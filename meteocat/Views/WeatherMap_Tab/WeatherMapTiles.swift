//
//  WeatherMapTiles.swift
//  meteocat
//
//  Where the map tiles come from, and the MapKit overlays that load them.
//  - Radar: Meteocat's own rain tiles (the ones meteo.cat/observacions/radar draws), one image every 6 minutes.
//  - Satellite: Meteosat Third Generation through EUMETSAT's open WMS (EUMETView), no key.
//

import MapKit

enum WeatherMapTiles {

    // MARK: Radar

    /// A new radar image every 6 minutes. The newest one is about 15-20 minutes old when it appears.
    static let radarStep: TimeInterval = 6 * 60
    /// The last hour, both ends included.
    static let radarFrameCount = 11
    /// meteo.cat has no radar tiles beyond this zoom. MapKit stretches the last level.
    static let radarMaxZoom = 7

    /// The times of the frames to show, oldest first, ending at `latest` snapped down to a 6 minute step.
    static func radarFrames(latest: Date, count: Int = radarFrameCount) -> [Date] {
        let end = (latest.timeIntervalSince1970 / radarStep).rounded(.down) * radarStep
        return (0..<max(count, 1)).map { Date(timeIntervalSince1970: end - Double(count - 1 - $0) * radarStep) }
    }

    /// The newest frame meteo.cat may already have published when it can't be asked: a bit under 20 minutes ago.
    static func estimatedLatestRadar(now: Date = Date()) -> Date {
        now.addingTimeInterval(-18 * 60)
    }

    /// `static-m.meteo.cat/tiles/radar/<UTC yyyy/MM/dd/HH/mm>/<zz>/000/000/<xxx>/000/000/<yyy>.png`.
    /// The server counts rows from the bottom (TMS), MapKit from the top, so `y` is flipped.
    /// A tile without rain does not exist (404), which MapKit leaves transparent.
    static func radarURL(time: Date, z: Int, x: Int, y: Int) -> URL? {
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute], from: time)
        let flippedY = (1 << z) - 1 - y
        let path = String(
            format: "%04d/%02d/%02d/%02d/%02d/%02d/000/000/%03d/000/000/%03d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, z, x, flippedY
        )
        return URL(string: "https://static-m.meteo.cat/tiles/radar/\(path).png")
    }

    // MARK: Satellite

    enum Satellite: String, CaseIterable, Identifiable {
        /// True colour by day, infrared-based clouds at night.
        case colour
        case infrared

        var id: String { rawValue }

        var layer: String {
            switch self {
            case .colour: "mtg_fd:rgb_geocolour"
            case .infrared: "mtg_fd:ir105_hrfi"
            }
        }

        var style: String {
            switch self {
            case .colour: ""
            case .infrared: "mtg_fd_ir105_hrfi_grayscale"
            }
        }
    }

    static let satelliteMaxZoom = 9
    private static let webMercatorHalfWorld = 20_037_508.342789244

    /// The newest image EUMETView may already have, when it can't be asked: 10 minute steps, about 40 minutes ago.
    static func estimatedLatestSatellite(now: Date = Date()) -> Date {
        let step: TimeInterval = 10 * 60
        return Date(timeIntervalSince1970: ((now.timeIntervalSince1970 - 40 * 60) / step).rounded(.down) * step)
    }

    /// A WMS `GetMap` for one 256 px map tile, in web mercator, of the image taken at `time`.
    /// Without a `TIME` EUMETView fills part of the map from another image, leaving a visible seam.
    static func satelliteURL(_ satellite: Satellite, time: Date, z: Int, x: Int, y: Int) -> URL? {
        let size = 2 * webMercatorHalfWorld / Double(1 << z)
        let minX = -webMercatorHalfWorld + Double(x) * size
        let maxY = webMercatorHalfWorld - Double(y) * size
        var components = URLComponents(string: "https://view.eumetsat.int/geoserver/wms")
        components?.queryItems = [
            URLQueryItem(name: "service", value: "WMS"),
            URLQueryItem(name: "version", value: "1.3.0"),
            URLQueryItem(name: "request", value: "GetMap"),
            URLQueryItem(name: "layers", value: satellite.layer),
            URLQueryItem(name: "styles", value: satellite.style),
            URLQueryItem(name: "crs", value: "EPSG:3857"),
            URLQueryItem(name: "bbox", value: "\(minX),\(maxY - size),\(minX + size),\(maxY)"),
            URLQueryItem(name: "width", value: "256"),
            URLQueryItem(name: "height", value: "256"),
            URLQueryItem(name: "format", value: "image/png"),
            URLQueryItem(name: "transparent", value: "true"),
            URLQueryItem(name: "time", value: ISO8601DateFormatter().string(from: time)),
        ]
        return components?.url
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}

// MARK: - Loading -

/// Loads map tiles for the overlays. MapKit asks for dozens at once and EUMETView answers a burst slowly or not at all
/// (about 20 requests a second, 8 at a time), so this keeps few connections open, tries a failed tile again, and
/// remembers what it has loaded.
final class TileLoader {
    private let session: URLSession
    private let cache = NSCache<NSString, NSData>()
    private static let attempts = 3

