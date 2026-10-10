import SwiftUI
import WidgetKit

// MARK: - Entry

/// One widget state. `display` is nil when no home station is set.
struct HomeStationEntry: TimelineEntry {
    let date: Date
    let display: HomeStationWidgetDisplay?
}

// MARK: - Provider

/// Reads the snapshot the app writes to the App Group. No networking here.
struct HomeStationProvider: TimelineProvider {
    /// How often the widget re-reads the shared snapshot.
    private static let refreshInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> HomeStationEntry {
        HomeStationEntry(date: Date(), display: HomeStationWidgetDisplay.preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeStationEntry) -> Void) {
        if context.isPreview {
            completion(HomeStationEntry(date: Date(), display: HomeStationWidgetDisplay.preview))
        } else {
            completion(currentEntry(now: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeStationEntry>) -> Void) {
        let now = Date()
        let timeline = Timeline(
            entries: [currentEntry(now: now)],
            policy: .after(now.addingTimeInterval(Self.refreshInterval))
        )
        completion(timeline)
    }

    // MARK: - Helpers

    private func currentEntry(now: Date) -> HomeStationEntry {
        guard let snapshot = HomeStationWidgetStore().load() else {
            return HomeStationEntry(date: now, display: nil)
        }
        return HomeStationEntry(date: now, display: HomeStationWidgetDisplay(snapshot: snapshot, now: now))
    }
}

// MARK: - Widget

struct HomeStationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.homeStationKind, provider: HomeStationProvider()) { entry in
            HomeStationWidgetView(entry: entry)
        }
        .configurationDisplayName("My Station")
        .description("Current temperature and today's max and min of your station.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

// MARK: - Views

/// Picks the layout for the current family. Faded when the snapshot is stale.
struct HomeStationWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HomeStationEntry

    var body: some View {
        content
            .opacity(entry.display?.isStale == true ? 0.55 : 1)
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        if let display = entry.display {
            switch family {
            case .accessoryRectangular:
                AccessoryRectangularView(display: display)
            case .accessoryInline:
                AccessoryInlineView(display: display)
            case .accessoryCircular:
                AccessoryCircularView(display: display)
            case .systemMedium:
                MediumView(display: display)
            default:
                SmallView(display: display)
            }
        } else if family == .accessoryInline || family == .accessoryCircular {
            // No room for the sentence: a hint that the station is missing.
            Text(HomeStationWidgetDisplay.placeholderValue)
        } else {
            EmptyStationView()
        }
    }
}

/// Shared by the small and medium layouts.
private struct CurrentTempText: View {
    let display: HomeStationWidgetDisplay
    let size: CGFloat

    var body: some View {
        Text(display.currentTemp)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(.orange)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }
}

private struct SmallView: View {
    let display: HomeStationWidgetDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(display.stationName)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
            CurrentTempText(display: display, size: 40)
            HStack(spacing: 8) {
                Label(display.maxTemp, systemImage: "arrow.up")
                Label(display.minTemp, systemImage: "arrow.down")
            }
            .font(.footnote)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text("Updated \(display.updatedTime)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct MediumView: View {
    let display: HomeStationWidgetDisplay

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(display.stationName)
                    .font(.headline)
                    .lineLimit(2)
                CurrentTempText(display: display, size: 44)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                Label(display.maxTemp, systemImage: "arrow.up")
                Label(display.minTemp, systemImage: "arrow.down")
                Text("Updated \(display.updatedTime)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct AccessoryRectangularView: View {
    let display: HomeStationWidgetDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(display.stationName)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(display.currentTemp)
                Label(display.maxTemp, systemImage: "arrow.up")
                Label(display.minTemp, systemImage: "arrow.down")
            }
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// The line above the clock on the Lock Screen: "18° ↑21° ↓12°". One `Text`, the only thing iOS draws there.
private struct AccessoryInlineView: View {
    let display: HomeStationWidgetDisplay

    var body: some View {
        Text("\(ShortTemp.text(display.currentTemp)) ↑\(ShortTemp.text(display.maxTemp)) ↓\(ShortTemp.text(display.minTemp))")
    }
}

/// The round Lock Screen widget: current temperature large, max and min below it.
private struct AccessoryCircularView: View {
    let display: HomeStationWidgetDisplay

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(ShortTemp.text(display.currentTemp))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                Text("\(ShortTemp.text(display.maxTemp)) \(ShortTemp.text(display.minTemp))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .minimumScaleFactor(0.6)
            }
            .lineLimit(1)
            .padding(.horizontal, 4)
        }
    }
}

/// "21.3 °C" → "21°", for the Lock Screen sizes where "°C" and decimals don't fit. "--" stays as it is.
private enum ShortTemp {
    static func text(_ value: String) -> String {
        let number = value
            .replacingOccurrences(of: "°C", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let double = Double(number) else { return value }
        return "\(Int(double.rounded()))°"
    }
}

/// Shown when no home station has been chosen in the app.
private struct EmptyStationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("My Station")
                .font(.headline)
            Text("Choose your station in the app")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview(as: .accessoryCircular) {
    HomeStationWidget()
} timeline: {
    HomeStationEntry(date: Date(), display: HomeStationWidgetDisplay.preview)
}

#Preview(as: .accessoryInline) {
    HomeStationWidget()
} timeline: {
    HomeStationEntry(date: Date(), display: HomeStationWidgetDisplay.preview)
}

#Preview(as: .systemSmall) {
    HomeStationWidget()
} timeline: {
    HomeStationEntry(date: Date(), display: HomeStationWidgetDisplay.preview)
    HomeStationEntry(date: Date(), display: nil)
}
