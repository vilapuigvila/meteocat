//
//  WeatherMapViewModel.swift
//  meteocat
//

import Foundation

@MainActor
final class WeatherMapViewModel: ObservableObject {

    /// The image under the radar, or `nil` for the plain map.
    @Published var satellite: WeatherMapTiles.Satellite? = .colour
    @Published var showsRadar = true
    /// The last hour of radar images, oldest first.
    @Published private(set) var frames: [Date] = []
    @Published var frameIndex = 0
    @Published private(set) var isPlaying = false
    /// When the satellite image was taken. `nil` until known, and then the satellite is not drawn.
    @Published private(set) var satelliteTime: Date?

    private let latestRadar: () async throws -> Date
    private let latestSatellite: () async throws -> Date
    private let now: () -> Date
    private var playTask: Task<Void, Never>?
    private var loadedAt: Date?

    /// A reload sooner than this brings nothing new: the radar updates every 6 minutes.
    private static let reloadInterval: TimeInterval = 3 * 60

    init(
        latestRadar: @escaping () async throws -> Date = { try await ServerData.request(.radarLatest) },
        latestSatellite: @escaping () async throws -> Date = { try await ServerData.request(.satelliteLatest) },
        now: @escaping () -> Date = { Date() }
    ) {
        self.latestRadar = latestRadar
        self.latestSatellite = latestSatellite
        self.now = now
    }

    var currentFrame: Date? {
        frames.indices.contains(frameIndex) ? frames[frameIndex] : nil
    }

    /// Asks when the newest radar image was taken. If that fails the time is estimated; a missing tile is only transparent.
    func load() async {
        if let loadedAt, now().timeIntervalSince(loadedAt) < Self.reloadInterval, !frames.isEmpty { return }
        async let radar = try? await latestRadar()
        async let satellite = try? await latestSatellite()
        let latest = await radar ?? WeatherMapTiles.estimatedLatestRadar(now: now())
        let newSatelliteTime = await satellite ?? WeatherMapTiles.estimatedLatestSatellite(now: now())
        loadedAt = now()
        if newSatelliteTime != satelliteTime {
            satelliteTime = newSatelliteTime
        }
        let newFrames = WeatherMapTiles.radarFrames(latest: latest)
        guard newFrames != frames else { return }
        let wasOnNewest = frameIndex >= frames.count - 1
        frames = newFrames
        if wasOnNewest || !frames.indices.contains(frameIndex) {
            frameIndex = newFrames.count - 1
        }
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func pause() {
        playTask?.cancel()
        playTask = nil
        isPlaying = false
    }

    private func play() {
        guard frames.count > 1 else { return }
        isPlaying = true
        if frameIndex >= frames.count - 1 {
            frameIndex = 0
        }
        playTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // rests a little longer on the newest image before starting over
                let last = frameIndex >= frames.count - 1
                try? await Task.sleep(for: .milliseconds(last ? 1400 : 550))
                guard !Task.isCancelled else { return }
                frameIndex = last ? 0 : frameIndex + 1
            }
        }
    }
}
