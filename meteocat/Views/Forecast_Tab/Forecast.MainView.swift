//
//  Forecast.MainView.swift
//  meteocat
//
//  Created by albert vila on 6/7/25.
//

import SwiftUI
import Alfy
import SDWebImageSwiftUI

struct ForecastView: View {
    
    @ObservedObject var viewModel: Forecast.ViewModel<Forecast.InteractorImpl>
    
    var body: some View {
        Forecast.MainView(stateView: viewModel.stateView) {
            viewModel.action($0)
        }
    }
}

extension Forecast {
    
    struct MainView: View {
        private static var requestTimeThreshold: Int { 60*5 }
        
        @State private var onAppearDate: Date?
        
        let stateView: StateView
        let onAction: (ActionView) -> Void
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if case .loading = stateView {
                    WeatherLoader()
                }
                
                if case .loaded(let representable) = stateView {
                    VStack(spacing: 0) {
                        WeatherSummaryView(
                            temperature: representable.now.currentTemp,
                            high: representable.now.maxTemp,
                            low: representable.now.minTemp,
                            description: representable.now.weatherDescription,
                            iconUrl: representable.now.iconWeather
                        )
                        .padding()
                        .padding(.top, 64)
                        
                        buildList(representable)
                        
                    }
                }
            }
            .padding()
            .onAppear { prev in
#warning("avp check it out ⚠️ -> maybe improve that")
                print("avpv prev date - \(prev)")
            }
            .onAppear {
                requestOnAppearIfNeeded(threshold: Self.requestTimeThreshold, date: Date())
            }
            .onAppLifecycleEvent { lifeCycle in
                switch lifeCycle {
                case .didEnterBackground:
#warning("avp check it out ⚠️ -> cancel request")
                    break
                case .willEnterForeground(let date):
                    requestOnAppearIfNeeded(threshold: Self.requestTimeThreshold, date: date)
                }
            }
        }
        
        private func requestOnAppearIfNeeded(threshold: Int, date: Date) {
            if let last = onAppearDate {
                print("avpv diff seconds from now – \(last.differenceInSecondsFromNow)")
                guard last.differenceInSecondsFromNow > threshold else {
                    return
                }
            }
            onAppearDate = date
            onAction(.onAppear)
        }
        
        private func buildList(_ representable: Forecast.Representable) -> some View {
            VStack {
                List {
                    Section(header: buildHeaderView(representable.source.datetime)) {
                        ForEach(representable.rows, id: \.self) { item in
                            VStack(alignment: .trailing) {
                                HStack(spacing: 16) {
#warning("avpv check it out ⚠️ -> image")
                                    /*Image(systemName: values.imageName)
                                        .foregroundStyle(values.color)
                                        .offset(x: -8)*/
                                    
                                    Text(item.title)
//                                        .foregroundStyle(.white)
                                    Text(item.weatherValue)
                                }
                            }
                            .frame(height: 44)
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .listRowSeparator(.visible)
            }
            .preferredColorScheme(.dark)
        }
        
        private func buildHeaderView(_ dateTime: String?) -> some View {
            VStack {
                VStack {
                    buildHeaderTitle(dateTime)
                }
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
        }
        
        private func buildHeaderTitle(_ dateTime: String?) -> some View {
            HStack {
                Text("Last update: ")
                Text(dateTime ?? "--")
                Spacer()
                /*
                Text("Additional info..")
                    .font(.custom("san francisco display", size: 24))
                    .fontWeight(.bold)
//                    .lineLimit(2)
                    .frame(maxWidth: .infinity, maxHeight: 44)*/
            }
            .foregroundStyle(.teal.opacity(0.8))
            .font(.custom("san francisco display", size: 12))
            .fontWeight(.bold)
        }
        
        private func buildText(_ text: String) -> some View {
            Text("Current temperature: \(text)")
                .font(.custom("san francisco display", size: 24))
                .foregroundStyle(.white.opacity(0.9))
                .fontWeight(.bold)
        }
    }
    
}

// MARK: - WeatherSummaryView -

private struct WeatherSummaryView: View {
    
    let temperature: String
    let high: String
    let low: String
    let description: String
    let iconUrl: URL?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 24) {
                Text("\(temperature)°C")
                    .font(.custom("san francisco display", size: 54))
                    .foregroundColor(.white.opacity(0.95))
                
                // High / Low
                VStack(spacing: 8) {
                    Text("\(high)°C")
                        .font(.custom("san francisco display", size: 20))
                        .foregroundColor(.red)
                    Text("\(low)°C")
                        .font(.custom("san francisco display", size: 20))
                        .foregroundColor(.blue)
                }
                .padding(.top, 8)
                
                WebImage(url: iconUrl)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 74, height: 74)
                    .padding(.leading, -12)
//                    .padding(.top, -6)
                
                Spacer()
            }
            
            Text(description)
                .font(.custom("san francisco display", size: 20))
                .foregroundColor(.white.opacity(0.8))
        }
//        .padding()
        .background(.black.opacity(0.95))
    }
}

// MARK: - Preview -

#Preview {
    Forecast.MainView(
        stateView: .loaded(
            Forecast.Representable(
                now: Forecast.Representable.Now(
                    currentTemp: "30",
                    maxTemp: "36",
                    minTemp: "3",
                    weatherDescription: "Tempesta",
                    iconWeather: URL(string: "https://static-m.meteo.cat/assets/images/meteors/estatcel/8.svg")
                ),
                source: .empty,
                rows: [
                .init(title: "Humidity:", weatherValue: "65%"),
                .init(title: "Rain:", weatherValue: "12 mm"),
                .init(title: "Pressure:", weatherValue: "1024 hPa"),
                .init(title: "Wind:", weatherValue: "45 km/h")
            ])
        ), onAction: { _ in }
    )
}

struct WeatherSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        WeatherSummaryView(
            temperature: "18",
            high: "26",
            low: "15",
            description: "Entre mig i molt ennuvolat",
            iconUrl: URL(string: "https://static-m.meteo.cat/assets/images/meteors/estatcel/8.svg")
        )
        .previewLayout(.sizeThatFits)
    }
}
