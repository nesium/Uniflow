//
//  StoreQueue.swift
//  Uniflow
//
//  Created by Marc Bauer on 21.02.18.
//  Copyright © 2018 nesiumdotcom. All rights reserved.
//

import Foundation
import NittyGritty
import RxSwift

public class StoreQueue<StateType, ActionType> {
  private struct Item {
    private let exec: (@escaping () -> ()) -> (Disposable)
    private var subscription: Disposable?

    init<StateType, ActionType>(
      _ creator: AsyncActionCreator<StateType, ActionType>,
      dispatch: @escaping (ActionType) -> (),
      getState: @escaping () -> (StateType),
      completionHandler: @escaping (Error?) -> ()) {
      self.exec = { completion in
        return creator.exec(dispatch, getState)
          .observeOn(MainScheduler.instance)
          .subscribe(
            onCompleted: {
              completionHandler(nil)
              completion()
            },
            onError: {
              completionHandler($0)
              completion()
            }
          )
      }
    }

    mutating func execute(completion: @escaping () -> ()) {
      self.subscription = self.exec(completion)
    }
  }

  private var items = [Item]()
  private var currentItem: Item?

  private let store: Store<StateType, ActionType>
  private lazy var completionHandlers = [() -> ()]()

  public var isEmpty: Bool {
    return DispatchQueue.ng_syncOnMainThread {
      self.unguardedQueueIsEmpty
    }
  }

  public init(store: Store<StateType, ActionType>) {
    self.store = store
  }

  @discardableResult
  public func enqueue(_ actionCreator: AsyncActionCreator<StateType, ActionType>) -> Completable {
    var observableResult: CompletableEvent? = nil

    let observable = Completable.create { observer in
      DispatchQueue.ng_asyncOnMainThread {
        if let result = observableResult {
          observer(result)
          return
        }

        let (dispatch, stateLookup) = self.store.createDispatchAndLookup()

        let queueWasEmpty = self.unguardedQueueIsEmpty

        self.items.insert(
          Item(
            actionCreator,
            dispatch: dispatch,
            getState: stateLookup,
            completionHandler: { error in
              self.currentItem = nil

              let result: CompletableEvent
              if let error = error {
                result = .error(error)
              } else {
                result = .completed
              }
              observableResult = result
              observer(result)
            }
          ),
          at: 0
        )

        if queueWasEmpty {
          self.executeNext()
        }
      }

      return Disposables.create()
    }
    .asObservable()
    .share()

    // Make it hot
    _ = observable.subscribe(onCompleted: {})

    return observable.asCompletable()
  }

  public func addCompletion(_ handler: @escaping () -> ()) {
    DispatchQueue.ng_asyncOnMainThread {
      guard !self.unguardedQueueIsEmpty else {
        handler()
        return
      }

      self.completionHandlers.append(handler)
    }
  }

  private func executeNext() {
    precondition(DispatchQueue.ng_isMain)
    precondition(self.currentItem == nil)

    guard var item = items.popLast() else {
      self.completionHandlers.forEach { $0() }
      return
    }

    self.currentItem = item

    item.execute() { [weak self] in
      guard let strongSelf = self else {
        return
      }
      if strongSelf.currentItem == nil {
        strongSelf.executeNext()
      }
    }
  }

  private var unguardedQueueIsEmpty: Bool {
    precondition(DispatchQueue.ng_isMain)
    return self.currentItem == nil && self.items.isEmpty
  }
}
