import XCTest
import MapKit
@testable import meteocatalf

/// The Radar tab: what RainViewer answers, where its tiles are, and the view model that picks the frames.
@MainActor
final class WeatherMapTests: XCTestCase {

    // A trimmed answer of https://api.rainviewer.com/public/weather-maps.json (frames out of order on purpose).
    private let json = """
    {
      "version": "2.0",
      "generated": 1791147023,
      "host": "https://tilecache.rainviewer.com",
      "radar": {
        "past": [
          {"time": 1791140400, "path": "/v2/radar/71a424d19da0"},
          {"time": 1791139800, "path": "/v2/radar/f73f910b7e10"},
          {"time": 1791147000, "path": "/v2/radar/e8a6e4be457c"}
        ],
        "nowcast": []
      },
      "satellite": {"infrared": []}
    }
    """

    private func maps() throws -> RadarMaps {
        RadarMaps(try JSONDecoder().decode(DTO.RainViewerMaps.self, from: Data(json.utf8)))
    }

    private func frame(_ minutes: Int) -> RadarFrame {
        RadarFrame(time: Date(timeIntervalSince1970: 1_791_139_800 + Double(minutes) * 60), path: "/v2/radar/frame\(minutes)")
    }

    // MARK: - The answer -

    func testTheAnswerIsReadIgnoringWhatTheAppDoesNotUse() throws {
        let maps = try maps()

        XCTAssertEqual(maps.host, "https://tilecache.rainviewer.com")
        XCTAssertEqual(maps.frames.count, 3)
    }

    func testFramesAreOldestFirstWithTheirTimes() throws {
        let frames = try maps().frames

        XCTAssertEqual(frames.map(\.path), ["/v2/radar/f73f910b7e10", "/v2/radar/71a424d19da0", "/v2/radar/e8a6e4be457c"])
        XCTAssertEqual(frames.first?.time, Date(timeIntervalSince1970: 1_791_139_800))
        XCTAssertEqual(frames.last?.time, Date(timeIntervalSince1970: 1_791_147_000))
    }

