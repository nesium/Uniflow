//
//  Reducer.swift
//  Uniflow
//
//  Created by Marc Bauer on 16.01.18.
//  Copyright © 2018 nesiumdotcom. All rights reserved.
//

import Foundation
import NittyGritty

public struct Reducer<S, A>: Monoid {
  let reduce: (inout S, A) -> Void

  public init(_ reduce: @escaping (inout S, A) -> Void) {
    self.reduce = reduce
  }

  public static var empty: Reducer {
    return Reducer { s, _ in }
  }

  public static func <> (lhs: Reducer, rhs: Reducer) -> Reducer {
    return Reducer { state, action in
      lhs.reduce(&state, action)
      rhs.reduce(&state, action)
    }
  }
}



extension Reducer {
  public func lift<T>(state: WritableKeyPath<T, S>) -> Reducer<T, A> {
    return Reducer<T, A> { t, a in
      self.reduce(&t[keyPath: state], a)
    }
  }

  public func lift<T>(state: MutatingLens<T, S>) -> Reducer<T, A> {
    return Reducer<T, A> { t, a in
      var part = state.view(t)
      self.reduce(&part, a)
      state.mutatingSet(&t, part)
    }
  }

  public func lift<B>(action: Prism<B, A>) -> Reducer<S, B> {
    return Reducer<S, B> { s, b in
      guard let a = action.preview(b) else {
        return
      }
      self.reduce(&s, a)
    }
  }

  public func lift<T, B>(state: WritableKeyPath<T, S>, action: Prism<B, A>) -> Reducer<T, B> {
    return Reducer<T, B> { t, b in
      guard let actionA = action.preview(b) else { return }
      self.reduce(&t[keyPath: state], actionA)
    }
  }

  public func lift<T, B>(state: MutatingLens<T, S>, action: Prism<B, A>) -> Reducer<T, B> {
    return Reducer<T, B> { t, b in
      guard let actionA = action.preview(b) else { return }
      var part = state.view(t)
      self.reduce(&part, actionA)
      state.mutatingSet(&t, part)
    }
  }
}
