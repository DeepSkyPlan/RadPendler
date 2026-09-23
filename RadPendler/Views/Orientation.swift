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
