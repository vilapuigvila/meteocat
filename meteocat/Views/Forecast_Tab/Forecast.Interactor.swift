//
//  Forecast.Interactor.swift
//  meteocat
//
//  Created by albert vila on 3/7/25.
//

import Foundation
import Combine
import Alfy

extension Forecast {
    
    protocol InteractorProtocol {
        associatedtype _Domain: Equatable
        associatedtype _UseCase: Equatable
        
        var domain: _Domain { get }
        var publisher: AnyPublisher<_Domain, Never> { get }
        func useCase(_ useCase: _UseCase)
    }
    
    final class InteractorImpl: InteractorProtocol {
        typealias _Domain = Domain
        typealias _UseCase = UseCase
        
        var domain: _Domain {
            subject.value
        }
        var publisher: AnyPublisher<_Domain, Never> {
            subject.eraseToAnyPublisher()
        }
        private let subject = CurrentValueSubject<_Domain, Never>(.empty)
        
        let databaseManager: DatabaseManagerProtocol
        
        init(databaseManager: DatabaseManagerProtocol) {
            self.databaseManager = databaseManager
        }
        
        func useCase(_ useCase: _UseCase) {
            switch useCase {
            case .getCurrentWeather:
                Task {
                    await getForecastInfo()
                }
            case .two:
                break
            }
        }
        
        private func getForecastInfo() async {
            guard let code = UserSettings.homeStation?.codeCity else {
                assertionFailure()
                subject.send(
                    domain.copy(
                        isLoading: false,
                        error: ErrorReason.missingCityCode.toEquatableError()
                    )
                )
                return
            }
            subject.send(domain.copy(isLoading: true))
            
            do {
                // 082858 good
                let dto: DTO.CurrentWeather = try await ServerData.request(.curentWeather(code: code)) // 081509
                let domain = domain.copy(
                    dto: dto,
                    isLoading: false,
                    error: nil
                )
                subject.send(domain)
            } catch {
                assertionFailure()
                subject.send(domain.copy(isLoading: false, error: error.toEquatableError()))
            }
        }
    }
}

// MARK: - Domain + UseCase -

extension Forecast {
    enum ErrorReason: Error {
        case missingCityCode
    }
    
    enum UseCase: Equatable {
        case getCurrentWeather
        case two
    }
    
    struct Domain: Equatable {
        let dto: DTO.CurrentWeather
        
        let isLoading: Bool
        let error: EquatableError?
        
        static let empty: Self = .init(
            dto: .init(
                now: .init(
                    currentTemp: nil, maxTemp: nil, minTemp: nil, weatherDescription: nil, iconWeather: nil
                ),
                source: .init(
                    station: nil, time: nil, datetime: nil
                ),
                humidity: nil,
                rain: nil,
                pressure: nil,
                wind: nil
            ),
            isLoading: false,
            error: nil
        )
        
        func copy(
            dto: DTO.CurrentWeather? = nil,
            isLoading: Bool? = nil,
            error: EquatableError? = nil
        ) -> Self {
            Domain(
                dto: dto ?? self.dto,
                isLoading: isLoading ?? self.isLoading,
                error: error ?? self.error
            )
        }
    }
}
