import Foundation

/// Wie sich die App bei den Diensten vorstellt, die sie fragt.
///
/// Ein Satz für alle: Name, Fassung, was sie ist, und wo man jemanden
/// erreicht. Die Dienste dahinter sind Gemeinschaftsprojekte ohne Vertrag —
/// wer dort eine auffällige App sieht, soll sie zuordnen und den Betreiber
/// anschreiben können, statt sie auszusperren. Bis 1.16 stand bei BRouter,
/// Overpass und Open-Meteo „private commute planner": das stimmte, solange die
/// App auf einem einzigen Telefon lief, und seit dem Store nicht mehr.
enum AppIdentity {
    static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "RadPendler/\(version) (Commute App; +https://github.com/DeepSkyPlan/RadPendler)"
    }
}
