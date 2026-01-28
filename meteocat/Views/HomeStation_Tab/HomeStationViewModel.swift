//
//  HomeStationViewModel.swift
//  meteocat
//
//  Created by albert vila on 5/2/25.
//

import Foundation
import Combine

/*
enum StateDomain<T: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded([T])
    case error(String)
}
*/

enum HomeStationStateDomain: Equatable, Sendable {
    struct Domain: Equatable, Sendable {
        let dto: [DTO.HomeStation]
        let summary: StationDayInfoSummary
    }
    
    case idle
    case loading
    case loaded(dto: [DTO.HomeStation], stationCode: String, cityCode: String, isHome: Bool, monthInfo: [StationDayInfo], summary: StationDayInfoSummary)
    case error(HomeStationInteractorImpl.ErrorReason)
    
    var result: [DTO.HomeStation] {
        guard case .loaded(let dto, _, _, _, _, _) = self else {
            return []
        }
        return dto
    }
    var stationCode: String {
        if case .loaded(_, let code, _, _, _, _) = self {
            return code
        } else {
            nonFatalCrashlytics(false, "dataCorrupted")
            return ""
        }
    }
    var cityCode: String {
        if case .loaded(_, _, let cityCode, _, _, _) = self {
            return cityCode
        } else {
            nonFatalCrashlytics(false, "dataCorrupted")
            return ""
        }
    }
    var summuary: StationDayInfoSummary {
        if case .loaded(_, _, _, _, _, let summary) = self {
            return summary
        } else {
            nonFatalCrashlytics(false, "dataCorrupted")
            return .init(averageTemp: nil, accumulatedRain: nil, firstDate: 0, lastDate: 0)
        }
    }
    var isHome: Bool {
        if case .loaded(_, _, _, let isHome, _, _) = self {
            return isHome
        } else {
            nonFatalCrashlytics(false, "dataCorrupted")
            return false
        }
    }
    var isFavorite: Bool {
        if case .loaded(let dto, _, _, _, _, _) = self {
            return dto.first?.isFavorite ?? false
        } else {
            nonFatalCrashlytics(false, "dataCorrupted")
            return false
        }
    }
    func copy(isHome: Bool? = nil, isFavorite: Bool? = nil) -> Self {
        .loaded(
            dto: result.map {
                DTO.HomeStation(
                    name: $0.name,
                    key: $0.key,
                    value: $0.value, time: $0.time, isFavorite: isFavorite ?? self.isFavorite)
            },
            stationCode: stationCode,
            cityCode: cityCode,
            isHome: isHome ?? self.isHome,
            monthInfo: monthInfo,
            summary: summuary
        )
    }

    var monthInfo: [StationDayInfo] {
        if case .loaded(_, _, _, _, let monthInfo, _) = self {
            return monthInfo
        } else {
            return []
        }
    }
}

final class HomeStationViewModel: ObservableObject {
    @Published private(set) var stateView: HomeStation.ViewState = .idle
    
    var stationName: String?
    let interactor: HomeStationInteractorProtocol
    
    init(stationName: String?, interactor: HomeStationInteractorProtocol) {
        self.stationName = stationName
        self.interactor = interactor
        registerPublisher()
    }
    
    func action(_ action: HomeStation.Action) {
        switch action {
        case .onAppear:
            interactor.useCase(.requestStation(date: Date()))
        case .onDisappear:
            interactor.useCase(.cancelRequestStation)
        case .request(let date):
            interactor.useCase(.requestStation(date: date))
        case .addToFavs(let stationCode, let isFav):
            interactor.useCase(.addToFavs(code: stationCode, isFavorite: isFav))
        case .addAsHome(let stationName, let code, let codeCity):
            interactor.useCase(.addAsHome(stationName: stationName, stationCode: code, codeCity: codeCity))
        case .presentCurrentWeather(let stationCode):
            break
        }
    }
    private var cancellables: Set<AnyCancellable> = []

    private func registerPublisher() {
        interactor
            .publisher
            .receive(on: DispatchQueue.main)
            .map(mapToHomeStationState)
            .weakAssign(to: \.stateView, on: self)
            .store(in: &cancellables)
    }
    
