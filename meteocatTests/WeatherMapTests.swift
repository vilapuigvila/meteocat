import XCTest
@testable import meteocat

/// The Radar tab: where its tiles come from, the times they are asked for, and the view model that picks the frames.
@MainActor
final class WeatherMapTests: XCTestCase {

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    // MARK: - Radar frames -

    func testFramesCoverTheLastHourEveryAndEndAtTheNewestImage() {
        let frames = WeatherMapTiles.radarFrames(latest: utc(2026, 10, 4, 18, 12))

        XCTAssertEqual(frames.count, 11)
        XCTAssertEqual(frames.first, utc(2026, 10, 4, 17, 12))
        XCTAssertEqual(frames.last, utc(2026, 10, 4, 18, 12))
        XCTAssertEqual(Set(zip(frames, frames.dropFirst()).map { $1.timeIntervalSince($0) }), [360])
    }

    func testFramesSnapToTheSixMinuteStep() {
        let frames = WeatherMapTiles.radarFrames(latest: utc(2026, 10, 4, 18, 14, 40))
        XCTAssertEqual(frames.last, utc(2026, 10, 4, 18, 12))
    }

    func testFramesCrossMidnightInUTC() {
        let frames = WeatherMapTiles.radarFrames(latest: utc(2026, 10, 5, 0, 12))
        XCTAssertEqual(frames.first, utc(2026, 10, 4, 23, 12))
    }

    // MARK: - Radar tile URL -

    /// meteo.cat counts tile rows from the bottom, MapKit from the top: row 47 of 128 is row 80 for the server.
    func testRadarTileURLFlipsTheRowAndPadsTheNumbers() {
        let url = WeatherMapTiles.radarURL(time: utc(2026, 10, 4, 18, 6), z: 7, x: 64, y: 47)
        XCTAssertEqual(url?.absoluteString, "https://static-m.meteo.cat/tiles/radar/2026/10/04/18/06/07/000/000/064/000/000/080.png")
    }

    func testRadarTileURLUsesUTCForTheTimeOfTheImage() {
        let url = WeatherMapTiles.radarURL(time: utc(2026, 1, 2, 3, 0), z: 5, x: 1, y: 0)
        XCTAssertEqual(url?.absoluteString, "https://static-m.meteo.cat/tiles/radar/2026/01/02/03/00/05/000/000/001/000/000/031.png")
    }

    // MARK: - Satellite tile URL -

    func testSatelliteTileURLAsksForTheWholeWorldAtZoomZero() throws {
        let url = try XCTUnwrap(WeatherMapTiles.satelliteURL(.colour, time: utc(2026, 10, 4, 18), z: 0, x: 0, y: 0))
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(url.host, "view.eumetsat.int")
        XCTAssertEqual(items["layers"], "mtg_fd:rgb_geocolour")
        XCTAssertEqual(items["crs"], "EPSG:3857")
        XCTAssertEqual(items["time"], "2026-10-04T18:00:00Z")
        XCTAssertEqual(items["width"], "256")
        let box = (items["bbox"] ?? "").split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(box.count, 4)
        XCTAssertEqual(box[0], -20_037_508.34, accuracy: 0.01)
        XCTAssertEqual(box[1], -20_037_508.34, accuracy: 0.01)
        XCTAssertEqual(box[2], 20_037_508.34, accuracy: 0.01)
        XCTAssertEqual(box[3], 20_037_508.34, accuracy: 0.01)
    }

    /// The second tile of the top row at zoom 1 is the north-east quarter.
    func testSatelliteTileURLBoxFollowsTheTileOrigin() throws {
        let url = try XCTUnwrap(WeatherMapTiles.satelliteURL(.infrared, time: utc(2026, 10, 4, 18), z: 1, x: 1, y: 0))
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let box = (items["bbox"] ?? "").split(separator: ",").compactMap { Double($0) }

        XCTAssertEqual(items["layers"], "mtg_fd:ir105_hrfi")
        XCTAssertEqual(items["styles"], "mtg_fd_ir105_hrfi_grayscale")
        XCTAssertEqual(box, [0, 0, 20_037_508.342789244, 20_037_508.342789244])
    }

    func testEstimatedSatelliteTimeIsFortyMinutesBackOnATenMinuteStep() {
        XCTAssertEqual(WeatherMapTiles.estimatedLatestSatellite(now: utc(2026, 10, 4, 18, 37)), utc(2026, 10, 4, 17, 50))
    }

    // MARK: - Reading the times -

