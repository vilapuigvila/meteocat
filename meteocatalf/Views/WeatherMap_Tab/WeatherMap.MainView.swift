//
//  WeatherMap.MainView.swift
//  meteocatalf
//
//  Rain radar over a map of Catalonia (RainViewer), with the last two hours as an animation.
//

import SwiftUI
import MapKit

struct WeatherMapView: View {

    @ObservedObject var viewModel: WeatherMapViewModel

    /// Where the user is, and whether the map is on screen: the location is only read while it is.
    @State private var isVisible = false
    @State private var hasLocation = false
    @State private var recenterCount = 0

    var body: some View {
        VStack(spacing: 0) {
            buildHeader()
            ZStack(alignment: .bottom) {
                WeatherMapRepresentable(
                    host: viewModel.host,
                    frames: viewModel.frames,
                    selectedFrame: viewModel.currentFrame,
                    showsRadar: viewModel.showsRadar,
                    isActive: isVisible,
                    recenterCount: recenterCount,
                    hasLocation: $hasLocation
                )
                .ignoresSafeArea(edges: .bottom)
                if hasLocation {
                    buildLocateButton()
                }
                if viewModel.frames.isEmpty {
                    buildStatus()
                }
                buildControls()
            }
        }
        .background(Signal.paper.ignoresSafeArea())
        .task { await viewModel.load() }
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            viewModel.pause()
        }
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
        viewModel.currentFrame.map { $0.time.formatted(.dateTime.day().month(.abbreviated).hour().minute()) }
    }

    // MARK: Controls

    /// Over the map until the first images arrive: the loader, or why there are none.
    @ViewBuilder
    private func buildStatus() -> some View {
        Group {
            if viewModel.failed {
                HStack(spacing: 12) {
                    Text("Radar unavailable")
                        .font(Signal.kicker)
                        .tracking(1.4)
                        .textCase(.uppercase)
                    Button("Retry") {
                        Task { await viewModel.load() }
                    }
                    .font(Signal.kicker)
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Signal.orange)
                    .accessibilityIdentifier("map.retry")
                }
                .foregroundStyle(Signal.ink)
            } else {
                SignalLoader(.compact, caption: "Loading radar")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Signal.paper)
        .overlay(Rectangle().stroke(Signal.ink, lineWidth: 1))
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 16)
    }

    /// Brings the map back to the user after panning it.
    private func buildLocateButton() -> some View {
        Button {
            recenterCount += 1
        } label: {
            Image(systemName: "location.fill")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(Signal.ink)
                .background(Signal.paper)
                .overlay(Rectangle().stroke(Signal.ink, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Center on my location")
        .accessibilityIdentifier("map.locate")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(16)
    }

    private func buildControls() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WeatherMapChip(title: "Radar", isOn: viewModel.showsRadar, id: "map.radar") {
                viewModel.showsRadar.toggle()
            }

            if viewModel.showsRadar, viewModel.frames.count > 1 {
                buildTimeline()
            }

            // RainViewer's terms ask for a mention of the source with a link
            HStack(spacing: 6) {
                Text("Radar:")
                    .foregroundStyle(Signal.muted)
                if let url = URL(string: "https://www.rainviewer.com/api.html") {
                    Link("RainViewer", destination: url)
                        .underline()
                        .foregroundStyle(Signal.ink)
                        .accessibilityIdentifier("map.source")
                }
            }
            .font(Signal.caption)
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
            .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play last two hours")
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
            .accessibilityValue(viewModel.currentFrame.map { $0.time.formatted(.dateTime.hour().minute()) } ?? "")
            .accessibilityIdentifier("map.slider")

            Text(viewModel.currentFrame?.time.formatted(.dateTime.hour().minute()) ?? "--:--")
                .font(Signal.figureSmall)
                .foregroundStyle(Signal.ink)
                .frame(width: 58, alignment: .trailing)
        }
    }
}

