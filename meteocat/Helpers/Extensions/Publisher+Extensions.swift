//
//  Publisher+Extensions.swift
//  meteocat
//
//  Created by albert vila on 6/2/25.
//

import Foundation
import Combine

extension Publisher where Failure == Never {
  func weakAssign<O: AnyObject>(
      to keyPath: ReferenceWritableKeyPath<O, Output>,
      on object: O
  ) -> AnyCancellable {
      sink { [weak object] value in
          object?[keyPath: keyPath] = value
      }
  }
}

extension Date {
    
    func areDatesInSameDay(_ date1: Date, _ date2: Date) -> Bool {
        Calendar.current.isDate(date1, inSameDayAs: date2)
    }
    func adding(millis: Int) -> Date {
        return Calendar.current.date(byAdding: .nanosecond, value: millis, to: self)!
    }
    func adding(seconds: Int) -> Date {
        return Calendar.current.date(byAdding: .second, value: seconds, to: self)!
    }
    func adding(minutes: Int) -> Date {
        return Calendar.current.date(byAdding: .minute, value: minutes, to: self)!
    }
    func adding(hours: Int) -> Date {
        return Calendar.current.date(byAdding: .hour, value: hours, to: self)!
    }
    func adding(days: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: days, to: self)!
    }
    func adding(hours: Int, minutes: Int) -> Date {
        return (Calendar.current.date(byAdding: .hour, value: hours, to: self)?.adding(minutes: minutes))!
    }
    func adding(hours: Int, minutes: Int, seconds: Int) -> Date {
        return (Calendar.current.date(byAdding: .hour, value: hours, to: self)?.adding(minutes: minutes).adding(seconds: seconds))!
    }
}
