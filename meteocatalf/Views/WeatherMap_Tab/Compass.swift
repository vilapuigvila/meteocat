//
//  Compass.swift
//  meteocatalf
//

import Foundation

/// Names the direction the phone points to: `315` is `NW`.
enum Compass {

    private static let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    /// `degrees` is clockwise from north; any value, negative or past 360, is taken round the circle.
    static func point(for degrees: Double) -> String {
        points[Int((normalized(degrees) + 22.5) / 45) % points.count]
    }

    /// `NW 315°`.
    static func text(for degrees: Double) -> String {
        "\(point(for: degrees)) \(Int(normalized(degrees).rounded()) % 360)°"
    }

    private static func normalized(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }
}
