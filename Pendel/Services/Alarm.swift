import AudioToolbox
import UIKit

/// The countdown's warning: a short system sound plus a nudge, so it works
/// with the phone on the table and in a pocket.
enum Alarm {
    static func beep() {
        AudioServicesPlaySystemSound(1057)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
