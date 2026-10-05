//
//  ErrorViews.swift
//  meteocatalf
//
//  Created by albert vila on 23/6/25.
//

import SwiftUI

/// The empty or failed state of a tab: a flat icon, a kicker, a title and one line, in an ink outline.
/// No animation and no shadow. `action` adds the button at the bottom.
struct SignalEmptyState: View {
    let systemImage: String
    let kicker: String
    let title: String
    var detail: String?
    var action: (title: String, identifier: String, run: () -> Void)?
    var identifier = "emptyState.card"
    var titleIdentifier = "emptyState.title"

    var body: some View {
        ZStack {
            Signal.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(Signal.orange)
                    .accessibilityHidden(true)
                SignalKicker(kicker)
                    .foregroundStyle(Signal.muted)
                Text(title)
                    .font(Signal.title)
                    .foregroundStyle(Signal.ink)
                    .accessibilityIdentifier(titleIdentifier)
                if let detail {
                    Text(detail)
                        .font(Signal.caption)
                        .foregroundStyle(Signal.muted)
                }
                if let action {
                    SignalRule()
                        .padding(.top, 4)
                    Button(action: action.run) {
                        SignalKicker(action.title)
                            .foregroundStyle(Signal.onSignal)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Signal.orange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(action.identifier)
                }
            }
            .padding(20)
            .frame(maxWidth: 340, alignment: .leading)
            .overlay(Rectangle().stroke(Signal.ink, lineWidth: 1))
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
        }
    }
}

struct MissingStationErrorView: View {
    var body: some View {
        SignalEmptyState(
            systemImage: "mappin.and.ellipse",
            kicker: "My station",
            title: "No station yet",
            detail: "Select a station from the list."
        )
    }
}

/// The empty My Station tab, with the closest station and a button to make it the user's station.
struct NearestStationSuggestionView: View {
    let suggestion: NearestStation.Suggestion
    let onAdd: () -> Void

    private var distanceText: String {
        "\(suggestion.distanceKm.formatted(.number.precision(.fractionLength(1)))) km"
    }

    var body: some View {
        SignalEmptyState(
            systemImage: "mappin.and.ellipse",
            kicker: "Closest station",
            title: suggestion.name,
            detail: distanceText,
            action: (title: "Add as My Station", identifier: "suggestion.addButton", run: onAdd),
            identifier: "suggestion.card",
            titleIdentifier: "suggestion.name"
        )
    }
}

/// Shown when a request fails because of the network.
struct NetworkFailureErrorView: View {
    var body: some View {
        SignalEmptyState(
            systemImage: "wifi.slash",
            kicker: "Network error",
            title: "No connection",
            detail: "Check your connection and try again."
        )
    }
}

/// The server has no values for the day: it hasn't started there yet, or the station sent nothing.
struct NoDataErrorView: View {
    var body: some View {
        SignalEmptyState(
            systemImage: "calendar.badge.clock",
            kicker: "No data",
            title: "Nothing for this day yet",
            detail: "Pick another date."
        )
    }
}

/// The Favs tab before any station is a favourite.
struct NoFavoritesView: View {
    var body: some View {
        SignalEmptyState(
            systemImage: "heart",
            kicker: "Favs",
            title: "No favourites yet",
            detail: "Tap the heart on a station.",
            identifier: "favorites.empty"
        )
    }
}

// MARK: - Preview
/*
struct ErrorViews_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MissingStationErrorView()
                .previewLayout(.sizeThatFits)
                .padding()

            NetworkFailureErrorView()
                .previewLayout(.sizeThatFits)
                .padding()
        }
    }
}*/
