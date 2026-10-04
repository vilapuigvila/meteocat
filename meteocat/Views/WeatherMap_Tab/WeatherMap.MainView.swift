//
//  WeatherMap.MainView.swift
//  meteocat
//
//  Rain radar over a satellite image of Catalonia, with the last hour of radar as an animation.
//

import SwiftUI
import MapKit

struct WeatherMapView: View {

    @ObservedObject var viewModel: WeatherMapViewModel

    var body: some View {
        VStack(spacing: 0) {
            buildHeader()
            ZStack(alignment: .bottom) {
                WeatherMapRepresentable(
                    satellite: viewModel.satellite,
                    satelliteTime: viewModel.satelliteTime,
                    frames: viewModel.frames,
                    selectedFrame: viewModel.currentFrame,
                    showsRadar: viewModel.showsRadar
                )
                .ignoresSafeArea(edges: .bottom)
                buildControls()
            }
        }
        .background(Signal.paper.ignoresSafeArea())
        .task { await viewModel.load() }
        .onDisappear { viewModel.pause() }
    }

    // MARK: Header

    private func buildHeader() -> some View {
        SignalHeader {
            SignalKicker(timeText.map { "Radar · \($0)" } ?? "Radar")
                .frame(minHeight: 44, alignment: .leading)
            Text("Radar")
                .font(.system(size: 48, weight: .light))
                .tracking(-1.4)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.top, 4)
        }
    }

    /// The time of the image on screen, local.
    private var timeText: String? {
        viewModel.currentFrame.map { $0.formatted(.dateTime.day().month(.abbreviated).hour().minute()) }
    }

    /// The source of each image on the map, with the time of the satellite one.
    private var attribution: String {
        guard viewModel.satellite != nil, let time = viewModel.satelliteTime else { return "Radar: Meteocat" }
        return "Satellite \(time.formatted(.dateTime.hour().minute())): EUMETSAT · Radar: Meteocat"
    }

    // MARK: Controls

    private func buildControls() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                WeatherMapChip(title: "Satellite", isOn: viewModel.satellite == .colour, id: "map.satellite") {
                    viewModel.satellite = .colour
                }
                WeatherMapChip(title: "Infrared", isOn: viewModel.satellite == .infrared, id: "map.infrared") {
                    viewModel.satellite = .infrared
                }
                WeatherMapChip(title: "Map", isOn: viewModel.satellite == nil, id: "map.plain") {
                    viewModel.satellite = nil
                }
                Spacer(minLength: 0)
                WeatherMapChip(title: "Radar", isOn: viewModel.showsRadar, signal: true, id: "map.radar") {
                    viewModel.showsRadar.toggle()
                }
            }

            if viewModel.showsRadar, viewModel.frames.count > 1 {
                buildTimeline()
            }

            Text(attribution)
                .font(Signal.caption)
                .foregroundStyle(Signal.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Signal.paper)
        .overlay(alignment: .top) { SignalRule(color: Signal.ink) }
    }

    private func buildTimeline() -> some View {
        HStack(spacing: 12) {
            Button {
                viewModel.togglePlay()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Signal.onSignal)
                    .background(Signal.orange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play last hour")
            .accessibilityIdentifier("map.play")

            Slider(
                value: Binding(
                    get: { Double(viewModel.frameIndex) },
                    set: {
                        viewModel.pause()
                        viewModel.frameIndex = Int($0.rounded())
                    }
                ),
                in: 0...Double(viewModel.frames.count - 1),
                step: 1
            )
            .tint(Signal.orange)
            .accessibilityLabel("Radar time")
            .accessibilityValue(viewModel.currentFrame.map { $0.formatted(.dateTime.hour().minute()) } ?? "")
            .accessibilityIdentifier("map.slider")

            Text(viewModel.currentFrame?.formatted(.dateTime.hour().minute()) ?? "--:--")
                .font(Signal.figureSmall)
                .foregroundStyle(Signal.ink)
                .frame(width: 58, alignment: .trailing)
        }
    }
}

