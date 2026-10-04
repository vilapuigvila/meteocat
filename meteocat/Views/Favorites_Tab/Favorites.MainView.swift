//
//  Favorites.MainView.swift
//  meteocat
//
//  Created by albert vila on 27/2/25.
//

import Foundation
import SwiftUI
import Alfy

struct FavoritesView: View {

    @ObservedObject var viewModel: FavoritesViewModel

    var body: some View {
        Favorites.MainView(state: viewModel.stateView) {
            viewModel.action($0)
        }
    }
}

extension Favorites {

    struct MainView: View {

        let state: Favorites.ViewState
        let action: (Favorites.Action) -> Void

        @State private var selectedItem: Favorites.Representable?
        @State private var isPresentedSheet = false
        @State private var currentDetent = PresentationDetent.large

        var body: some View {
            ZStack {
                if case .idle = state {
                    EmptyView()
                      .transition(.opacity)
                }
                if case .error(let error) = state {
                    switch error {
                    case .networkFailure:
                        NetworkFailureErrorView()
                            .transition(.opacity)
                    case .empty:
                        MissingStationErrorView()
                            .transition(.opacity)
                    }
                }
                if case .loading = state {
                    SignalLoader("Loading favorites")
                }
                if case .loaded(let representable) = state {
                    NavigationStack {
                        ScrollView {
                            VStack(spacing: 0) {
                                buildHeader()

                                VStack(spacing: 0) {
                                    buildColumnTitles()
                                    SignalRule(color: Signal.ink)
                                    ForEach(representable) { item in
                                        buildRowView(item)
                                            .transition( .opacity)
                                            .animation(.easeOut(duration: 0.5), value: state.result)
                                    }
                                    Text("Bar: day range between -10 and 40 °C. Rain in mm.")
                                        .font(Signal.caption)
                                        .foregroundStyle(Signal.muted)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 12)
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                            }
                        }
                        .signalTopFill()
                        .background(Signal.paper.ignoresSafeArea())
                        .navigationTitle("Favorites")
                        .toolbar(.hidden, for: .navigationBar)
                        .onChange(of: selectedItem) { _, newValue in
                            guard newValue != nil else {
                                return
                            }
                            isPresentedSheet = true
                        }
                        .sheet(isPresented: $isPresentedSheet, onDismiss: {
                            selectedItem = nil
                            action(.onAppear)
                        }) {
                            if let selectedItem {
                                let viewModel = HomeStationViewModel(
                                    stationName: selectedItem.name,
                                    interactor: HomeStationInteractorImpl(
                                        source: .detailStation(code: selectedItem.stationCode, cityCode: ""),
                                        databaseManager: DatabaseManager.shared
                                    )
                                )
                                FavoriteDetailView(viewModel: viewModel)
 //                            .presentationDetents([.medium, .fraction(0.8), .height(200)], selection: $currentDetent)
                                    .presentationDetents([.medium, .large])
                                    .interactiveDismissDisabled(false)
                            }
                        }
                    }

                }
            }
            .animation(.easeInOut(duration: 0.5), value: state)
            .background(Signal.paper.ignoresSafeArea())
            .onAppear {
                action(.onAppear)
            }
        }

        private func buildHeader() -> some View {
            SignalHeader {
                SignalKicker("Today · \(Date().formatted(.dateTime.day().month(.abbreviated)))")
                    .frame(minHeight: 44, alignment: .leading)
                Text("Favorites")
                    .font(.system(size: 48, weight: .light))
                    .tracking(-1.4)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.top, 4)
            }
        }

        private func buildColumnTitles() -> some View {
            HStack(spacing: 0) {
                Text("STATION")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("MAX").frame(width: Favorites.RowView.columnWidth, alignment: .trailing)
                Text("MIN").frame(width: Favorites.RowView.columnWidth, alignment: .trailing)
                Text("RAIN").frame(width: Favorites.RowView.columnWidth, alignment: .trailing)
            }
            .font(Signal.caption)
            .tracking(1)
            .foregroundStyle(Signal.muted)
            .padding(.top, 20)
            .padding(.bottom, 8)
            .accessibilityHidden(true)
        }

