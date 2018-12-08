//
//  Middleware.swift
//  Uniflow
//
//  Created by Marc Bauer on 13.03.18.
//  Copyright © 2018 nesiumdotcom. All rights reserved.
//

import Foundation
import NittyGritty
import RxSwift

public struct Middleware<StateType, ActionType> {
  public let exec: (
    @escaping Dispatch<ActionType>,
    @escaping GetState<StateType>,
    DisposeBag
  ) -> (ActionType, @escaping Next<ActionType>) -> ()

  public init(_ exec: @escaping (
    _ dispatch: @escaping Dispatch<ActionType>,
    _ getState: @escaping GetState<StateType>,
    _ disposeBag: DisposeBag
  ) -> (ActionType, @escaping Next<ActionType>) -> ()) {
    self.exec = exec
  }

  public static func <> (lhs: Middleware, rhs: Middleware) -> Middleware {
    return Middleware { dispatch, getState, disposeBag in
      let a = lhs.exec(dispatch, getState, disposeBag)
      let b = rhs.exec(dispatch, getState, disposeBag)

      return { action, next in
        a(action, { b($0, next) })
      }
    }
  }
}



extension Middleware {
  public func lift<B>(
    action prism: Prism<B, ActionType>
  ) -> Middleware<StateType, B> {
    return Middleware<StateType, B> { dispatch, getState, disposeBag in
      let modifiedDispatch: Dispatch<ActionType> = { dispatch(prism.review($0)) }
      let middleware = self.exec(modifiedDispatch, getState, disposeBag)

      return { action, next in
        guard let modifiedAction = prism.preview(action) else {
          next(action)
          return
        }
        let modifiedNext: Next<ActionType> = { next(prism.review($0)) }
        middleware(modifiedAction, modifiedNext)
      }
    }
  }

  public func lift<T, B>(
    state: WritableKeyPath<T, StateType>,
    action prism: Prism<B, ActionType>
  ) -> Middleware<T, B> {
    return Middleware<T, B> { dispatch, getState, disposeBag in
      let modifiedDispatch: Dispatch<ActionType> = { dispatch(prism.review($0)) }
      let modifiedGetState: GetState<StateType> = { getState()[keyPath: state] }
      let middleware = self.exec(modifiedDispatch, modifiedGetState, disposeBag)

      return { action, next in
        guard let modifiedAction = prism.preview(action) else {
          next(action)
          return
        }
        let modifiedNext: Next<ActionType> = { next(prism.review($0)) }
        middleware(modifiedAction, modifiedNext)
      }
    }
  }
}
