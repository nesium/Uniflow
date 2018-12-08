//
//  StoreTests.swift
//  W2BackendTests
//
//  Created by Marc Bauer on 19.10.17.
//  Copyright © 2017 nesiumdotcom. All rights reserved.
//

import Foundation
import RxSwift
import Uniflow
import XCTest

struct MyState {
  var items: [Int] = []
}

enum MyAction {
  case addItem(Int)
  case callback((MyState) -> ())
}

let concurrentScheduler = ConcurrentDispatchQueueScheduler(qos: .background)

func SquareLastItemAction(delay: TimeInterval = 0.2) -> AsyncActionCreator<MyState, MyAction> {
  return AsyncActionCreator { dispatch, getState in
    let lastItem = (getState().items.last ?? 0) + 1

    return Completable.create { observer in
      DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + delay) {
        dispatch(.addItem(lastItem * lastItem))
        observer(.completed)
      }
      return Disposables.create()
    }
  }
}

func PushItemAction(item: Int, delay: TimeInterval = 0)
  -> AsyncActionCreator<MyState, MyAction> {
  return AsyncActionCreator { dispatch, getState in
    guard delay > 0 else {
      dispatch(.addItem(item))
      return Completable.empty()
    }

    return Completable.create { observer in
      DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + delay) {
        dispatch(.addItem(item))
        observer(.completed)
      }
      return Disposables.create()
    }
  }
}

let reducer = Reducer<MyState, MyAction> { state, action in
  switch action {
    case .addItem(let item):
      state.items.append(item)
    case .callback(let callback):
      callback(state)
  }
}



class QueueTests: XCTestCase {
  func testAsyncActionQueueing() {
    let store = Store(reducer: StoreTests.reducer, initialState: StoreTests.State())
    let queueA = StoreQueue(store: store)
    let queueB = StoreQueue(store: store)

    let exp = expectation(description: "Waiting…")

    func makeAction(
      type: String,
      delay: TimeInterval
    ) -> AsyncActionCreator<StoreTests.State, StoreTests.Action> {
      return AsyncActionCreator { dispatch, getState in
        Completable.create { observer in
          DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: {
            dispatch(.action(type))
            observer(.completed)
          })
          return Disposables.create()
        }
      }
    }

    let action1 = makeAction(type: "A", delay: 0.4)
    let action2 = makeAction(type: "B", delay: 0.1)

    let action3 = makeAction(type: "C", delay: 0.2)
    let action4 = makeAction(type: "D", delay: 0.1)


    queueA.enqueue(action1)
    _ = queueA.enqueue(action2)
      .subscribe(onCompleted: {
        exp.fulfill()
      })

    queueB.enqueue(action3)
    queueB.enqueue(action4)

