//
//  WeatherMapViewModel.swift
//  meteocatalf
//

import Foundation

@MainActor
final class WeatherMapViewModel: ObservableObject {

    @Published var showsRadar = true
    /// The host of the radar tiles.
    @Published private(set) var host = ""
    /// The last two hours of radar images, oldest first.
    @Published private(set) var frames: [RadarFrame] = []
    @Published var frameIndex = 0
    @Published private(set) var isPlaying = false
    /// RainViewer could not be asked and there is nothing to show yet.
    @Published private(set) var failed = false

    private let loadMaps: () async throws -> RadarMaps
    private let now: () -> Date
    private var playTask: Task<Void, Never>?
    private var loadedAt: Date?

    /// A reload sooner than this brings nothing new: RainViewer adds an image every 10 minutes.
    private static let reloadInterval: TimeInterval = 3 * 60

    init(
        loadMaps: @escaping () async throws -> RadarMaps = {
            let maps: DTO.RainViewerMaps = try await ServerData.request(.radarMaps)
            return RadarMaps(maps)
        },
        now: @escaping () -> Date = { Date() }
    ) {
        self.loadMaps = loadMaps
        self.now = now
    }

    var currentFrame: RadarFrame? {
        frames.indices.contains(frameIndex) ? frames[frameIndex] : nil
    }

    /// Asks RainViewer for its images. If that fails the images already shown stay; with none, `failed` is set.
    func load() async {
        if let loadedAt, now().timeIntervalSince(loadedAt) < Self.reloadInterval, !frames.isEmpty { return }
        guard let maps = try? await loadMaps(), !maps.frames.isEmpty else {
            failed = frames.isEmpty
            return
        }
        failed = false
        loadedAt = now()
        if maps.host != host {
            host = maps.host
        }
        guard maps.frames != frames else { return }
        let wasOnNewest = frameIndex >= frames.count - 1
        frames = maps.frames
        if wasOnNewest || !frames.indices.contains(frameIndex) {
            frameIndex = maps.frames.count - 1
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
