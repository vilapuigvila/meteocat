//
//  Forecast.ViewModel.swift
//  meteocat
//
//  Created by albert vila on 4/7/25.
//

import Foundation
import Combine
import Alfy

extension Forecast {
    
    final class ViewModel<I: InteractorProtocol>: ObservableObject where I._UseCase == Forecast.UseCase, I._Domain == Forecast.Domain {
        private static var readFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeZone = .current
            formatter.locale = .current
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            return formatter
        }
        private var cancellables: Set<AnyCancellable> = []
        
        @Published private(set) var stateView: Forecast.StateView = .idle
        
        let interactor: I
        
        init(interactor: I) {
            self.interactor = interactor
            registerPublisher()
        }
        
        func action(_ action: ActionView) {
            switch action {
            case .onAppear:
                interactor.useCase(.getCurrentWeather)
            case .onDisappear:
                interactor.useCase(.two)
            }
        }
        
        private func registerPublisher() {
            interactor
                .publisher
                .receive(on: DispatchQueue.main)
                .map { domain in
                    if let error = domain.error {
                        nonFatalCrashlytics(false, error.localizedDescription)
                        return .error(Forecast.ErrrorView.emptyData)
                    } else if domain.isLoading {
                        return .loading
                    } else {
                        return .loaded(
                            Forecast.Representable(
                                now: Forecast.Representable.Now(
                                    currentTemp: domain.dto.now.currentTemp ?? "--",
                                    maxTemp: domain.dto.now.maxTemp ?? "--",
                                    minTemp: domain.dto.now.minTemp ?? "--",
                                    weatherDescription: domain.dto.now.weatherDescription ?? "--",
                                    iconWeather: domain.dto.now.iconWeather
                                ),
                                source: Forecast.Representable.Source(
                                    station: domain.dto.source.station ?? "--",
                                    time: domain.dto.source.time ?? "--",
                                    datetime: self.formatted(domain.dto.source.datetime)
                                ),
                                rows: domain.dto.rows.map {
                                    Forecast.Representable.Row(
                                        title: $0.title,
                                        weatherValue: $0.content
                                    )
                                }
                            )
                        )
                    }
                }
                .weakAssign(to: \.stateView, on: self)
                .store(in: &cancellables)
        }
        
        private static func buildRowValue(_ key: String, value: String?) -> String {
            guard let value = value else {
                return "--"
            }
            return "\(key) - \(value)"
        }
        
        private func formatted(_ isoString: String?) -> String {
            guard let isoString = isoString else {
                return "--"
            }
            let formatter = DateFormatter()
            formatter.locale   = Locale.current
            formatter.timeZone = TimeZone.current
            
            // 1) If it ends in “Z”, treat Z as just a literal suffix,
            //    parse “yyyy-MM-dd'T'HH:mm” in local TZ:
            if isoString.hasSuffix("Z") {
                let trimmed = String(isoString.dropLast()) // removes the Z
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
                if let date = formatter.date(from: trimmed) {
                    return Self.readFormatter.string(from: date)
                }
            }
            
            // 2) Otherwise, try standard ISO8601 (UTC conversions apply):
            if let date = ISO8601DateFormatter().date(from: isoString) {
                return Self.readFormatter.string(from: date)
            }
            
            // 3) Finally, try offset-aware fallback (e.g. “…+0200”):
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mmX"
            if let date = formatter.date(from: isoString) {
                return Self.readFormatter.string(from: date)
            }
            
            // Couldn’t parse
            return "--"
        }
    }
    
}