        private func buildRowView(_ item: Favorites.Representable) -> some View {
            Button {
                selectedItem = item
            } label: {
                Favorites.RowView(item: item)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("favorites.card.\(item.stationCode)")
        }
    }
}

#Preview {
     var mockviewModel: Favorites.ViewState {
        .loaded([
            Favorites.Representable(name: "Castellar de N'Hug", maxTemp: "19.1 C", minTemp: "10.12121321 C", rainAcc: "12 mm", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "St. Llorenç de Morunys", maxTemp: "19.1 C", minTemp: "10.1 C", rainAcc: "", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Vallter 2000", maxTemp: "23.1324353453435454 C", minTemp: "21.1123454545 C", rainAcc: "12 mm", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Vic", maxTemp: "19.1 C", minTemp: "10.1 C", rainAcc: "12 mm", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Barcelona", maxTemp: "19.1 C", minTemp: "10.1 C", rainAcc: "12 mm", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Banyoles", maxTemp: "19.1 C", minTemp: "10.1 C", rainAcc: "12 mm", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Cadaqués", maxTemp: "19.1 C", minTemp: "10.1 C", rainAcc: "12 mm", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Olot", maxTemp: "19.145644564446 C", minTemp: "10.1 C", rainAcc: "--", stationCode: "", isFAvorite: false),
        ])
    }
    return Favorites.MainView(state: mockviewModel) { _ in

    }
}

extension Favorites {

    /// One favourite station: name with its day range, then max, min and rain.
    struct RowView: View {
        static let columnWidth: CGFloat = 66

        let item: Favorites.Representable

        /// The scale of the range bar, in °C. Catalonia's stations run from deep winter to heat waves.
        private static let scale: ClosedRange<Double> = -10...40

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.name)
                            .font(.system(.body).weight(.semibold))
                            .lineLimit(1)
                        buildRangeBar()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 8)

                    buildFigure(Self.figure(item.maxTemp), suffix: "°", color: Signal.ink)
                    buildFigure(Self.figure(item.minTemp), suffix: "°", color: Signal.muted)
                    buildFigure(Self.figure(item.rainAcc), suffix: "", color: Signal.ink, small: true)
                }
                .frame(minHeight: 72)
                .contentShape(Rectangle())
                SignalRule()
            }
        }

        private func buildFigure(_ text: String, suffix: String, color: Color, small: Bool = false) -> some View {
            Text(text == "--" || text.isEmpty ? "--" : text + suffix)
                .font(small ? Signal.caption : Signal.figureSmall)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(color)
                .frame(width: Self.columnWidth, alignment: .trailing)
        }

        /// Nothing is drawn when a value is missing.
        @ViewBuilder
        private func buildRangeBar() -> some View {
            if let low = StationValue.number(from: item.minTemp), let high = StationValue.number(from: item.maxTemp) {
                let span = Self.scale.upperBound - Self.scale.lowerBound
                let start = (min(max(low, Self.scale.lowerBound), Self.scale.upperBound) - Self.scale.lowerBound) / span
                let end = (min(max(high, Self.scale.lowerBound), Self.scale.upperBound) - Self.scale.lowerBound) / span
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Signal.track)
                        Rectangle()
                            .fill(Signal.orange)
                            .frame(width: max(2, geo.size.width * CGFloat(end - start)))
                            .offset(x: geo.size.width * CGFloat(start))
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            } else {
                Color.clear.frame(height: 4)
            }
        }

        /// `"19.1 °C"` → `"19.1"`.
        private static func figure(_ text: String) -> String {
            text.split(separator: " ").first.map(String.init) ?? text
        }
    }
}
