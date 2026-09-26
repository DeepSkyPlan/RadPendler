import CloudKit
import Foundation

/// Die **Linien** der gefahrenen Fahrten, zwischen den eigenen Geräten.
///
/// Die Zahlen einer Fahrt reisen längst — sie liegen als Zusammenfassung im
/// iCloud-Schlüssel-Wert-Speicher, zusammen mit den Einstellungen. Die Linie
/// kann das nicht: der ganze Speicher fasst ein Megabyte für die App, und eine
/// einzige Linie sind achtzig Kilobyte. Deshalb steht bis heute unter einer auf
/// dem iPhone aufgezeichneten Fahrt auf dem iPad „nicht auf diesem Gerät".
///
/// CloudKit hat diese Grenze nicht. Je Fahrt ein Datensatz in der privaten
/// Datenbank, die Linie als `CKAsset` — als Datei, nicht als Feld: ein Feld
/// hört bei einem Megabyte auf, eine Tagestour nicht.
///
/// **Ohne Container ist alles hier ein stiller Nichtstuer.** Genau wie
/// `CloudStore`: keine Apple-ID, kein Container, kein Netz — dann bleibt die
/// Linie eben auf dem Gerät, auf dem sie gezeichnet wurde, und die App
/// verhält sich wie vorher. Was zum Einschalten fehlt, steht in `project.yml`
/// neben der auskommentierten Berechtigung.
actor TrackCloud {
    static let shared = TrackCloud()

    /// Muss genauso im Entwicklerportal stehen — und bleibt, wie er ist,
    /// auch wenn die App umzieht: ein Container ist eine eigenständige
    /// Kennung, keine Ableitung der Bundle-Id. Er trug `org.afjk` schon,
    /// bevor die App es tat.
    static let containerID = "iCloud.org.afjk.radpendler"

    static let recordType = "RideTrack"
    private static let assetKey = "track"

    private lazy var database = CKContainer(identifier: Self.containerID).privateCloudDatabase

    /// Einmal gescheitert heißt: es gibt keinen Container, oder keine Apple-ID,
    /// oder die App hat die Berechtigung nicht. Dann wird nicht bei jeder Fahrt
    /// neu gefragt — das kostet nur Zeit und Strom für dieselbe Absage.
    private var unavailable = false
    /// Woran das Hochladen zuletzt gescheitert ist — nil, solange alles geht.
    /// Ohne das war ein dauerhaft abgewiesener Upload **völlig stumm**: die
    /// Linie lag auf dem Gerät, die Fahrtenliste sah normal aus, und dass in
    /// der Wolke nie etwas ankam, merkte man erst im Dashboard. Genau so ist
    /// der erste Versuch untergegangen — in Production legt CloudKit keine
    /// Datensatztypen von selbst an, der Server wies ab, niemand sah es.
    private(set) var lastFailure: String?

    private func recordID(_ id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString)
    }

    // MARK: Hinauf

    /// Legt die Linie ab. Fehler sind hier folgenlos: die Linie liegt bereits
    /// auf der Platte, und eine Fahrt, deren Zeichnung nicht gereist ist, sieht
    /// auf dem anderen Gerät genauso aus wie bisher.
    func upload(_ track: RideTrack) async {
        guard !unavailable, let data = try? JSONEncoder().encode(track) else { return }
        // `CKAsset` will eine Datei. Sie wird nach dem Hochladen nicht mehr
        // gebraucht — anders als die Linie selbst, die im Fahrtenordner bleibt.
        let scratch = URL.temporaryDirectory.appending(path: "upload-\(track.id.uuidString).json")
        guard (try? data.write(to: scratch, options: [.atomic, .completeFileProtectionUnlessOpen])) != nil else { return }
        defer { try? FileManager.default.removeItem(at: scratch) }
        let record = CKRecord(recordType: Self.recordType, recordID: recordID(track.id))
        record[Self.assetKey] = CKAsset(fileURL: scratch)
        do {
            // `allKeys` und nicht `ifServerRecordUnchanged`: dieselbe Fahrt
            // zweimal abzulegen ist kein Konflikt, sondern derselbe Inhalt.
            _ = try await database.modifyRecords(saving: [record], deleting: [],
                                                 savePolicy: .allKeys, atomically: true)
            lastFailure = nil
        } catch {
            note(error)
            lastFailure = Self.reason(error)
        }
    }

    // MARK: Herunter

    /// Holt die Linie einer Fahrt, die auf einem anderen Gerät gezeichnet
    /// wurde. nil heißt weiterhin „nicht zu haben" — und die Detailansicht
    /// sagt das, statt eine leere Karte zu zeigen.
    func download(_ id: UUID) async -> RideTrack? {
        guard !unavailable else { return nil }
        do {
            let record = try await database.record(for: recordID(id))
            guard let asset = record[Self.assetKey] as? CKAsset, let url = asset.fileURL,
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(RideTrack.self, from: data)
        } catch {
            note(error)
            return nil
        }
    }

    // MARK: Weg

    /// Gelöscht wird ohne Rückfrage und ohne Folgen: ist der Datensatz schon
    /// weg, ist das Ziel erreicht.
    func delete(_ id: UUID) async {
        guard !unavailable else { return }
        do {
            _ = try await database.modifyRecords(saving: [], deleting: [recordID(id)])
        } catch {
            note(error)
        }
    }

    /// Was einmal grundsätzlich fehlt, fehlt für diesen Lauf. Ein einzelner
    /// Netzfehler zählt nicht dazu — der nächste Versuch kann klappen.
    /// In einem Satz, der in der Fahrtenliste Platz hat.
    static func reason(_ error: Error) -> String {
        guard let ck = error as? CKError else { return L("Die Linien reisen gerade nicht in deine iCloud.") }
        switch ck.code {
        case .notAuthenticated: return L("Die Linien bleiben auf dem Gerät: keine Apple-ID angemeldet.")
        case .quotaExceeded: return L("Die Linien bleiben auf dem Gerät: dein iCloud-Speicher ist voll.")
        case .networkUnavailable, .networkFailure: return L("Die Linien reisen, sobald wieder Netz da ist.")
        case .invalidArguments, .serverRejectedRequest, .constraintViolation:
            return L("Die Linien reisen nicht: iCloud kennt den Datensatztyp nicht (Schema nicht übernommen).")
        default: return L("Die Linien reisen gerade nicht in deine iCloud (%@).", String(describing: ck.code))
        }
    }

    private func note(_ error: Error) {
        guard let ck = error as? CKError else { return }
        switch ck.code {
        case .notAuthenticated, .badContainer, .badDatabase, .permissionFailure, .managedAccountRestricted:
            unavailable = true
        default:
            break
        }
    }
}
