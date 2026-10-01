import Foundation

/// Whether the screen may turn with the phone, or has to stay as it is.
enum OrientationLock: String, CaseIterable, Codable {
    case auto, portrait, landscape

    var title: String {
        switch self {
        case .auto: L("Automatisch")
        case .portrait: L("Hochkant")
        case .landscape: L("Querformat")
        }
    }

    var symbol: String {
        switch self {
        case .auto: "rotate.right"
        case .portrait: "iphone"
        case .landscape: "iphone.landscape"
        }
    }

    /// Tap order of the button on the ride screen.
    var next: OrientationLock {
        switch self {
        case .auto: .portrait
        case .portrait: .landscape
        case .landscape: .auto
        }
    }
}
