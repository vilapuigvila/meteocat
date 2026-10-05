import XCTest
import CryptoKit
import Alfy
@testable import meteocatalf

/// Answers every request of a test session from `replies` and counts how many reached the "network", per URL
/// (the app host may use the shared session too while a test has it replaced, so a global count would be noisy).
private final class StubURLProtocol: URLProtocol {
    enum Reply {
        case page(String)
        case failure(URLError.Code)
    }

    private static let lock = NSLock()
    private static var replies: [String: Reply] = [:]
    private static var hits: [String: Int] = [:]

    static func reply(_ reply: Reply, for url: String) {
        lock.lock(); defer { lock.unlock() }
        replies[url] = reply
    }

    static func hits(for url: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return hits[url, default: 0]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        Self.lock.lock()
        Self.hits[url, default: 0] += 1
        let reply = Self.replies[url]
        Self.lock.unlock()

        switch reply {
        case .page(let html):
            // meteo.cat's own policy would make Alfy drop the page right away: only `.ignoreServer` keeps it.
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-cache"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(html.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
        }
    }
}

/// Drives the real Alfy cache (memory and disk) over a stub session, through `ServerData`.
final class ServerDataCacheTests: XCTestCase {

    private var namespace = ""

    override func setUp() {
        super.setUp()
        namespace = "meteocatalfTests-\(UUID().uuidString)"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        Requester.configureCache(
            CachedURLSession.Configuration(
                session: URLSession(configuration: configuration),
                cacheNamespace: namespace,
                isOnline: { true }
            )
        )
    }

    override func tearDown() {
        // Back to the defaults the app runs with, so other tests (and the app host) aren't affected.
        Requester.configureCache(CachedURLSession.Configuration())
        try? FileManager.default.removeItem(at: cacheDirectory)
        super.tearDown()
    }

    // MARK: - Helpers

    private func dailyPage(temp: String) -> String {
        """
        <html><body><div id="fitxa-ema"><h2>Orís</h2></div>
        <table><caption>Dades di&agrave;ries de l'estaci&oacute; meteorol&ograve;gica</caption><tbody>
          <tr><th scope="row">Temperatura mitjana</th><td colspan="2">\(temp)</td></tr>
        </tbody></table></body></html>
        """
    }

    private let stationsPage = """
        <html><body><script>var meta = {"CC":{"codi":"CC","nom":"oris","tipus":"A","coordenades":{"latitud":1.0,"longitud":2.0},\
        "emplacament":"x","altitud":1.0,"municipi":{"codi":"1","nom":"Oris"},"comarca":{"codi":1,"nom":"Osona"},"estats":[]}};</script></body></html>
        """

    private func url(for service: ServerData.Service) -> String {
        ServerData.makeRequest(for: service).urlString
    }

    private func temp(_ rows: [DTO.HomeStation]) -> String? {
        rows.first { $0.key == "Temperatura mitjana" }?.value
    }

    // MARK: Seeding Alfy's disk cache
    //
    // Alfy stamps entries with the real clock, so a page "stored before the day settled" for a day that already
    // settled can only be set up by writing the entry itself. This mirrors Alfy's private entry and file layout
    // (`Caches/<namespace>/<sha256("GET <url>")>.plist`); if Alfy changes it these tests fail loudly on the control step.

