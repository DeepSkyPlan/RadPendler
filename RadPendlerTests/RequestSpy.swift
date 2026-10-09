import Foundation

/// Schreibt mit, was eine Planung wirklich ans Netz schickt — für die
/// Live-Tests (`BikeLiveTests`), die sonst nur das Ergebnis sehen. Jede Anfrage
/// geht unverändert weiter; festgehalten werden Dienst, Art, Status, Größe und
/// Dauer, nie die Adresse mit ihren Koordinaten.
final class RequestSpy: URLProtocol {
    struct Entry { var host: String, what: String, status: Int, bytes: Int, seconds: Double, at: Double }

    private static let lock = NSLock()
    private static var entries: [Entry] = []
    private static var began = Date()
    private static let marker = "RequestSpy.seen"
    private static let forward = URLSession(configuration: .ephemeral)

    static func start() {
        lock.lock(); entries = []; began = .now; lock.unlock()
        URLProtocol.registerClass(RequestSpy.self)
    }

    /// Was seit `start()` hinausging, in der Reihenfolge des Abschlusses.
    static func stop() -> [Entry] {
        URLProtocol.unregisterClass(RequestSpy.self)
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme, scheme.hasPrefix("http") else { return false }
        return URLProtocol.property(forKey: marker, in: request) == nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var running: URLSessionDataTask?

    override func startLoading() {
        let copy = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: Self.marker, in: copy)
        // Der Rumpf einer POST-Anfrage kommt hier als Strom an, nicht als Daten.
        if copy.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var body = Data(), buffer = [UInt8](repeating: 0, count: 16_384)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
            copy.httpBody = body
        }
        let started = Date()
        let url = request.url
        let what = Self.kind(url, method: request.httpMethod ?? "GET")
        running = Self.forward.dataTask(with: copy as URLRequest) { [weak self] data, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            Self.lock.lock()
            Self.entries.append(Entry(host: url?.host ?? "?", what: what, status: error == nil ? status : -1,
                                      bytes: data?.count ?? 0, seconds: Date().timeIntervalSince(started),
                                      at: started.timeIntervalSince(Self.began)))
            Self.lock.unlock()
            if let error { self.client?.urlProtocol(self, didFailWithError: error); return }
            if let response { self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
            if let data { self.client?.urlProtocol(self, didLoad: data) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        running?.resume()
    }

    override func stopLoading() { running?.cancel() }

    /// „BRouter Profil hochladen", „BRouter Route (trekking)" — ohne Koordinaten.
    private static func kind(_ url: URL?, method: String) -> String {
        guard let url else { return "?" }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if url.host == "brouter.de" {
            if url.path.hasSuffix("/profile") { return "Profil hochladen" }
            let profile = items.first { $0.name == "profile" }?.value ?? "?"
            let points = (items.first { $0.name == "lonlats" }?.value ?? "").split(separator: "|").count
            return "Route (\(profile.hasPrefix("custom_") ? "eigenes Profil" : profile), \(points) Punkte)"
        }
        return "\(method) \(url.path)"
    }
}
