//
//  Publisher+Extensions.swift
//  meteocat
//
//  Created by albert vila on 6/2/25.
//

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