    /// What MapKit draws where there is nothing to show (a radar tile without rain does not exist).
    private static let emptyTile: Data = {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).pngData { _ in }
    }()

    init(maxConnections: Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = maxConnections
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
        cache.totalCostLimit = 40 * 1024 * 1024
    }

    /// `priority` is 0...1: the tiles of the image on screen go before the ones loaded ahead.
    func load(_ url: URL, cacheKey: String, priority: Float, result: @escaping (Data?, Error?) -> Void) {
        fetch(url, key: cacheKey as NSString, priority: priority, attempt: 1, result: result)
    }

    private func fetch(_ url: URL, key: NSString, priority: Float, attempt: Int, result: @escaping (Data?, Error?) -> Void) {
        if let cached = cache.object(forKey: key) {
            return result(cached as Data, nil)
        }
        let task = session.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { return result(nil, error) }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200, let data {
                cache.setObject(data as NSData, forKey: key, cost: data.count)
                return result(data, nil)
            }
            if status == 404 {
                return result(Self.emptyTile, nil)
            }
            guard attempt < Self.attempts else {
                return result(nil, error ?? URLError(.badServerResponse))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.6 * Double(attempt)) {
                self.fetch(url, key: key, priority: priority, attempt: attempt + 1, result: result)
            }
        }
        task.priority = priority
        task.resume()
    }
}

// MARK: - Overlays -

/// The URL MapKit asks for when a tile cannot be built: a request that fails, which leaves the tile empty.
private let missingTileURL = URL(string: "about:blank") ?? URL(fileURLWithPath: "/")

/// A tile overlay whose server stops at `nativeMaxZoom`. MapKit does not stretch tiles by itself: asked for a closer
/// zoom it simply loads nothing. So the overlay accepts up to `extraZoom` more levels and cuts the part it needs out
/// of the last tile the server has.
class RemoteTileOverlay: MKTileOverlay {
    let nativeMaxZoom: Int
    /// 0...1: the image on screen loads before the ones loaded ahead.
    var priority: Float { 1 }
    var loader: TileLoader { fatalError("override") }

    private static let extraZoom = 4

    init(nativeMaxZoom: Int) {
        self.nativeMaxZoom = nativeMaxZoom
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: 256, height: 256)
        canReplaceMapContent = false
        maximumZ = nativeMaxZoom + Self.extraZoom
    }

    /// The server's own tile at `z`, `x`, `y` (never beyond `nativeMaxZoom`).
    func nativeURL(z: Int, x: Int, y: Int) -> URL? { nil }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let overzoom = max(path.z - nativeMaxZoom, 0)
        return nativeURL(z: path.z - overzoom, x: path.x >> overzoom, y: path.y >> overzoom) ?? missingTileURL
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let overzoom = max(path.z - nativeMaxZoom, 0)
        let url = url(forTilePath: path)
        guard overzoom > 0 else {
            return loader.load(url, cacheKey: url.absoluteString, priority: priority, result: result)
        }
        let part = (x: path.x & ((1 << overzoom) - 1), y: path.y & ((1 << overzoom) - 1))
        loader.load(url, cacheKey: url.absoluteString, priority: priority) { data, error in
            guard let data else { return result(nil, error) }
            result(Self.crop(data, overzoom: overzoom, part: part) ?? data, nil)
        }
    }

    /// The `1/2^overzoom` square of `data` at `part`, scaled up to a whole tile.
    private static func crop(_ data: Data, overzoom: Int, part: (x: Int, y: Int)) -> Data? {
        let divisions = 1 << overzoom
        guard let image = UIImage(data: data)?.cgImage, image.width >= divisions, image.height >= divisions else { return nil }
        let width = image.width / divisions
        let height = image.height / divisions
        guard let piece = image.cropping(to: CGRect(x: part.x * width, y: part.y * height, width: width, height: height)) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).pngData { context in
            context.cgContext.interpolationQuality = .medium
            UIImage(cgImage: piece).draw(in: CGRect(x: 0, y: 0, width: 256, height: 256))
        }
    }
}

/// One radar image.
final class RadarTileOverlay: RemoteTileOverlay {
    let time: Date
    /// The image on screen. Its tiles load before those of the other images.
    var isCurrent = false

    private static let radarLoader = TileLoader(maxConnections: 6)

    init(time: Date) {
        self.time = time
        super.init(nativeMaxZoom: WeatherMapTiles.radarMaxZoom)
    }

    override var priority: Float { isCurrent ? 1 : 0.1 }
    override var loader: TileLoader { Self.radarLoader }

    // MapKit compares overlays, and these differ only by time
    override var hash: Int { time.hashValue }

    override func isEqual(_ object: Any?) -> Bool {
        (object as? RadarTileOverlay)?.time == time
    }

    override func nativeURL(z: Int, x: Int, y: Int) -> URL? {
        WeatherMapTiles.radarURL(time: time, z: z, x: x, y: y)
    }
}

/// The satellite image under the radar.
final class SatelliteTileOverlay: RemoteTileOverlay {
    let satellite: WeatherMapTiles.Satellite
    let time: Date

    private static let satelliteLoader = TileLoader(maxConnections: 6)

    init(_ satellite: WeatherMapTiles.Satellite, time: Date) {
        self.satellite = satellite
        self.time = time
        super.init(nativeMaxZoom: WeatherMapTiles.satelliteMaxZoom)
    }

    override var loader: TileLoader { Self.satelliteLoader }

    override func nativeURL(z: Int, x: Int, y: Int) -> URL? {
        WeatherMapTiles.satelliteURL(satellite, time: time, z: z, x: x, y: y)
    }
}