/// A square toggle: filled with ink when on, or with orange for the radar.
private struct WeatherMapChip: View {
    let title: String
    let isOn: Bool
    var signal = false
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Signal.kicker)
                .tracking(1)
                .textCase(.uppercase)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .foregroundStyle(isOn ? (signal ? Signal.onSignal : Signal.paper) : Signal.ink)
                .background(isOn ? (signal ? Signal.orange : Signal.ink) : Color.clear)
                .overlay(Rectangle().stroke(isOn && signal ? Signal.orange : Signal.ink, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

// MARK: - MapKit -

private struct WeatherMapRepresentable: UIViewRepresentable {
    let satellite: WeatherMapTiles.Satellite?
    let satelliteTime: Date?
    let frames: [Date]
    let selectedFrame: Date?
    let showsRadar: Bool

    /// Catalonia, with room around it.
    private static let start = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.7, longitude: 1.75),
        span: MKCoordinateSpan(latitudeDelta: 3.2, longitudeDelta: 4.2)
    )
    private static let limits = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.7, longitude: 1.75),
        span: MKCoordinateSpan(latitudeDelta: 9, longitudeDelta: 12)
    )

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        map.pointOfInterestFilter = .excludingAll
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.setRegion(Self.start, animated: false)
        map.cameraBoundary = MKMapView.CameraBoundary(coordinateRegion: Self.limits)
        map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 8_000, maxCenterCoordinateDistance: 1_600_000)
        map.accessibilityIdentifier = "map.view"
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.apply(self, to: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var satelliteOverlay: SatelliteTileOverlay?
        private var radarOverlays: [RadarTileOverlay] = []
        private var renderers: [Date: MKTileOverlayRenderer] = [:]
        private var selectedFrame: Date?
        private var showsRadar = true

        /// Every radar image stays on the map, only the chosen one is visible, so stepping through the hour doesn't reload tiles.
        func apply(_ parent: WeatherMapRepresentable, to map: MKMapView) {
            let wanted = parent.satelliteTime.flatMap { time in parent.satellite.map { ($0, time) } }
            if wanted?.0 != satelliteOverlay?.satellite || wanted?.1 != satelliteOverlay?.time {
                if let old = satelliteOverlay {
                    map.removeOverlay(old)
                    satelliteOverlay = nil
                }
                if let (satellite, time) = wanted {
                    let overlay = SatelliteTileOverlay(satellite, time: time)
                    // below the radar, and below the place names
                    map.insertOverlay(overlay, at: 0, level: .aboveRoads)
                    satelliteOverlay = overlay
                }
            }

            // before the overlays are added: MapKit asks for each renderer, and its alpha, at that moment
            selectedFrame = parent.selectedFrame
            showsRadar = parent.showsRadar

            if parent.frames != radarOverlays.map(\.time) {
                map.removeOverlays(radarOverlays)
                renderers = [:]
                radarOverlays = parent.frames.map(RadarTileOverlay.init(time:))
                for overlay in radarOverlays {
                    map.addOverlay(overlay, level: .aboveRoads)
                }
            }

            for overlay in radarOverlays {
                overlay.isCurrent = overlay.time == selectedFrame
            }
            for (time, renderer) in renderers {
                let alpha = self.alpha(for: time)
                if renderer.alpha != alpha {
                    renderer.alpha = alpha
                    renderer.setNeedsDisplay()
                }
            }
        }

        /// The images that are not on screen stay a hair above 0: MapKit loads no tiles for a renderer that is invisible.
        private func alpha(for time: Date) -> CGFloat {
            showsRadar && time == selectedFrame ? 0.85 : 0.004
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tiles = overlay as? MKTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKTileOverlayRenderer(tileOverlay: tiles)
            if let radar = tiles as? RadarTileOverlay {
                renderer.alpha = alpha(for: radar.time)
                renderers[radar.time] = renderer
            }
            return renderer
        }
    }
}
