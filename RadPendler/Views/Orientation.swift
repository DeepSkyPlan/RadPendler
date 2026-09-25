import SwiftUI
import UIKit

/// The one thing SwiftUI has no say over: which way up the app may be.
/// `supportedInterfaceOrientations` is asked of the app delegate, so there has
/// to be one — it does nothing else.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Read by UIKit on every rotation. Set through `OrientationLock.apply()`.
    static var lock: UIInterfaceOrientationMask = .all

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.lock
    }
}

extension OrientationLock {
    var mask: UIInterfaceOrientationMask {
        switch self {
        case .auto: .all
        case .portrait: .portrait
        case .landscape: .landscape
        }
    }

    /// Takes effect at once: the mask alone only decides what happens at the
    /// *next* rotation, so the scene is asked to turn as well.
    ///
    /// Not in `auto`, though. Asking for a geometry update with "any
    /// orientation" pins whatever the device happens to be in at that moment,
    /// and the app then stops following the phone at all — which is the exact
    /// opposite of what "automatisch" says.
    @MainActor func apply() {
        AppDelegate.lock = mask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        guard self != .auto else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}

/// Der dunkle Bildschirm während einer Fahrt.
///
/// Der Bildschirm ist der größte Stromfresser einer Aufzeichnung — größer als
/// der GPS-Empfänger —, und er bleibt eine Fahrt lang an, weil ein Blick auf
/// die Karte an der Kreuzung nichts nützt, wenn man vorher entsperren muss.
/// iOS hilft hier nicht: mit abgeschaltetem Ruhezustand dimmt es von sich aus
/// gar nichts. Also dimmt die App selbst — sie stellt die Helligkeit herunter
/// und beim ersten Antippen wieder her, so wie es jedes Navigationsgerät tut.
///
/// `UIScreen.brightness` ist **systemweit**: was hier gesetzt wird, gilt auch
/// für alles andere. Deshalb wird der Wert von vorher gemerkt und in jedem
/// Ausgang wieder eingesetzt — Fahrtende, Pause, App in den Hintergrund.
@MainActor
@Observable
final class ScreenDim {
    private(set) var dimmed = false
    /// Die Helligkeit, die der Nutzer eingestellt hatte.
    private var original: CGFloat?

    /// So viel bleibt übrig: ein Viertel, aber nie unter 8 % — darunter ist
    /// der Bildschirm bei Sonne schwarz und man findet den Knopf nicht mehr,
    /// mit dem man ihn wieder hell macht. Und nie **heller** als vorher: wer
    /// sein Telefon auf 5 % stehen hat, will nicht, dass das Abdunkeln es
    /// aufhellt.
    nonisolated static func level(of original: CGFloat) -> CGFloat {
        Swift.min(original, Swift.max(0.08, original * 0.25))
    }

    func dim() {
        guard !dimmed else { return }
        let now = UIScreen.main.brightness
        original = now
        dimmed = true
        UIScreen.main.brightness = Self.level(of: now)
    }

    /// Wieder hell. Nur, wenn wir selbst gedimmt haben — sonst überschriebe
    /// das eine Helligkeit, die der Nutzer inzwischen von Hand gestellt hat.
    func wake() {
        guard dimmed, let original else { return }
        dimmed = false
        self.original = nil
        UIScreen.main.brightness = original
    }
}

/// Cycles automatic → hochkant → querformat. Sits on the ride screen, where a
/// phone on a handlebar must not turn itself while one leans into a corner.
struct OrientationButton: View {
    @Binding var lock: OrientationLock

    var body: some View {
        Button {
            lock = lock.next
            lock.apply()
        } label: {
            Image(systemName: lock.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(lock == .auto ? Theme.accent : .white)
                .frame(width: 36, height: 36)
                .background(lock == .auto ? AnyShapeStyle(.regularMaterial)
                                          : AnyShapeStyle(Theme.gradient(Theme.accent)), in: Circle())
        }
        .accessibilityLabel("Ausrichtung: \(lock.title). Tippen für \(lock.next.title).")
    }
}
