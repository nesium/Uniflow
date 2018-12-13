//
//  Store.swift
//  Uniflow
//
//  Created by Marc Bauer on 19.02.18.
//  Copyright © 2018 nesiumdotcom. All rights reserved.
//

import Foundation
import NSMFoundation
import RxSwift

public class Store<StateType, ActionType> {
  private var _state: StateType {
    didSet { self.stateSubject.onNext(self.state) }
  }
  private var _dispatch: ((ActionType) -> ())!
  
  private let stateSubject: BehaviorSubject<StateType>
  private let reducer: Reducer<StateType, ActionType>

  private lazy var queue: StoreQueue<StateType, ActionType> = StoreQueue(store: self)
  private lazy var disposeBag = DisposeBag()

  public var state: StateType {
    return DispatchQueue.nsm_syncOnMainThread { self._state }
  }

  public var observableState: Observable<StateType> {
    return stateSubject.asObservable()
  }

  public init(
    reducer: Reducer<StateType, ActionType>,
    initialState: StateType,
    middleware: Middleware<StateType, ActionType>? = nil
  ) {
    self.reducer = reducer
    self._state = initialState
    self.stateSubject = BehaviorSubject(value: initialState)

    let last: Next = { [weak self] action in
      self?.performDispatch(action)
    }

    if let middleware = middleware {
      let stateLookup: GetState = { [weak self] in
        DispatchQueue.nsm_syncOnMainThread {
          self?._state ?? initialState
        }
      }

      var initialDispatchQueue = [ActionType]()
      let dispatch: Dispatch<ActionType> = { [weak self] action in
        self?._dispatch?(action) ?? initialDispatchQueue.append(action)
      }

      let next = middleware.exec(dispatch, stateLookup, self.disposeBag)
      self._dispatch = { action in
        next(action, last)
      }

      initialDispatchQueue.forEach(self._dispatch)
    } else {
      self._dispatch = last
    }
  }

  public func dispatch(_ action: ActionType) {
    DispatchQueue.nsm_asyncOnMainThread {
      self._dispatch(action)
    }
  }

  public func dispatch(_ actionCreator: ActionCreator<StateType, ActionType>) {
    let (dispatch, stateLookup) = self.createDispatchAndLookup()
    actionCreator.exec(dispatch, stateLookup)
  }

  @discardableResult
  public func dispatch(_ actionCreator: AsyncActionCreator<StateType, ActionType>) -> Completable {
    let (dispatch, stateLookup) = self.createDispatchAndLookup()

    // Share observable
    let observable = actionCreator.exec(dispatch, stateLookup)
      .asObservable()
      .share()

    // Make it hot
    _ = observable.subscribe(onCompleted: {})

    return observable.asCompletable()
  }

  internal func createDispatchAndLookup() -> ((ActionType) -> (), () -> (StateType)) {
    let state = self.state
    let stateLookup: () -> (StateType) = { [weak self] in
      DispatchQueue.nsm_syncOnMainThread {
        self?._state ?? state
      }
    }
    return ({ [weak self] in self?.dispatch($0) }, stateLookup)
  }

  private func performDispatch(_ action: ActionType) {
    DispatchQueue.nsm_asyncOnMainThread {
      self.reducer.reduce(&self._state, action)
    }
  }
}