    func testAnAnswerWithoutRadarCannotBeRead() {
        XCTAssertThrowsError(try JSONDecoder().decode(DTO.RainViewerMaps.self, from: Data(#"{"host": "https://x"}"#.utf8)))
    }

    // MARK: - Tile URL -

    func testTileURLIsHostPathSizeZoomColumnRow() {
        let url = WeatherMapTiles.radarURL(host: "https://tilecache.rainviewer.com", frame: frame(0), z: 7, x: 64, y: 47)
        XCTAssertEqual(url?.absoluteString, "https://tilecache.rainviewer.com/v2/radar/frame0/256/7/64/47/2/1_0.png")
    }

    /// Unlike meteo.cat's, rows count from the top, as in MapKit: nothing is flipped.
    func testTileURLKeepsMapKitsRow() {
        let url = WeatherMapTiles.radarURL(host: "https://h", frame: frame(0), z: 3, x: 4, y: 1)
        XCTAssertEqual(url?.lastPathComponent, "1_0.png")
        XCTAssertTrue(url?.absoluteString.contains("/256/3/4/1/") == true)
    }

    // MARK: - Overlay -

    func testOverlaysOfDifferentFramesAreDifferentToMapKit() {
        let one = RadarTileOverlay(frame: frame(0), host: "https://h")
        let same = RadarTileOverlay(frame: frame(0), host: "https://h")
        let other = RadarTileOverlay(frame: frame(10), host: "https://h")

        XCTAssertTrue(one.isEqual(same))
        XCTAssertEqual(one.hash, same.hash)
        XCTAssertFalse(one.isEqual(other))
    }

    /// Past zoom 7 RainViewer answers a "Zoom Level Not Supported" picture, so those tiles are asked at zoom 7 instead.
    func testCloserZoomsAskForTheZoomSevenTileThatContainsThem() {
        let overlay = RadarTileOverlay(frame: frame(0), host: "https://h")

        // zoom 9 tile (258, 190) lives in the zoom 7 tile (64, 47)
        let url = overlay.url(forTilePath: MKTileOverlayPath(x: 258, y: 190, z: 9, contentScaleFactor: 1))
        XCTAssertTrue(url.absoluteString.contains("/256/7/64/47/"), url.absoluteString)
        XCTAssertEqual(overlay.maximumZ, 7 + 4)
    }

    // MARK: - View model -

    private struct Offline: Error {}

    private func makeViewModel(_ answer: Result<RadarMaps, Error>, now: @escaping () -> Date = { Date() }) -> WeatherMapViewModel {
        WeatherMapViewModel(loadMaps: { try answer.get() }, now: now)
    }

    func testLoadShowsTheNewestImage() async throws {
        let viewModel = makeViewModel(.success(try maps()))

        await viewModel.load()

        XCTAssertEqual(viewModel.host, "https://tilecache.rainviewer.com")
        XCTAssertEqual(viewModel.frames.count, 3)
        XCTAssertEqual(viewModel.currentFrame, viewModel.frames.last)
        XCTAssertFalse(viewModel.failed)
    }

    func testLoadFailureWithNothingToShowIsReported() async {
        let viewModel = makeViewModel(.failure(Offline()))

        await viewModel.load()

        XCTAssertTrue(viewModel.failed)
        XCTAssertTrue(viewModel.frames.isEmpty)
    }

    func testAnAnswerWithoutFramesIsAFailure() async {
        let viewModel = makeViewModel(.success(RadarMaps(host: "https://h", frames: [])))

        await viewModel.load()

        XCTAssertTrue(viewModel.failed)
    }

    func testLoadFailureKeepsTheImagesAlreadyShown() async throws {
        var answer: Result<RadarMaps, Error> = .success(try maps())
        var clock = Date()
        let viewModel = WeatherMapViewModel(loadMaps: { try answer.get() }, now: { clock })
        await viewModel.load()

        answer = .failure(Offline())
        clock = clock.addingTimeInterval(600)
        await viewModel.load()

        XCTAssertEqual(viewModel.frames.count, 3)
        XCTAssertFalse(viewModel.failed)
    }

    func testPlayStartsOverFromTheOldestImageWhenOnTheNewest() async throws {
        let viewModel = makeViewModel(.success(try maps()))
        await viewModel.load()
        XCTAssertEqual(viewModel.frameIndex, 2)

        viewModel.togglePlay()
        XCTAssertTrue(viewModel.isPlaying)
        XCTAssertEqual(viewModel.frameIndex, 0)

        viewModel.togglePlay()
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testPlayAdvancesThroughTheFrames() async throws {
        let viewModel = makeViewModel(.success(try maps()))
        await viewModel.load()

        viewModel.togglePlay()
        try await Task.sleep(nanoseconds: 800_000_000)
        viewModel.pause()

        XCTAssertGreaterThan(viewModel.frameIndex, 0)
    }

    func testLoadAgainSoonDoesNotAskAgain() async throws {
        var asked = 0
        let answer = try maps()
        let viewModel = WeatherMapViewModel(loadMaps: { asked += 1; return answer }, now: { Date() })

        await viewModel.load()
        await viewModel.load()

        XCTAssertEqual(asked, 1)
    }

    func testANewImageMovesTheViewToItWhenTheOldestWasOnTheNewest() async throws {
        var answer = try maps()
        var clock = Date()
        let viewModel = WeatherMapViewModel(loadMaps: { answer }, now: { clock })
        await viewModel.load()

        let newer = RadarFrame(time: Date(timeIntervalSince1970: 1_791_147_600), path: "/v2/radar/newer")
        answer = RadarMaps(host: answer.host, frames: Array(answer.frames.dropFirst()) + [newer])
        clock = clock.addingTimeInterval(600)
        await viewModel.load()

        XCTAssertEqual(viewModel.currentFrame, newer)
    }
}

/// The compass point shown beside the user on the radar map.
final class CompassTests: XCTestCase {

    func testTheEightPoints() {
        let expected = [0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"]
        for (degrees, name) in expected {
            XCTAssertEqual(Compass.point(for: Double(degrees)), name, "\(degrees)°")
        }
    }

    func testEachPointCoversTwentyTwoAndAHalfDegreesEitherSide() {
        XCTAssertEqual(Compass.point(for: 22.4), "N")
        XCTAssertEqual(Compass.point(for: 22.6), "NE")
        XCTAssertEqual(Compass.point(for: 337.4), "NW")
        XCTAssertEqual(Compass.point(for: 337.6), "N")
    }

    func testNegativeAndLargeAnglesGoRoundTheCircle() {
        XCTAssertEqual(Compass.point(for: -90), "W")
        XCTAssertEqual(Compass.point(for: 450), "E")
        XCTAssertEqual(Compass.point(for: 360), "N")
    }

    func testTextShowsThePointAndTheRoundedDegrees() {
        XCTAssertEqual(Compass.text(for: 314.6), "NW 315°")
        XCTAssertEqual(Compass.text(for: 359.7), "N 0°")
        XCTAssertEqual(Compass.text(for: -90), "W 270°")
    }
}
