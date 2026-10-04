//
//  HomeStationView.swift
//  meteocat
//
//  Created by albert vila on 4/2/25.
//

import SwiftUI
import Combine
import Alfy

struct HomeStationView: View {

    @ObservedObject var viewModel: HomeStationViewModel

    var body: some View {
        HomeStation.MainView(source: .home, state: viewModel.stateView) {
            viewModel.action($0)
        }
    }
}

fileprivate enum MonthMetric: String, Identifiable {
    case averageTemp
    case accumulatedRain

    var id: String { rawValue }
}

extension HomeStation {

    struct MainView: View /*, DecoupledView*/ {
        enum Source {
            case home, detail, modal
        }

        @Environment(\.scenePhase) private var scenePhase

        @State private var showCurrentWeather = false {
            willSet { precondition(source == .home, "Only the ☢️ -> `.home` source supports showing the current weather") }
        }

        @State private var monthMetricSheet: MonthMetric?

        @State private var selectedDate = Date()
        @State private var isDatePickerVisible = true
        @State private var isLoading = false
        @State private var hasAppeared = false
        @State private var _stateView: HomeStation.ViewState = .idle

        let source: Source
        let state: HomeStation.ViewState
        let action: (HomeStation.Action) -> Void

	        var body: some View {
            ZStack {
                if case .error(let kind) = state {
                    switch kind {
                    case .missingStationCode:
                        MissingStationErrorView()
                            .transition(.opacity)
                    case .networkFailure:
                        NetworkFailureErrorView()
                            .transition(.opacity)
                    case .noData:
                        NoDataErrorView()
                            .transition(.opacity)
                    }
                }
                if case .suggestion(let suggestion) = state {
                    NearestStationSuggestionView(suggestion: suggestion) {
                        action(.addAsHome(
                            stationName: suggestion.name,
                            code: suggestion.code,
                            codeCity: suggestion.codeCity
                        ))
                    }
                    .transition(.opacity)
                }
                if case .idle = state {
                  EmptyView()
                    .transition(.opacity)
                }
                if case .loading = state {
                    WeatherLoader()
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                if case .loaded(let representable) = state {
                    buildListView(representable)
                        .blur(radius: showCurrentWeather ? 0.999 : 0.0)
                        .animation(.easeInOut(duration: 0.3), value: showCurrentWeather)
                        .sheet(item: $monthMetricSheet) { metric in
                            MonthSummarySheet(
                                metric: metric,
                                stationName: representable.name,
                                monthValues: representable.monthValues,
                                missingDays: representable.missingDays
                            )
                        }

                    if source == .home {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button {
                                    //                                action(.presentCurrentWeather(stationCode: ""))
                                    showCurrentWeather = true
                                } label: {
                                    Image(systemName: "cloud.sun.fill")
                                        .font(.title2)
                                        .foregroundColor(Signal.onSignal)
                                        .padding(20)
                                }
                                .background(Color.accentColor)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                .padding()
                                .accessibilityLabel("Current weather")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showCurrentWeather) {
                ForecastView(
                    viewModel: Forecast.ViewModel(
                        interactor: Forecast.InteractorImpl(databaseManager: DatabaseManager.shared)
                    )
                )
                .presentationDetents([.fraction(0.3)])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(false)
                .ignoresSafeArea(edges: .bottom)
            }
            .animation(.easeInOut(duration: 0.5), value: state)
            .onAppear {
                action(.onAppear)
            }
            .onDisappear {
                action(.onDisappear)
            }
            .onChange(of: selectedDate) { oldValue, newValue in
                guard oldValue != newValue else { return nonFatalCrashlytics(false, "dataCorrupted") }
                action(.request(date: newValue))
            }
            .onAppLifecycleEvent { lifeCycle in
                switch lifeCycle {
                case .didEnterBackground:
                    action(.onDisappear)
                case .willEnterForeground(let date):
                    selectedDate = date
                    action(.request(date: selectedDate))
                }
            }
        }
        var isRedacted: Bool {
            guard let name = state.representable?.name else { return true }
            return name.isEmpty
        }

        private func buildListView(_ representable: HomeStation.Representable) -> some View {
            ScrollView {
                VStack(spacing: 0) {
                    buildHeaderView(representable)

                    VStack(spacing: 0) {
                        buildDatePicker()
                        buildMonthSummaryView(representable)
                        ForEach(Array(rows(of: representable).enumerated()), id: \.offset) { _, item in
                            buildRow(key: item.key, value: item.value, time: item.time)
                        }
                    }
                    .padding(.horizontal, Sizes.contentMargin + 4)
                    // keeps the last row clear of the floating weather button
                    .padding(.bottom, source == .home ? 88 : 24)
                }
            }
            .signalTopFill()
            .background(Signal.paper.ignoresSafeArea())
        }

        /// The average temperature is the big figure in the header, so it isn't repeated in the rows.
        private func rows(of representable: HomeStation.Representable) -> [HomeStation.Representable.Values] {
            representable.values.filter { !isAverageTemp($0) }
        }

        private func isAverageTemp(_ value: HomeStation.Representable.Values) -> Bool {
            StationValue.normalize(value.key).contains(StationValue.averageTempKey)
        }

        // MARK: Header

        private var headerKicker: String {
            switch source {
            case .home: return "My station"
            case .detail: return "Station"
            case .modal: return "Favorite"
            }
        }

        private func buildHeaderView(_ representable: HomeStation.Representable) -> some View {
            SignalHeader {
                HStack(spacing: 4) {
                    SignalKicker(headerKicker)
                    Spacer(minLength: 8)
                    buildHeaderButtons(representable)
                }
                .frame(minHeight: Sizes.touchSize)

                Text(representable.name)
                    .font(Signal.title)
                    .lineLimit(2)
                    .padding(.top, 10)
                    .accessibilityIdentifier("station.title")

                Text(selectedDate.formatted(date: .abbreviated, time: .standard))
                    .font(Signal.caption)
                    .padding(.top, 6)

                buildHero(representable)
            }
            // The sheet has no navigation bar: without this the title sits on the grabber and the heart in the corner.
            .padding(.top, source == .modal ? Sizes.contentMargin : 0)
        }

        @ViewBuilder
        private func buildHeaderButtons(_ representable: HomeStation.Representable) -> some View {
            switch source {
            case .home:
                EmptyView()
            case .modal:
                buildFavoriteButton(representable)
            case .detail:
                buildFavoriteButton(representable)
                buildHomeButton(representable)
            }
        }

        @ViewBuilder
        private func buildHero(_ representable: HomeStation.Representable) -> some View {
            if let mean = representable.values.first(where: isAverageTemp) {
                // "17.0 °C" → "17.0" large, "°C" small
                let parts = mean.value.split(separator: " ", maxSplits: 1).map(String.init)
                VStack(alignment: .leading, spacing: 0) {
                    Text(mean.key)
                        .font(Signal.caption)
                        .padding(.top, 14)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(parts.first ?? mean.value)
                            .font(Signal.hero())
                            .tracking(-3)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        if parts.count > 1 {
                            Text(parts[1])
                                .font(.system(size: 32, weight: .light))
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("station.hero")
                }
            }
        }

        // MARK: Content

        private func buildDatePicker() -> some View {
            VStack(spacing: 0) {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate, in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(CompactDatePickerStyle())
                .padding(.vertical, 12)
                .id(selectedDate.timeIntervalSince1970)
                .accessibilityIdentifier("station.datePicker")
                SignalRule()
            }
        }

        @ViewBuilder
        private func buildMonthSummaryView(_ representable: HomeStation.Representable) -> some View {
            let hasAverageTemp = !representable.averageTemp.isEmpty
            let hasAccumulatedRain = !representable.accumulatedRain.isEmpty
            if hasAverageTemp || hasAccumulatedRain {
                HStack(spacing: 12) {
                    if hasAverageTemp {
                        Button {
                            monthMetricSheet = .averageTemp
                        } label: {
                            SignalTile(title: "Mitjana (mes)", value: representable.averageTemp)
                        }
                        .buttonStyle(.plain)
                    }
                    if hasAccumulatedRain {
                        Button {
                            monthMetricSheet = .accumulatedRain
                        } label: {
                            SignalTile(title: "Acumulada (mes)", value: representable.accumulatedRain, filled: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 16)
            }
        }

        private func buildRow(key: String, value: String, time: String?) -> some View {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(key)
                        .font(Signal.rowTitle)
                    Spacer(minLength: 8)
                    Text(value)
                        .font(Signal.figure)
                    if let time {
                        Text(time)
                            .font(Signal.caption)
                            .foregroundStyle(Signal.muted)
                    }
                }
                .padding(.vertical, 14)
                SignalRule()
            }
        }

        // MARK: Buttons

        @State private var showSparks = false
        private func buildFavoriteButton(_ representable: HomeStation.Representable) -> some View {
            Button {
                feedbackGenerator(success: !representable.isFavorite)

                showSparks = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showSparks = false
                }
                withAnimation {
                    action(.addToFavs(code: representable.code, isFavorite: !representable.isFavorite))
                }
            } label: {
                ZStack {
                    Image(systemName: !representable.isFavorite ? "heart" : "heart.fill")
                        .font(.system(size: Sizes.iconSize - 2, weight: .regular))
                        .animation(.spring(), value: representable.isFavorite)

                    if showSparks, source != .home {
                        SparkView(isAddinng: !representable.isFavorite)
                            .frame(width: 24, height: 24)
                            .allowsHitTesting(false)
                    }
                }
            }
            .buttonStyle(SignalIconButtonStyle(filled: representable.isFavorite))
            .accessibilityLabel(representable.isFavorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityIdentifier("station.favoriteButton")
        }

        private func buildHomeButton(_ representable: HomeStation.Representable) -> some View {
            Button {
                feedbackGenerator(success: !representable.isHome)
                withAnimation {
                    action(.addAsHome(
                        stationName: representable.isHome ? nil : representable.name,
                        code: representable.isHome ? nil : representable.code,
                        codeCity: representable.isHome ? nil : representable.cityCode
                    ))
                }
            } label: {
                Image(systemName: representable.isHome ? "house.fill" : "house")
                    .font(.system(size: Sizes.iconSize - 2, weight: .regular))
                    .animation(.spring(), value: representable.isHome)
            }
            .buttonStyle(SignalIconButtonStyle(filled: representable.isHome))
            .accessibilityLabel(representable.isHome ? "Remove as my station" : "Set as my station")
            .accessibilityIdentifier("station.homeButton")
        }
        private func feedbackGenerator(success: Bool) {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(success ? .success : .error)
        }

        private enum Sizes {
            static let iconSize: CGFloat = 24
            static let touchSize: CGFloat = 44
            static let contentMargin: CGFloat = 16
        }
    }
}

// MARK: - MonthSummarySheet -

private struct MonthSummarySheet: View {
    let metric: MonthMetric
    let stationName: String
    let monthValues: [HomeStation.Representable.MonthDayValue]
    let missingDays: Int

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(monthValues, id: \.date) { day in
                        HStack(spacing: 12) {
                            Image(systemName: iconName)
                                .foregroundStyle(Signal.orange)

                            Text(day.date.formatted(date: .abbreviated, time: .omitted))
                                .font(Signal.rowTitle)

                            Spacer()

                            if day.isPartial {
                                Text("parcial")
                                    .font(Signal.caption)
                                    .foregroundStyle(Signal.muted)
                            }
                            Text(value(for: day))
                                .font(Signal.figure)
                        }
                        .padding(.vertical, 6)
                    }
                } footer: {
                    Text(footerText)
                        .font(Signal.caption)
                }
            }
            .listStyle(.plain)
            .navigationTitle("\(stationName) · \(title)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var title: String {
        switch metric {
        case .averageTemp:
            return "Mitjana (mes)"
        case .accumulatedRain:
            return "Acumulada (mes)"
        }
    }

    private var footerText: String {
        var lines: [String] = []
        if metric == .averageTemp, monthValues.contains(where: \.isPartial) {
            lines.append("La mitjana no inclou el dia en curs (dades parcials).")
        }
        if missingDays > 0 {
            lines.append("\(missingDays) dies sense dades.")
        }
        return lines.joined(separator: "\n")
    }

    private var iconName: String {
        switch metric {
        case .averageTemp:
            return "thermometer.medium"
        case .accumulatedRain:
            return "cloud.rain"
        }
    }

    private func value(for day: HomeStation.Representable.MonthDayValue) -> String {
        switch metric {
        case .averageTemp:
            return day.averageTemp
        case .accumulatedRain:
            return day.accumulatedRain
        }
    }
}

#Preview {
    VStack {
        HomeStation.MainView(source: .home, state: .loaded(HomeStation.Representable(
            values: [
                HomeStation.Representable.Values(key: "Temperatura mitjana", value: "10.5", time: nil),
                HomeStation.Representable.Values(key: "Temperatura maxima", value: "11.5", time: nil),
                HomeStation.Representable.Values(key: "Temperatura minima", value: "1.5", time: "4:52TU"),
                HomeStation.Representable.Values(key: "Humitat relativa", value: "50%", time: nil),
                HomeStation.Representable.Values(key: "Humitat relativa", value: "50%", time: nil),
                HomeStation.Representable.Values(key: "Precipitacio acumulada", value: "12.2 mm", time: nil)
            ],
            name: "Orís",
            code: "CC",
            cityCode: "085121",
            isFavorite: false,
            isHome: false,
            averageTemp: "14,4°C",
            accumulatedRain: "123,4 mm",
            monthValues: (1...19).map { day in
                .init(
                    date: Calendar.current.date(from: .init(year: 2026, month: 1, day: day)) ?? Date(),
                    averageTemp: "\(Double.random(in: 8...16).rounded()) °C",
                    accumulatedRain: "\(Double.random(in: 0...6).rounded()) mm",
                    isPartial: day == 19
                )
            },
            missingDays: 0
        ))) { _ in

            }
        Spacer()
    }
}