    private struct SeededEntry: Codable {
        let storedAt: Date
        let expiresAt: Date
        let data: Data
        let statusCode: Int
        let headers: [String: String]
        let mimeType: String?
        let textEncodingName: String?
    }

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(namespace, isDirectory: true)
    }

    private func seed(url: String, html: String, storedAt: Date, expiresAt: Date) throws {
        let entry = SeededEntry(
            storedAt: storedAt,
            expiresAt: expiresAt,
            data: Data(html.utf8),
            statusCode: 200,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            mimeType: "text/html",
            textEncodingName: "utf-8"
        )
        let key = SHA256.hash(data: Data("GET \(url)".utf8)).map { String(format: "%02x", $0) }.joined()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try encoder.encode(entry).write(to: cacheDirectory.appendingPathComponent(key).appendingPathExtension("plist"))
    }

    private func xCache(_ response: URLResponse) -> String? {
        (response as? HTTPURLResponse)?.allHeaderFields["X-Cache"] as? String
    }

    // MARK: - Tests -

    func testSecondDailyRequestInsideTheTTLMakesNoNetworkCall() async throws {
        // A day in progress, whatever the time zone of the machine running the tests.
        let date = Date().addingTimeInterval(2 * 24 * 3600)
        let service = ServerData.Service.requestStation(code: "HIT1", date: date)
        let pageURL = url(for: service)
        StubURLProtocol.reply(.page(dailyPage(temp: "17.0 °C")), for: pageURL)

        let first = try await ServerData.requestStation(code: "HIT1", date: date)
        let second = try await ServerData.requestStation(code: "HIT1", date: date)

        XCTAssertEqual(temp(first), "17.0 °C")
        XCTAssertEqual(second, first)
        XCTAssertEqual(StubURLProtocol.hits(for: pageURL), 1, "the second request must be answered by Alfy's cache")
    }

    func testStationListIsServedFromTheCacheUntilPullToRefresh() async throws {
        let pageURL = url(for: .stations(forceRefresh: false))
        StubURLProtocol.reply(.page(stationsPage), for: pageURL)

        let before = StubURLProtocol.hits(for: pageURL)
        let first: [DTO.Station] = try await ServerData.request(.stations(forceRefresh: false))
        XCTAssertEqual(first.map(\.code), ["CC"])
        let afterFirst = StubURLProtocol.hits(for: pageURL)
        XCTAssertEqual(afterFirst, before + 1)

        let _: [DTO.Station] = try await ServerData.request(.stations(forceRefresh: false))
        XCTAssertEqual(StubURLProtocol.hits(for: pageURL), afterFirst, "inside the TTL: no network call")

        let _: [DTO.Station] = try await ServerData.request(.stations(forceRefresh: true))
        XCTAssertEqual(StubURLProtocol.hits(for: pageURL), afterFirst + 1, "pull-to-refresh reaches the network")

        let _: [DTO.Station] = try await ServerData.request(.stations(forceRefresh: false))
        XCTAssertEqual(StubURLProtocol.hits(for: pageURL), afterFirst + 1, "the forced response was stored")
    }

    func testFinalDayStoredBeforeItSettledIsFetchedAgain() async throws {
        let day = DayKey(Date().addingTimeInterval(-3 * 24 * 3600))
        let date = day.localNoon()
        let service = ServerData.Service.requestStation(code: "SETTLE1", date: date)
        let pageURL = url(for: service)
        let settledAt = day.utcEnd.addingTimeInterval(DayKey.settleDelay)
        let now = Date()
        XCTAssertGreaterThan(now.timeIntervalSince(settledAt), 2 * 24 * 3600)

        // Stored half an hour before the day settled (a partial page), and still unexpired by its own lifetime.
        // `testFinalDayStoredAfterItSettledIsReused` is the counterpart: same entry, stored after the day settled.
        try seed(
            url: pageURL,
            html: dailyPage(temp: "10.0 °C"),
            storedAt: settledAt.addingTimeInterval(-1800),
            expiresAt: now.addingTimeInterval(3600)
        )
        StubURLProtocol.reply(.page(dailyPage(temp: "18.0 °C")), for: pageURL)

        let rows = try await ServerData.requestStation(code: "SETTLE1", date: date, now: now)
        XCTAssertEqual(temp(rows), "18.0 °C")
        XCTAssertEqual(StubURLProtocol.hits(for: pageURL), 1)
    }

    func testFinalDayStoredAfterItSettledIsReused() async throws {
        let day = DayKey(Date().addingTimeInterval(-3 * 24 * 3600))
        let date = day.localNoon()
        let pageURL = url(for: .requestStation(code: "SETTLE2", date: date))
        let settledAt = day.utcEnd.addingTimeInterval(DayKey.settleDelay)
        let now = Date()

        try seed(
            url: pageURL,
            html: dailyPage(temp: "17.0 °C"),
            storedAt: settledAt.addingTimeInterval(1800),
            expiresAt: now.addingTimeInterval(3600)
        )
        StubURLProtocol.reply(.page(dailyPage(temp: "18.0 °C")), for: pageURL)

        let rows = try await ServerData.requestStation(code: "SETTLE2", date: date, now: now)
        XCTAssertEqual(temp(rows), "17.0 °C")
        XCTAssertEqual(StubURLProtocol.hits(for: pageURL), 0)
    }

    func testFailedDailyRequestThrowsInsteadOfServingTheStalePage() async throws {
        let day = DayKey(Date().addingTimeInterval(-3 * 24 * 3600))
        let date = day.localNoon()
        let pageURL = url(for: .requestStation(code: "STALE1", date: date))
        let settledAt = day.utcEnd.addingTimeInterval(DayKey.settleDelay)

        // An expired partial page, stored before the day settled.
        let storedAt = settledAt.addingTimeInterval(-1800)
        try seed(url: pageURL, html: dailyPage(temp: "10.0 °C"), storedAt: storedAt, expiresAt: storedAt.addingTimeInterval(3600))
        StubURLProtocol.reply(.failure(.notConnectedToInternet), for: pageURL)

        // Control: with Alfy's default (stale on error) the same failure returns that partial page.
        let stale = try await Requester.makeRequest(pageURL).send()
        XCTAssertEqual(xCache(stale.urlResponse), "STALE")
        XCTAssertEqual(String(data: stale.data, encoding: .utf8)?.contains("10.0 °C"), true)

        do {
            let rows = try await ServerData.requestStation(code: "STALE1", date: date)
            XCTFail("expected an error, got \(rows)")
        } catch Requester.ErrorReason.noInternetConnection {
            // the network error, not the cached page
        }
    }
}
