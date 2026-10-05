//
//  Signal.swift
//  meteocatalf
//
//  The "Field Notes · Signal" look: ink on paper, one orange signal colour, monospaced figures.
//

import SwiftUI
import UIKit

enum Signal {

    // MARK: Colours

    /// #FF5A1F. The same in light and dark; text on top of it is always `onSignal`.
    static let orange = Color(red: 1.0, green: 90.0 / 255, blue: 31.0 / 255)
    /// Text and icons on `orange`: #111418.
    static let onSignal = Color(red: 17.0 / 255, green: 20.0 / 255, blue: 24.0 / 255)

    static let paper = Color(light: 0xF6F7F8, dark: 0x111418)
    static let ink = Color(light: 0x111418, dark: 0xF6F7F8)
    static let muted = Color(light: 0x5B6470, dark: 0xA0A9B4)
    static let rule = Color(light: 0xD9DDE2, dark: 0x2A3037)
    /// Light range bars and pale fills.
    static let track = Color(light: 0xE6E9ED, dark: 0x2A3037)

    // MARK: Fonts

    static let kicker = Font.system(.caption, design: .monospaced).weight(.medium)
    static let caption = Font.system(.caption, design: .monospaced)
    static let figure = Font.system(.title3, design: .monospaced).weight(.medium)
    static let figureSmall = Font.system(.callout, design: .monospaced).weight(.medium)
    static let title = Font.system(.title, design: .default).weight(.semibold)
    static let rowTitle = Font.system(.subheadline, design: .default)
    static func hero(_ size: CGFloat = 96) -> Font { .system(size: size, weight: .light) }

    // MARK: Tab bar

    /// Dark bar, light labels, and an orange line over the selected item (before iOS 26, whose glass bar keeps the system look).
    @MainActor
    static func configureTabBar() {
        let bar = UIColor(red: 17.0 / 255, green: 20.0 / 255, blue: 24.0 / 255, alpha: 1)
        let idle = UIColor(red: 180.0 / 255, green: 188.0 / 255, blue: 198.0 / 255, alpha: 1)
        // Back chevrons sit on the orange header: dark in light mode.
        UINavigationBar.appearance().tintColor = UIColor { $0.userInterfaceStyle == .dark ? .white : bar }

        if #unavailable(iOS 26) {
            configureClassicTabBar(bar: bar, idle: idle)
        }
    }

    @MainActor
    private static func configureClassicTabBar(bar: UIColor, idle: UIColor) {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = bar
        appearance.shadowColor = .clear
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = idle
            item.normal.titleTextAttributes = [.foregroundColor: idle]
            item.selected.iconColor = .white
            item.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        }
        appearance.selectionIndicatorImage = selectionLine()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    /// A 4 pt orange line along the top edge, stretched to the width of the item.
    private static func selectionLine() -> UIImage {
        let size = CGSize(width: 3, height: 49)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(Signal.orange).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: size.width, height: 4))
        }
        return image.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 1), resizingMode: .stretch)
    }
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

// MARK: - Pieces -

/// The orange block at the top of a screen. It paints behind the status bar.
struct SignalHeader<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .foregroundStyle(Signal.onSignal)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Signal.orange.ignoresSafeArea(edges: .top))
    }
}

/// Small spaced capitals, like `STATIONS · 7 OF 183`.
struct SignalKicker: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Signal.kicker)
            .tracking(1.4)
            .textCase(.uppercase)
    }
}

/// A month figure: outlined, or filled with ink when `filled`.
struct SignalTile: View {
    let title: String
    let value: String
    var filled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Signal.caption)
                .foregroundStyle(filled ? Signal.paper.opacity(0.8) : Signal.muted)
            Text(value)
                .font(Signal.figure)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(filled ? Signal.paper : Signal.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(filled ? Signal.ink : Color.clear)
        .overlay(Rectangle().stroke(Signal.ink, lineWidth: filled ? 0 : 1))
    }
}

/// A one-pixel line.
struct SignalRule: View {
    var color: Color = Signal.rule

    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

/// Square-cornered icon button used in the header (heart, home).
struct SignalIconButtonStyle: ButtonStyle {
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 44, height: 44)
            .foregroundStyle(filled ? Color.white : Signal.onSignal)
            .background(filled ? Signal.onSignal : Color.clear)
            .overlay(Rectangle().stroke(Signal.onSignal, lineWidth: filled ? 0 : 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    /// Paints the area above a scrolling screen (status bar, and the navigation bar when there is one) orange,
    /// so the header seems to start at the top of the display. Apply before the screen's own background.
    func signalTopFill() -> some View {
        background(alignment: .top) {
            GeometryReader { geo in
                Signal.orange
                    .frame(height: geo.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }
}