    waitForExpectations(timeout: 5) { error in
      XCTAssertNil(error)
      XCTAssertEqual(store.state.actions, ["C", "D", "A", "B"])
    }
  }

  func testQueueForwardsErrors() {
    let exp = expectation(description: "Waiting…")

    let action = AsyncActionCreator<
      StoreTests.State,
      StoreTests.Action
    > { dispatch, getState in
      Completable.create { observer in
        observer(.error(NSError(domain: "TestDomain", code: -1, userInfo: nil)))
        return Disposables.create()
      }
    }

    let store = Store(reducer: StoreTests.reducer, initialState: StoreTests.State())
    let queue = StoreQueue(store: store)

    _ = queue.enqueue(action)
      .subscribe(
        onCompleted: {
          XCTFail()
        },
        onError: {
          XCTAssertEqual(($0 as NSError).domain, "TestDomain")
          exp.fulfill()
        }
      )

    waitForExpectations(timeout: 1)
  }

  func testQueueOrder() {
    func makeAction(
      action: String
    ) -> AsyncActionCreator<StoreTests.State, StoreTests.Action> {
      return AsyncActionCreator<
        StoreTests.State,
        StoreTests.Action
      > { dispatch, getState in
        dispatch(.action(action))
        return Completable.empty()
      }
    }

    func makeAsyncAction(action: String) -> AsyncActionCreator<
      StoreTests.State,
      StoreTests.Action
    > {
      return AsyncActionCreator<
        StoreTests.State,
        StoreTests.Action
      > { dispatch, getState in
        return Completable.create { observer in
          DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            dispatch(.action(action))
            observer(.completed)
          }
          return Disposables.create()
        }
      }
    }

    let store = Store(reducer: StoreTests.reducer, initialState: StoreTests.State())
    let queue = StoreQueue(store: store)

    let exp = expectation(description: "Waiting…")

    _ = queue.enqueue(makeAsyncAction(action: "A"))
      .subscribe(onCompleted: {
        queue.enqueue(makeAsyncAction(action: "C"))
      })
    queue.enqueue(makeAction(action: "B"))


    queue.addCompletion {
      XCTAssertEqual(store.state.actions, ["A", "B", "C"])
      exp.fulfill()
    }

    waitForExpectations(timeout: 1)
  }

  func testSerialSubscription() {
    let store = Store(reducer: reducer, initialState: MyState())
    let queue = StoreQueue(store: store)

    var collectedResults: [MyState] = []

    _ = store.observableState
      .subscribe(onNext: {
        collectedResults.append($0)
      })

    expect { done in
      queue.enqueue(SquareLastItemAction())
        .andThen(queue.enqueue(SquareLastItemAction()))
        .andThen(queue.enqueue(SquareLastItemAction()))
        .andThen(queue.enqueue(PushItemAction(item: 99)))
        .do(onCompleted: {
          XCTAssertEqual(store.state.items, [1, 4, 25, 99])

          let items = collectedResults.map { $0.items }
          XCTAssertEqual(items[0], [])
          XCTAssertEqual(items[1], [1])
          XCTAssertEqual(items[2], [1, 4])
          XCTAssertEqual(items[3], [1, 4, 25])
          XCTAssertEqual(items[4], [1, 4, 25, 99])

          done()
        })
    }
  }

  func testParallelSubscription() {
    let store = Store(reducer: reducer, initialState: MyState())
    let queue = StoreQueue(store: store)

    expect(timeout: 2) { done in
      Completable.merge(
        queue.enqueue(SquareLastItemAction(delay: 0.2)),
        queue.enqueue(SquareLastItemAction(delay: 0.0)),
        queue.enqueue(SquareLastItemAction(delay: 0.4)),
        queue.enqueue(PushItemAction(item: 99))
      )
      .andThen(store.observableState.take(1))
      .map { state in
        XCTAssertEqual(state.items, [1, 4, 25, 99])
        done()
      }
    }
  }

  func testMultipleSubscriptionOnStoreDoesNotExecuteObservableMultipleTimes() {
    let store = Store(reducer: reducer, initialState: MyState())

    let dispatch = store.dispatch(PushItemAction(item: 99, delay: 0.1))

    _ = dispatch.subscribe(onCompleted: {})
    _ = dispatch.subscribe(onCompleted: {})

    expect { done in
      dispatch
        .observeOn(MainScheduler.instance)
        .do(onCompleted: {
          XCTAssertEqual(store.state.items, [99])
          done()
        })
    }
  }

  func testMultipleSubscriptionOnQueueDoesNotExecuteObservableMultipleTimes() {
    let store = Store(reducer: reducer, initialState: MyState())
    let queue = StoreQueue(store: store)

    let dispatch = queue.enqueue(PushItemAction(item: 99, delay: 0.1))

    _ = dispatch.subscribe(onCompleted: {})
    _ = dispatch.subscribe(onCompleted: {})

    expect { done in
      dispatch
        .observeOn(MainScheduler.instance)
        .do(onCompleted: {
          XCTAssertEqual(store.state.items, [99])
          done()
        })
    }
  }

  func testMultipleSubscriptionOnQueueWithImmediateCompletingObservableDoesNotExecuteObservableMultipleTimes() {
    let store = Store(reducer: reducer, initialState: MyState())
    let queue = StoreQueue(store: store)

    let dispatch = queue.enqueue(PushItemAction(item: 99, delay: 0))

    _ = dispatch.subscribe(onCompleted: {})
    _ = dispatch.subscribe(onCompleted: {})

    expect { done in
      dispatch
        .observeOn(MainScheduler.instance)
        .do(onCompleted: {
          XCTAssertEqual(store.state.items, [99])
          done()
        })
    }
  }

  func testQueueNotificationOrder() {
    let store = Store(reducer: reducer, initialState: MyState())
    let queue = StoreQueue(store: store)

    var completionHandlerCalled: Int = 0
    var observableIsCompleted = false

    queue.addCompletion {
      completionHandlerCalled += 1
    }

    XCTAssertEqual(completionHandlerCalled, 1)

    expect { done in
      Observable<Void>.create { observer in
        let sub = Completable.merge(
          queue.enqueue(PushItemAction(item: 2, delay: 0.1)),
          queue.enqueue(PushItemAction(item: 3, delay: 0))
        )
        .subscribe(onCompleted: {
          XCTAssertTrue(queue.isEmpty)
          XCTAssertEqual(completionHandlerCalled, 1)
          XCTAssertEqual(store.state.items, [2, 3])
          observableIsCompleted = true
        })

        queue.addCompletion {
          XCTAssertTrue(queue.isEmpty)
          XCTAssertTrue(observableIsCompleted)
          done()
          observer.onCompleted()
        }

        XCTAssertFalse(queue.isEmpty, "queue should not be empty")

        return Disposables.create([sub])
      }
    }
  }
}