    func testRadarTimeIsReadFromThePageScript() {
        let html = """
        <script>
            Meteocat.tempsActual.init({
                id: 'map',
                dataServidor: '10/04/2026 18:19Z',
                dataDarreraRadar: '10/04/2026 18:06Z',
                dataDarreraAdveccio: '2026-10-04T18:06:00+00:00'
            });
        </script>
        """
        XCTAssertEqual(ServerData.parseRadarTime(html: html), utc(2026, 10, 4, 18, 6))
    }

    func testRadarTimeIsNilWhenThePageChanges() {
        XCTAssertNil(ServerData.parseRadarTime(html: "<html><body>no script</body></html>"))
        XCTAssertNil(ServerData.parseRadarTime(html: "dataDarreraRadar: ''"))
    }

    func testSatelliteTimeIsTheEndOfTheGeoColourDimension() {
        let xml = """
        <Layer queryable="1"><Name>rgb_cloudphase</Name>
          <Dimension name="time" units="ISO8601" default="2026-10-04T17:50:00Z">2024-09-23T00:00:00.000Z/2026-10-04T17:50:00.000Z/PT10M</Dimension></Layer>
        <Layer queryable="1"><Name>rgb_geocolour</Name><Title>GeoColour</Title>
          <Dimension name="time" units="ISO8601" default="2026-10-04T18:20:00Z" nearestValue="1">2024-09-23T00:00:00.000Z/2026-10-04T18:20:00.000Z/PT10M</Dimension></Layer>
        """
        XCTAssertEqual(ServerData.parseSatelliteTime(capabilities: xml), utc(2026, 10, 4, 18, 20))
    }

    func testSatelliteTimeIsNilWithoutTheLayer() {
        XCTAssertNil(ServerData.parseSatelliteTime(capabilities: "<Layer><Name>rgb_dust</Name></Layer>"))
    }

    // MARK: - View model -

    private struct Offline: Error {}

    private func makeViewModel(radar: Date? = nil, satellite: Date? = nil, now: Date) -> WeatherMapViewModel {
        WeatherMapViewModel(
            latestRadar: { if let radar { return radar } else { throw Offline() } },
            latestSatellite: { if let satellite { return satellite } else { throw Offline() } },
            now: { now }
        )
    }

    func testLoadShowsTheNewestRadarImageAndTheSatelliteTime() async {
        let viewModel = makeViewModel(radar: utc(2026, 10, 4, 18, 12), satellite: utc(2026, 10, 4, 18, 0), now: utc(2026, 10, 4, 18, 30))

        await viewModel.load()

        XCTAssertEqual(viewModel.frames.count, 11)
        XCTAssertEqual(viewModel.currentFrame, utc(2026, 10, 4, 18, 12))
        XCTAssertEqual(viewModel.satelliteTime, utc(2026, 10, 4, 18, 0))
    }

    func testLoadEstimatesTheTimesWhenTheServersDoNotAnswer() async {
        let now = utc(2026, 10, 4, 18, 37)
        let viewModel = makeViewModel(now: now)

        await viewModel.load()

        XCTAssertEqual(viewModel.currentFrame, WeatherMapTiles.radarFrames(latest: WeatherMapTiles.estimatedLatestRadar(now: now)).last)
        XCTAssertEqual(viewModel.satelliteTime, WeatherMapTiles.estimatedLatestSatellite(now: now))
    }

    func testPlayStartsOverFromTheOldestImageWhenOnTheNewest() async {
        let viewModel = makeViewModel(radar: utc(2026, 10, 4, 18, 12), satellite: utc(2026, 10, 4, 18, 0), now: utc(2026, 10, 4, 18, 30))
        await viewModel.load()
        XCTAssertEqual(viewModel.frameIndex, 10)

        viewModel.togglePlay()
        XCTAssertTrue(viewModel.isPlaying)
        XCTAssertEqual(viewModel.frameIndex, 0)

        viewModel.togglePlay()
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testPlayAdvancesThroughTheFrames() async throws {
        let viewModel = makeViewModel(radar: utc(2026, 10, 4, 18, 12), satellite: utc(2026, 10, 4, 18, 0), now: utc(2026, 10, 4, 18, 30))
        await viewModel.load()

        viewModel.togglePlay()
        try await Task.sleep(nanoseconds: 1_300_000_000)
        viewModel.pause()

        XCTAssertGreaterThan(viewModel.frameIndex, 0)
    }

    func testLoadAgainSoonDoesNotAskTheServersAgain() async {
        var asked = 0
        let viewModel = WeatherMapViewModel(
            latestRadar: { asked += 1; return Date() },
            latestSatellite: { Date() },
            now: { Date() }
        )

        await viewModel.load()
        await viewModel.load()

        XCTAssertEqual(asked, 1)
    }
}
