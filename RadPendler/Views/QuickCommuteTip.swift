import SwiftUI
import TipKit

/// Der Doppeltipp auf die Kopfzeile setzt die Pendelstrecke ein — und sieht
/// man ihm nicht an. Er stand bis 1.9.1 nur in der Anleitung, und wer die
/// nicht liest, tippte jeden Morgen Start und Ziel von Hand.
///
/// Einmal, als Sprechblase an der Kopfzeile, und erst ab dem dritten Öffnen:
/// beim ersten Start fehlen ohnehin noch Zuhause und Arbeit, ohne die der
/// Doppeltipp nichts weiß. Wer ihn einmal benutzt hat, sieht ihn nie wieder.
struct QuickCommuteTip: Tip {
    static let opened = Tips.Event(id: "appOpened")
    /// Zuhause und Arbeit sind gesetzt — sonst gibt es nichts einzusetzen.
    @Parameter static var hasCommute: Bool = false

    var title: Text { Text(L("Doppeltipp: Pendelstrecke")) }
    var message: Text? {
        Text(L("Zweimal auf diese Box tippen setzt deinen Standort als Start und Zuhause oder Arbeit als Ziel."))
    }
    var image: Image? { Image(systemName: "hand.tap") }

    var rules: [Rule] {
        #Rule(Self.$hasCommute) { $0 == true }
        #Rule(Self.opened) { $0.donations.count >= 3 }
    }
}
