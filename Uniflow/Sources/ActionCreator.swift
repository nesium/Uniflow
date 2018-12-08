//
//  ActionCreator.swift
//  Uniflow
//
//  Created by Marc Bauer on 22.02.18.
//  Copyright © 2018 nesiumdotcom. All rights reserved.
//

import Foundation
import NittyGritty

public typealias Dispatch<ActionType> = (ActionType) -> ()
public typealias GetState<StateType> = () -> (StateType)
public typealias Next<ActionType> = (ActionType) -> ()


public struct ActionCreator<StateType, ActionType> {
  public let exec: (@escaping Dispatch<ActionType>, @escaping GetState<StateType>) -> ()

  public init(_ exec: @escaping (
    _ dispatch: @escaping Dispatch<ActionType>,
    _ getState: @escaping GetState<StateType>
  ) -> ()) {
    self.exec = exec
  }
}



extension ActionCreator {
  public func lift<B>(
    action prism: Prism<B, ActionType>
  ) -> ActionCreator<StateType, B> {
    return ActionCreator<StateType, B> { dispatch, getState in
      let modifiedDispatch: Dispatch<ActionType> = { dispatch(prism.review($0)) }
      return self.exec(modifiedDispatch, getState)
    }
  }

  public func lift<T, B>(
    state: WritableKeyPath<T, StateType>,
    action prism: Prism<B, ActionType>
  ) -> ActionCreator<T, B> {
    return ActionCreator<T, B> { dispatch, getState in
      let modifiedDispatch: Dispatch<ActionType> = { dispatch(prism.review($0)) }
      let modifiedGetState: GetState<StateType> = { getState()[keyPath: state] }
      return self.exec(modifiedDispatch, modifiedGetState)
    }
  }
}
