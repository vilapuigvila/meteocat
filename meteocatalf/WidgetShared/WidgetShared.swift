//
//  WidgetShared.swift
//  meteocatalf
//

import Foundation

/// Names both the app and the widget extension use. This folder is compiled into both targets: Foundation only.
enum WidgetShared {
    /// The App Group the app writes the snapshot to and the widget reads it from.
    static let appGroupID = "group.com.pskmoons.meteocat"
    /// Kind of the home station widget, used to reload its timelines.
    static let homeStationKind = "HomeStationWidget"
}
