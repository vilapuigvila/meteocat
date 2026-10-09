//
//  HomeStationWidgetValues.swift
//  meteocatalf
//

import Foundation

/// Turns the values the app already shows into what the snapshot stores. Pure, so it is unit tested.
enum HomeStationWidgetValues {

    /// Today's max and min from the daily table rows, matched after diacritic folding and lowercasing
    /// ("Temperatura màxima" → "temperatura maxima"). Nil for a row that isn't there or has an empty value.
    static func extremes(in rows: [(key: String, value: String)]) -> (max: String?, min: String?) {
        let maxRow = rows.first(where: { fold($0.key).contains("temperatura maxima") })
        let minRow = rows.first(where: { fold($0.key).contains("temperatura minima") })
        return (
            max: maxRow.flatMap { nonBlank($0.value) },
            min: minRow.flatMap { nonBlank($0.value) }
        )
    }

    /// "18" → "18 °C"; kept as is when it already has "°"; nil for nil/blank. Same rule as HomeStationViewModel.currentTemp.
    static func temperature(_ raw: String?) -> String? {
        guard let text = raw.flatMap({ nonBlank($0) }) else { return nil }
        return text.contains("°") ? text : "\(text) °C"
    }

    // MARK: - Private -

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    }

    private static func nonBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