/// A square toggle: filled with orange when on.
private struct WeatherMapChip: View {
    let title: String
    let isOn: Bool
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
                .foregroundStyle(isOn ? Signal.onSignal : Signal.ink)
                .background(isOn ? Signal.orange : Color.clear)
                .overlay(Rectangle().stroke(isOn ? Signal.orange : Signal.ink, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

// MARK: - MapKit -

private struct WeatherMapRepresentable: UIViewRepresentable {
    let host: String
    let frames: [RadarFrame]
    let selectedFrame: RadarFrame?
    let showsRadar: Bool
    /// The map is on screen: only then the user location and the compass are read.
    let isActive: Bool
    /// Each change brings the map back to the user.
    let recenterCount: Int
    @Binding var hasLocation: Bool

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

    final class Coordinator: NSObject, MKMapViewDelegate, CLLocationManagerDelegate {
        private var radarOverlays: [RadarTileOverlay] = []
        private var radarHost = ""
        private var renderers: [RadarFrame: MKTileOverlayRenderer] = [:]
        private var selectedFrame: RadarFrame?
        private var showsRadar = true

        // the user: where, which way the phone points
        private let compass = CLLocationManager()
        private var userView: HeadingLocationView?
        private var heading: Double?
        private var didCenter = false
        private var handledRecenter = 0
        private var hasLocation: Binding<Bool>?

        override init() {
            super.init()
            compass.delegate = self
            compass.headingFilter = 3
        }

        /// Every radar image stays on the map, only the chosen one is visible, so stepping through the hour doesn't reload tiles.
        func apply(_ parent: WeatherMapRepresentable, to map: MKMapView) {
            // before the overlays are added: MapKit asks for each renderer, and its alpha, at that moment
            selectedFrame = parent.selectedFrame
            showsRadar = parent.showsRadar

            if parent.frames != radarOverlays.map(\.frame) || parent.host != radarHost {
                map.removeOverlays(radarOverlays)
                renderers = [:]
                radarHost = parent.host
                radarOverlays = parent.frames.map { RadarTileOverlay(frame: $0, host: parent.host) }
                for overlay in radarOverlays {
                    map.addOverlay(overlay, level: .aboveRoads)
                }
            }

            hasLocation = parent.$hasLocation
            applyUser(parent, to: map)

            for overlay in radarOverlays {
                overlay.isCurrent = overlay.frame == selectedFrame
            }
            for (frame, renderer) in renderers {
                let alpha = self.alpha(for: frame)
                if renderer.alpha != alpha {
                    renderer.alpha = alpha
                    renderer.setNeedsDisplay()
                }
            }
        }

        /// The location dot and the compass run only while the tab is on screen.
        private func applyUser(_ parent: WeatherMapRepresentable, to map: MKMapView) {
            if map.showsUserLocation != parent.isActive {
                map.showsUserLocation = parent.isActive
                if parent.isActive {
                    if CLLocationManager.headingAvailable() { compass.startUpdatingHeading() }
                } else {
                    compass.stopUpdatingHeading()
                }
            }
            if parent.recenterCount != handledRecenter {
                handledRecenter = parent.recenterCount
                center(on: map, animated: true)
            }
        }

        /// Keeps the zoom the map has, moves it to the user.
        private func center(on map: MKMapView, animated: Bool) {
            guard let location = map.userLocation.location else { return }
            map.setRegion(MKCoordinateRegion(center: location.coordinate, span: map.region.span), animated: animated)
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard userLocation.location != nil else { return }
            if !didCenter {
                didCenter = true
                center(on: mapView, animated: false)
            }
            if let hasLocation, !hasLocation.wrappedValue {
                // not while SwiftUI is updating the view
                DispatchQueue.main.async { hasLocation.wrappedValue = true }
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKUserLocation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: HeadingLocationView.reuseIdentifier) as? HeadingLocationView
                ?? HeadingLocationView(annotation: annotation, reuseIdentifier: HeadingLocationView.reuseIdentifier)
            view.heading = heading
            userView = view
            return view
        }

        func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            // true north when the phone knows where it is, magnetic north otherwise; negative means no reading
            let degrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
            heading = degrees >= 0 ? degrees : nil
            userView?.heading = heading
        }

        func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { false }

        /// The images that are not on screen stay a hair above 0: MapKit loads no tiles for a renderer that is invisible.
        private func alpha(for frame: RadarFrame) -> CGFloat {
            showsRadar && frame == selectedFrame ? 0.85 : 0.004
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tiles = overlay as? MKTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKTileOverlayRenderer(tileOverlay: tiles)
            if let radar = tiles as? RadarTileOverlay {
                renderer.alpha = alpha(for: radar.frame)
                renderers[radar.frame] = renderer
            }
            return renderer
        }
    }
}
