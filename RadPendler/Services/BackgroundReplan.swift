import BackgroundTasks
import Foundation
import UIKit

/// Hält die Warnungen richtig, während die App zu ist.
///
/// Die Warnungen stehen als `UNTimeIntervalNotificationTrigger` fest, sobald
/// ein Plan da ist — und ein Fahrplan ändert sich danach noch. Fährt der Zug
/// fünf Minuten später als beim letzten Öffnen bekannt, klingelt es fünf
/// Minuten zu früh und man steht auf dem Bahnsteig herum; fährt er früher,
/// klingelt es zu spät, und das ist schlimmer.
///
/// Die App darf im Hintergrund nicht rechnen, wann sie will, aber sie darf
/// fragen. `BGAppRefreshTask` weckt sie gelegentlich — iOS entscheidet wann,
/// nach Tageszeit und Gewohnheit —, und die paar Sekunden reichen für eine
/// Neuplanung und ein Nachstellen der Warnungen.
///
/// Geplant wird dabei **dieselbe Frage**, die auf dem Bildschirm stand: dieselbe
/// Kategorie, dieselbe Abfahrt oder Ankunft. Eine geweckte App, die sich selbst
/// eine andere Verbindung sucht, warnt zuverlässig vor dem falschen Zug.
enum BackgroundReplan {
    /// Muss genauso in `BGTaskSchedulerPermittedIdentifiers` stehen
    /// (`RadPendlerInfo.plist`), sonst lehnt iOS die Anmeldung ab.
    static let taskID = "de.keese.radpendler.replan"

    /// Frühestens so viel später wieder. Es ist eine Bitte, keine Zusage: iOS
    /// weckt, wenn es ihm passt, und gar nicht, wenn der Nutzer die
    /// Hintergrundaktualisierung abgeschaltet hat.
    static let interval: TimeInterval = 15 * 60

    // MARK: Die Frage, auf die die Warnungen antworten

    /// Was der Countdown zählt. Liegt in den UserDefaults, damit die geweckte
    /// App dieselbe Frage stellt und nicht irgendeine. Reist **nicht** nach
    /// iCloud: welcher Zug auf diesem Bildschirm steht, geht das iPad nichts an.
    struct Question: Codable, Equatable {
        /// `TravelMode.rawValue`
        var mode: String
        /// nil heißt „jetzt los".
        var date: Date?
        var isArrival: Bool
    }

    private static let key = "countdownQuestion"

    static var remembered: Question? {
        UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(Question.self, from: $0) }
    }

    /// nil löscht sie — dann gibt es nichts nachzustellen und die App lässt
    /// sich auch nicht mehr dafür wecken.
    static func remember(_ question: Question?) {
        guard question != remembered else { return }
        if let question, let data = try? JSONEncoder().encode(question) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Die laufenden Einstellungen. Wird die App für die Aufgabe frisch
    /// gestartet, gibt es sie noch nicht — dann werden sie gelesen. Im
    /// Normalfall wird die vorhandene Instanz gefragt, statt eine zweite zu
    /// bauen, die dieselben Schlüssel ein zweites Mal schreibt.
    @MainActor static var live: (() -> AppSettings)?

    // MARK: An- und abmelden

    /// Muss beim Start laufen, bevor das Starten fertig ist — danach nimmt
    /// `BGTaskScheduler` die Anmeldung nicht mehr an.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { return task.setTaskCompleted(success: false) }
            handle(refresh)
        }
    }

    /// Meldet die nächste Gelegenheit an. Ohne etwas zu zählen wird nichts
    /// angemeldet: eine Weckzeit für eine Frage, die niemand gestellt hat,
    /// kostet nur Strom.
    static func schedule(after seconds: TimeInterval = interval) {
        guard remembered != nil else { return BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID) }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Die nächste Gelegenheit sofort anmelden. Eine Aufgabe, die sich nicht
        // selbst wieder anmeldet, läuft genau einmal.
        schedule()
        let work = Task {
            await run()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        // iOS gibt der Aufgabe wenige Sekunden. Läuft die Zeit ab, wird
        // abgebrochen — die alten Warnungen bleiben dann stehen, was allemal
        // besser ist als gar keine.
        task.expirationHandler = { work.cancel() }
    }

    // MARK: Nachstellen

    /// Einer statt einer je Wecken: `MapKitRouter` und `CompositeRouter`
    /// haben Zwischenspeicher, und ein frisch gebauter Planer hat leere.
    @MainActor private static let planner = TripPlanner()

    @MainActor static func run() async {
        guard let question = remembered else { return }
        let settings = live?() ?? AppSettings()
        guard let origin = settings.origin, let destination = settings.destination else { return }
        let target: PlanTarget = question.isArrival ? .arriveBy(question.date ?? .now)
                                                    : .departAfter(question.date ?? .now)
        // Nur die Kategorie, auf die der Countdown zählt — und derselbe
        // Planer wie beim letzten Wecken, damit seine Zwischenspeicher das
        // Wecken überleben.
        let result = await Self.planner.plan(PlanRequest(origin: origin, destination: destination,
                                                         target: target, settings: settings.snapshot),
                                             only: TravelMode(rawValue: question.mode))
        guard !Task.isCancelled, let option = option(for: question, in: result.options) else { return }
        await Alarm.schedule(for: option, alerts: settings.alertsOn ? settings.alertMinutes : [])
    }

    /// Welche Möglichkeit die geweckte App nachstellt: die beste ihrer
    /// Kategorie, Alternativen zuletzt — dieselbe Reihenfolge, die der
    /// Bildschirm zeigt, und dieselbe Regel, nach der `PlanModel` entscheidet,
    /// ob es überhaupt etwas zu zählen gibt.
    ///
    /// Rein, damit die Regel geprüft werden kann, ohne die App zu wecken.
    static func option(for question: Question, in options: [TripOption]) -> TripOption? {
        let own = TripRules.ordered(options.filter { $0.mode.rawValue == question.mode })
        guard let option = own.first else { return nil }
        // Rad und Auto mit „jetzt los" haben keine feste Abfahrt; da gibt es
        // nichts nachzustellen, und eine Warnung wäre erfunden.
        guard TripRules.countsDown(option, arrivalSearch: question.isArrival) else { return nil }
        return option
    }
}

extension AppDelegate {
    /// Kein Standardargument: der Selektor muss genau
    /// `application:didFinishLaunchingWithOptions:` heißen, sonst ruft UIKit
    /// ihn nicht — und `register` **muss** hier laufen. Später angemeldet,
    /// nimmt `BGTaskScheduler` die Kennung nicht mehr an.
    ///
    /// Das Gegenstück, `applicationDidEnterBackground`, steht bewusst nicht
    /// hier: eine App mit Szenen bekommt es nie zu sehen. Angemeldet wird über
    /// `scenePhase` in `RadPendlerApp`.
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        BackgroundReplan.register()
        return true
    }
}