    private func mapToHomeStationState(_ value: HomeStationStateDomain) -> HomeStation.ViewState {
        switch value {
        case .idle:
            return .idle
        case .loading:
            return .loading
        case .loaded(let representable, let stationCode, let cityCode, let isHome, let monthInfo, let summary):
            print("avvp [HOME STATION VM] - \(dump(representable))")
            let values = representable.map {
                HomeStation.Representable.Values(key: $0.key, value: $0.value, time: $0.time)
            }
            return .loaded(
                HomeStation.Representable(
                    values: values,
                    name: representable.first?.name ?? "",
                    code: stationCode,
                    cityCode: cityCode,
                    isFavorite: representable.first?.isFavorite ?? false,
                    isHome: isHome,
                    averageTemp: summary.averageTemp == nil ? "--" : "\(summary.averageTemp!)",
                    accumulatedRain: summary.accumulatedRain == nil ? "--" : "\(summary.accumulatedRain!)",
                    monthValues: monthInfo.monthDayValues()
                )
            )
        case .error(let error):
            return .error(error.asHomeStationErrorView())
        }
    }
}

// MARK: - helper  -

struct StationDayInfoSummary: Equatable, Sendable {
    let averageTemp: Double?
    let accumulatedRain: Double?
    let firstDate: Double
    let lastDate: Double
}

extension Array where Element == StationDayInfo {

    func stationDayInfoSummary() -> StationDayInfoSummary {
        guard let first = self.min(by: { $0.date < $1.date }),
              let last = self.max(by: { $0.date < $1.date })
        else {
            return .init(averageTemp: nil, accumulatedRain: nil, firstDate: 0, lastDate: 0)
        }

        return .init(
            averageTemp: averageValue(forKey: "temperatura mitjana", isRain: false),
            accumulatedRain: averageValue(forKey: "precipitació acumulada", isRain: true),
            firstDate: Date(timeIntervalSince1970: first.date).timeIntervalSince1970,
            lastDate: Date(timeIntervalSince1970: last.date).timeIntervalSince1970
        )
    }

    private func averageValue(forKey key: String, isRain: Bool) -> Double? {
        let normalizedKey = normalize(key)
        let values: [Double] = compactMap { dayInfo in
            guard let entry = dayInfo.info.first(where: { normalize($0.key) == normalizedKey }) else {
                return nil
            }
            return parseDouble(from: entry.value)
        }
        guard !values.isEmpty else { return nil }
        if isRain {
            return (values.reduce(0, +) * 10).rounded() / 10
        } else {
            let total = values.reduce(0, +) / Double(values.count)
            return (total * 10).rounded() / 10
        }
    }

    private func normalize(_ string: String) -> String {
        string.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }

    private func parseDouble(from string: String) -> Double? {
        let candidate = string.replacingOccurrences(of: ",", with: ".")
        let scanner = Scanner(string: candidate)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: "0123456789.-").inverted
        return scanner.scanDouble()
    }

    func monthDayValues(referenceDate: Date = Date()) -> [HomeStation.Representable.MonthDayValue] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else {
            return []
        }

        var byDay: [DateComponents: StationDayInfo] = [:]
        byDay.reserveCapacity(self.count)

        for dayInfo in self {
            let date = Date(timeIntervalSince1970: dayInfo.date)
            let key = calendar.dateComponents([.year, .month, .day], from: date)
            byDay[key] = dayInfo
        }

        return (1...day).compactMap { dayOfMonth in
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12)) else {
                return nil
            }
            let key = DateComponents(year: year, month: month, day: dayOfMonth)
            let info = byDay[key]?.info ?? []

            let avg = extractValue(forKeyContains: "temperatura mitjana", in: info) ?? "--"
            let rain = extractValue(forKeyContains: "precipitacio acumulada", in: info) ?? "--"
            return .init(date: date, averageTemp: avg, accumulatedRain: rain)
        }
    }

    private func extractValue(forKeyContains keyFragment: String, in items: [DTO.HomeStation]) -> String? {
        let fragment = normalize(keyFragment)
        return items.first { normalize($0.key).contains(fragment) }?.value
    }
}
