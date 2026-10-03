import SwiftUI
import TipKit

/// Der Knopf „Pendeln“ in der Kopfzeile (bis 1.10.2 ein Doppeltipp) setzt die
/// Pendelstrecke ein — und was er tut, sieht man dem Haus allein nicht an. Er stand bis 1.9.1 nur in der Anleitung, und wer die
/// nicht liest, tippte jeden Morgen Start und Ziel von Hand.
///
/// Einmal, als Sprechblase an der Kopfzeile, und erst ab dem dritten Öffnen:
/// beim ersten Start fehlen ohnehin noch Zuhause und Arbeit, ohne die der
/// Knopf nichts weiß. Wer ihn einmal benutzt hat, sieht ihn nie wieder.
struct QuickCommuteTip: Tip {
    static let opened = Tips.Event(id: "appOpened")
    /// Zuhause und Arbeit sind gesetzt — sonst gibt es nichts einzusetzen.
    @Parameter static var hasCommute: Bool = false

    /// Neue Kennung seit dem Knopf (1.10.3): wer den alten Hinweis zum
    /// Doppeltipp schon weggetippt hat, soll den neuen trotzdem einmal sehen.
    var id: String { "commuteButton" }
    var title: Text { Text(L("Pendelstrecke")) }
    var message: Text? {
        Text(L("Dieser Knopf setzt deinen Standort als Start und Zuhause oder Arbeit als Ziel."))
    }
    var image: Image? { Image(systemName: "house.and.flag.fill") }

    var rules: [Rule] {
        #Rule(Self.$hasCommute) { $0 == true }
        #Rule(Self.opened) { $0.donations.count >= 3 }
    }
}
