//
//  SignalLoader.swift
//  meteocat
//
//  The one loading indicator of the app: square orange drops falling onto an ink line.
//

import SwiftUI

struct SignalLoader: View {

    enum Size {
        /// Centred on an empty screen, caption underneath.
        case regular
        /// Small, caption beside it: over a map or a list that is refreshing.
        case compact
    }

    let caption: String?
    let size: Size

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ caption: String? = nil, size: Size = .regular) {
        self.caption = caption
        self.size = size
    }

    init(_ size: Size, caption: String? = nil) {
        self.init(caption, size: size)
    }

    var body: some View {
        Group {
            switch size {
            case .regular:
                VStack(spacing: 16) { rain; captionView }
            case .compact:
                HStack(spacing: 12) { rain; captionView }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption ?? "Loading")
        .accessibilityIdentifier("signal.loader")
    }

    @ViewBuilder
    private var captionView: some View {
        if let caption {
            Text(caption)
                .font(Signal.kicker)
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Signal.muted)
        }
    }

    private var rain: some View {
        let layout = Rain.Layout(size)
        return TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, _ in
                // with Reduce Motion on, one still frame with the drops half way down
                let time = reduceMotion ? Rain.stillTime : timeline.date.timeIntervalSinceReferenceDate
                Rain.draw(in: &context, layout: layout, time: time)
            }
        }
        .frame(width: layout.width, height: layout.height)
    }
}

// MARK: - Rain -

/// The drops: pure maths for where each one is at a time, so the picture is the same on every frame and testable.
enum Rain {

    /// Seconds a drop takes to fall, and then wait for its next turn.
    static let period: TimeInterval = 1.5
    /// A time at which every column has a drop in the air.
    static let stillTime: TimeInterval = 1.15
    /// Each column's start, in seconds. The lighter drop behind follows `trailDelay` later.
    static let delays: [TimeInterval] = [0, 0.5, 0.22, 0.9, 0.65]
    static let trailDelay: TimeInterval = 0.1

    struct Layout {
        let columns: Int
        /// One unit is the side of a drop (0.7 em in the design).
        let unit: CGFloat
        let width: CGFloat
        let height: CGFloat
        let line: CGFloat

        init(_ size: SignalLoader.Size) {
            switch size {
            case .regular:
                columns = 5; unit = 16; line = 1.25
            case .compact:
                columns = 3; unit = 7; line = 1
            }
            width = columns == 5 ? 7 * unit : 5 * unit
            height = columns == 5 ? 6 * unit : 4 * unit
        }

        var drop: CGFloat { unit * 0.7 }
    }

    /// How far down a drop is, 0...1, and how visible: it fades in at the top and out at the line.
    static func state(at time: TimeInterval, delay: TimeInterval) -> (progress: Double, opacity: Double) {
        let local = (time - delay).truncatingRemainder(dividingBy: period)
        let progress = (local < 0 ? local + period : local) / period
        let opacity: Double
        switch progress {
        case ..<0.12: opacity = progress / 0.12
        case ..<0.8: opacity = 1
        default: opacity = (1 - progress) / 0.2
        }
        return (progress, opacity)
    }

    static func draw(in context: inout GraphicsContext, layout: Layout, time: TimeInterval) {
        let drop = layout.drop
        let travel = layout.height - layout.line
        let inset = layout.unit * 0.3
        let gap = layout.columns > 1
            ? (layout.width - 2 * inset - drop) / CGFloat(layout.columns - 1)
            : 0

        for column in 0..<layout.columns {
            let x = inset + gap * CGFloat(column)
            let delay = delays[column % delays.count]
            // the lighter drop first, so the leading one is drawn over it
            for (offset, strength) in [(trailDelay, 0.55), (0, 1.0)] {
                let step = state(at: time, delay: delay + offset)
                // falls faster as it goes, like a drop
                let y = -drop + travel * CGFloat(step.progress * step.progress)
                let rect = CGRect(x: x, y: y, width: drop, height: drop)
                context.fill(Path(rect), with: .color(Signal.orange.opacity(step.opacity * strength)))
            }
        }

        let ground = CGRect(x: 0, y: layout.height - layout.line, width: layout.width, height: layout.line)
        context.fill(Path(ground), with: .color(Signal.ink))
    }
}

#Preview("Regular") {
    SignalLoader("Loading stations")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Signal.paper)
}

#Preview("Compact") {
    SignalLoader(.compact, caption: "Updating stations")
        .padding()
        .background(Signal.paper)
}
