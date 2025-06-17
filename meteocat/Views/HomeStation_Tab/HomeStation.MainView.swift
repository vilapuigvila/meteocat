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

extension HomeStation {
    
    struct MainView: View /*, DecoupledView*/ {
        enum Source {
            case home, detail, modal
        }
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.scenePhase) private var scenePhase
        
        @State private var selectedDate = Date()
        @State private var isDatePickerVisible = true
        @State private var isLoading = false
        @State private var hasAppeared = false
        
        let source: Source
        let state: HomeStation.ViewState
        let action: (HomeStation.Action) -> Void
        
        var body: some View {
            ZStack {
                switch state {
                case .error(let errorView):
                    switch errorView {
                    case .missingStationCode:
                        Text("Please select a station from the list.")
                    case .networkFailure:
                        Text("Network Error")
                    }
                case .idle:
                    EmptyView()
                case .loading:
                    Text("Loading...")
                case .loaded(let representable):
                    VStack {
                        List {
                            Section(header: buildHeaderView(representable)) {
                                ForEach(representable.values.indices, id: \.self) { idx in
                                    let item = representable.values[idx]
                                    buildRow(
                                        key: item.key,
                                        value: item.value,
                                        time: item.time,
                                        idx: idx
                                    )
                                    .padding([.top, .bottom], 12)
                                }
                            }
                        }
                        .listRowSeparator(.visible)
                    }
                }
            }
            .onAppear {
                action(.onAppear)
            }
            .onDisappear {
                action(.onDisappear)
            }
            .onChange(of: selectedDate) { oldValue, newValue in
                guard oldValue != newValue else { return assertionFailure() }
                action(.request(date: newValue))
            }
            .onReceive(
                Publishers.Merge(
                    NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification),
                    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            )) { notification in
                switch notification.name {
                case UIApplication.didEnterBackgroundNotification:
                    action(.onDisappear)
                case UIApplication.willEnterForegroundNotification:
                    selectedDate = Date()
                    action(.request(date: selectedDate))
                default:
                    assertionFailure("not implemented")
                    break
                }
            }
        }
        var isRedacted: Bool {
            guard let name = state.representable?.name else { return true }
            return name.isEmpty
        }
        
        private func buildHeaderTitle(_ representable: HomeStation.Representable) -> some View {
            HStack {
                switch source {
                case .home:
                    Text(representable.name)
                        .font(.custom("san francisco display", size: 28))
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, maxHeight: 44)
                case .modal:
                    buildModalCaseView(representable)
                case .detail:
                    buildDetailCaseView(representable)
                }
            }
        }
        
        private func buildDetailCaseView(_ representable: HomeStation.Representable) -> some View {
            Group {
                buildFavoriteButton(representable)
                Spacer()
                
                Text(representable.name)
                    .lineLimit(2)
                    .font(.custom("san francisco display", size: 28))
                    .fontWeight(.bold)
                
                Spacer()
                
                buildHomeButton(representable)
            }
        }

        private func buildModalCaseView(_ representable: HomeStation.Representable) -> some View {
            ZStack {
                // Center text with padding to avoid button
                HStack {
                    // Invisible spacer that matches button width
                    Spacer()
                        .frame(width: Sizes.iconSize*1.5)
                    
                    // Centered text
                    Text(representable.name)
                        .lineLimit(2)
                        .font(.custom("San Francisco Display", size: 28))
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    
                    // Invisible spacer for symmetry
                    Spacer()
                        .frame(width: Sizes.iconSize*1.5)
                }
                
                // Button layer at the leading edge
                HStack {
                    buildFavoriteButton(representable)
                    Spacer()
                }
            }
        }
        
        private func buildHeaderView(_ representable: HomeStation.Representable) -> some View {
            VStack {
                VStack {
                    buildHeaderTitle(representable)
                    
                    Text(selectedDate.formatted(date: .abbreviated, time: .standard))
                        .font(.custom("Poppins-Bold", size: 14))
                }
                .padding(.bottom, 16)
//                .redacted(reason: isRedacted ? .placeholder : [])

                DatePicker(
                    "Select Date",
                    selection: $selectedDate, in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(CompactDatePickerStyle())
                .padding(.bottom, 20)
                .id(selectedDate.timeIntervalSince1970)
                
                SafariProgressBar(isLoading: $isLoading)
                    .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
        }
        
        private func buildRow(key: String, value: String, time: String?, idx: Int) -> some View {
            Group {
                if let values = color(forKey: key) {
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: values.imageName)
                                .foregroundStyle(values.color)
                                .offset(x: -8)
                            
                            Text("\(key)")
                                .offset(x: -6)
                            Spacer()
                            
                            Text("\(value)")
                                .foregroundStyle(values.color)
                        }
                        if let date = time {
                            Text(date)
                                .font(.custom("Poppins-Bold", size: 12))
                                .foregroundStyle(.gray)
                        }
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(key)")
                            Spacer()
                            Text("\(value)")
                            
                            if let date = time {
                                Text(date)
                                    .font(.custom("Poppins-Bold", size: 12))
                                    .foregroundStyle(.gray)
                            }
                        }
                    }
                }
            }
        }
        
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
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .frame(width: Sizes.iconSize, height: Sizes.iconSize)
                        .padding(.horizontal, 4)
                        .animation(.spring(), value: representable.isFavorite)
                    
                    if showSparks, source != .home {
                        SparkView(isAddinng: !representable.isFavorite)
                            .frame(width: 24, height: 24)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .offset(x: -20)
        }

        private func buildHomeButton(_ representable: HomeStation.Representable) -> some View {
            Button {
                feedbackGenerator(success: !representable.isHome)
                withAnimation {
                    action(.addAsHome(
                        stationName: representable.isHome ? nil : representable.name,
                        code: representable.isHome ? nil : representable.code
                    ))
                }
            } label: {
                Image(systemName: representable.isHome ? "house.circle.fill" : "house.slash")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(representable.isHome ? Color.green.opacity(0.5) : Color.gray)
                    .frame(width: 24, height: 24)
                    .padding(.horizontal, 4)
                    .animation(.spring(), value: representable.isHome)
            }
            .frame(width: 44, height: 44)
            .offset(x: 20)
        }
        private func feedbackGenerator(success: Bool) {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(success ? .success : .error)
        }
        private func color(forKey key: String) -> (color: Color, imageName: String)? {
            func normalized(_ string: String) -> String {
                string.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            }
            let normalizedKey = normalized(key)
            switch true {
            case normalizedKey.contains("temperatura mitjana"):
                return (.green, "thermometer.medium")
            case normalizedKey.contains("temperatura maxima"):
                return (.red, "thermometer.sun")
            case normalizedKey.contains("temperatura minima"):
                return (.blue, "thermometer.snowflake")
            case normalizedKey.contains("humitat"):
                return (.cyan, "humidity.fill")
            case normalizedKey.contains("vent"):
                return (.gray, "wind")
            case normalizedKey.contains("pressio atmosferica"):
                return nil
            case normalizedKey.contains("precipitacio"):
                return (.cyan, "cloud.rain") // value.contains("0.") ? "cloud" :
            default:
                return nil
            }
        }
        
        private enum Sizes {
            static let iconSize: CGFloat = 24
        }
    }
}

#Preview {
    VStack {
        HomeStation.MainView(source: .modal, state: .loaded(HomeStation.Representable(
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
            isFavorite: false, isHome: false))) { _ in
                
            }
        Spacer()
    }
}
