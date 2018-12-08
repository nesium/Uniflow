//
//  AsyncActionCreator.swift
//  Uniflow
//
//  Created by Marc Bauer on 08.12.18.
//  Copyright © 2018 Marc Bauer. All rights reserved.
//

import Foundation
import NittyGritty
import RxSwift

public struct AsyncActionCreator<StateType, ActionType>: Monoid {
  public let exec: (@escaping Dispatch<ActionType>, @escaping GetState<StateType>) -> Completable

  public init(_ exec: @escaping (
    _ dispatch: @escaping Dispatch<ActionType>,
    _ getState: @escaping GetState<StateType>
  ) -> Completable) {
    self.exec = exec
  }

  public static var empty: AsyncActionCreator {
    return AsyncActionCreator { _, _ in Completable.empty() }
  }

  public static func <> (lhs: AsyncActionCreator, rhs: AsyncActionCreator) -> AsyncActionCreator {
    return AsyncActionCreator { dispatch, getState in
      lhs.exec(dispatch, getState)
        .andThen(Completable.deferred {
          rhs.exec(dispatch, getState)
        })
    }
  }
}



extension AsyncActionCreator {
  public func lift<B>(
    action prism: Prism<B, ActionType>
  ) -> AsyncActionCreator<StateType, B> {
    return AsyncActionCreator<StateType, B> { dispatch, getState in
      let modifiedDispatch: Dispatch<ActionType> = { dispatch(prism.review($0)) }
      return self.exec(modifiedDispatch, getState)
    }
  }

  public func lift<T, B>(
    state: WritableKeyPath<T, StateType>,
    action prism: Prism<B, ActionType>
  ) -> AsyncActionCreator<T, B> {
    return AsyncActionCreator<T, B> { dispatch, getState in
      let modifiedDispatch: Dispatch<ActionType> = { dispatch(prism.review($0)) }
      let modifiedGetState: GetState<StateType> = { getState()[keyPath: state] }
      return self.exec(modifiedDispatch, modifiedGetState)
    }
  }
}
