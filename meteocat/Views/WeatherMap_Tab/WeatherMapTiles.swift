//
//  WeatherMapTiles.swift
//  meteocat
//
//  Where the radar tiles come from, and the MapKit overlays that load them: RainViewer's public weather maps API
//  (https://www.rainviewer.com/api.html), one image every 10 minutes for the last two hours.
//

import MapKit

/// One radar image: when it was taken and the path of its tiles.
struct RadarFrame: Hashable {
    let time: Date
    let path: String
}

/// What RainViewer has: the host of the tiles and the images, oldest first.
struct RadarMaps: Equatable {
    let host: String
    let frames: [RadarFrame]

    init(host: String, frames: [RadarFrame]) {
        self.host = host
        self.frames = frames
    }

    init(_ dto: DTO.RainViewerMaps) {
        host = dto.host
        frames = dto.radar.past
            .sorted { $0.time < $1.time }
            .map { RadarFrame(time: Date(timeIntervalSince1970: $0.time), path: $0.path) }
    }
}

enum WeatherMapTiles {

    /// RainViewer has no tiles beyond this zoom: it answers a "Zoom Level Not Supported" picture, with a success status.
    /// MapKit does not stretch tiles by itself, so `RemoteTileOverlay` cuts closer zooms out of the zoom 7 tile.
    static let radarMaxZoom = 7
    /// RainViewer's colour scheme ("Universal Blue"). The free tier answers the same colours for any scheme.
    static let radarColorScheme = 2

    /// `{host}{path}/256/{z}/{x}/{y}/{color}/{smooth}_{snow}.png`: smoothed, without snow.
    /// A tile without rain is a transparent picture. Rows count from the top, as in MapKit.
    static func radarURL(host: String, frame: RadarFrame, z: Int, x: Int, y: Int) -> URL? {
        URL(string: "\(host)\(frame.path)/256/\(z)/\(x)/\(y)/\(radarColorScheme)/1_0.png")
    }
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
    let frame: RadarFrame
    let host: String
    /// The image on screen. Its tiles load before those of the other images.
    var isCurrent = false

    private static let radarLoader = TileLoader(maxConnections: 6)

    init(frame: RadarFrame, host: String) {
        self.frame = frame
        self.host = host
        super.init(nativeMaxZoom: WeatherMapTiles.radarMaxZoom)
    }

    override var priority: Float { isCurrent ? 1 : 0.1 }
    override var loader: TileLoader { Self.radarLoader }

    // MapKit compares overlays, and these differ only by frame
    override var hash: Int { frame.path.hashValue }

    override func isEqual(_ object: Any?) -> Bool {
        (object as? RadarTileOverlay)?.frame.path == frame.path
    }

    override func nativeURL(z: Int, x: Int, y: Int) -> URL? {
        WeatherMapTiles.radarURL(host: host, frame: frame, z: z, x: x, y: y)
    }
}
