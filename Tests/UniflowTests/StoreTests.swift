//
//  ReduxStoreTests.swift
//  UniflowTests
//
//  Created by Marc Bauer on 20.02.18.
//  Copyright © 2018 nesiumdotcom. All rights reserved.
//

import NSMFoundation
import RxSwift
import Uniflow
import XCTest

class StoreTests: XCTestCase {
  enum Action {
    case action(String)
  }

  struct State {
    var actions = [String]()
  }

  static let reducer = Reducer<State, Action> { state, action in
    switch action {
      case .action(let str):
        state.actions.append(str)
    }
  }

  func testPlainActions() {
    let store = Store(reducer: StoreTests.reducer, initialState: State())

    store.dispatch(.action("A"))
    store.dispatch(.action("B"))
    store.dispatch(.action("C"))

    XCTAssertEqual(store.state.actions, ["A", "B", "C"])
  }

  func testActionCreators() {
    let store = Store(reducer: StoreTests.reducer, initialState: State())

    let exp = expectation(description: "Waiting…")

    let action1 = ActionCreator<State, Action> { dispatch, getState in
      DispatchQueue.global().asyncAfter(deadline: .now() + 0.1, execute: {
        XCTAssertEqual(getState().actions, [])
        dispatch(.action("A"))
      })
      DispatchQueue.global().asyncAfter(deadline: .now() + 0.3, execute: {
        XCTAssertEqual(getState().actions, ["A", "C"])
        dispatch(.action("B"))
      })
    }

    let action2 = ActionCreator<State, Action> { dispatch, getState in
      DispatchQueue.global().asyncAfter(deadline: .now() + 0.2, execute: {
        XCTAssertEqual(getState().actions, ["A"])
        dispatch(.action("C"))
      })
      DispatchQueue.global().asyncAfter(deadline: .now() + 0.4, execute: {
        XCTAssertEqual(getState().actions, ["A", "C", "B"])
        dispatch(.action("D"))
        exp.fulfill()
      })
    }

    store.dispatch(action1)
    store.dispatch(action2)

    waitForExpectations(timeout: 1) { error in
      XCTAssertNil(error)
      XCTAssertEqual(store.state.actions, ["A", "C", "B", "D"])
    }
  }

  func testLiftedActionCreator() {
    enum OuterAction {
      enum InnerAction {
        case action1(String)
      }
      case inner(InnerAction)
    }

    struct OuterState {
      struct InnerState {
        var result: String
      }
      var inner: InnerState
    }

    let reducer = Reducer<OuterState, OuterAction> { state, action in
      switch action {
        case .inner(.action1(let value)):
          state.inner.result = value
      }
    }

    let action1 = AsyncActionCreator<OuterState, OuterAction.InnerAction> { dispatch, getState in
      Completable.create { observer in
        dispatch(.action1(getState().inner.result + "B"))
        observer(.completed)
        return Disposables.create()
      }
    }

    let action2 = AsyncActionCreator<OuterState.InnerState, OuterAction.InnerAction> { dispatch, getState in
      Completable.create { observer in
        dispatch(.action1(getState().result + "C"))
        observer(.completed)
        return Disposables.create()
      }
    }

    let prism = Prism<OuterAction, OuterAction.InnerAction>(
      preview: { (stateAction: OuterAction) -> OuterAction.InnerAction? in
        if case let .inner(action) = stateAction {
          return action
        }
        return nil
      },
      review: OuterAction.inner
    )

    let store = Store(
      reducer: reducer,
      initialState: OuterState(inner: OuterState.InnerState(result: "A"))
    )

    store.dispatch(action1.lift(action: prism))
    store.dispatch(action2.lift(state: \OuterState.inner, action: prism))

    XCTAssertEqual(store.state.inner.result, "ABC")
  }

  func testAppendedAsyncActions() {
    let store = Store(reducer: StoreTests.reducer, initialState: State())

    func makeObservable(type: String, delay: TimeInterval) -> Observable<Action> {
      return Observable.create { observer in
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: {
          observer.onNext(.action(type))
          observer.onCompleted()
        })
        return Disposables.create()
      }
    }

    let action1 = AsyncActionCreator<State, Action> { dispatch, getState in
      makeObservable(type: "A", delay: 0.2)
        .do(onNext: dispatch)
        .ignoreElements()
    }

    let action2 = AsyncActionCreator<State, Action> { dispatch, getState in
      guard let resultOfFirstAction = getState().actions.first else {
        return Completable.error(NSError(
          domain: "TestDomain",
          code: -1,
          userInfo: [
            NSLocalizedDescriptionKey:
              "The second action should see the result of performing the first action"
          ]
        ))
      }
      return makeObservable(type: resultOfFirstAction + "B", delay: 0.1)
        .do(onNext: dispatch)
        .ignoreElements()
    }

    let combinedAction = action1 <> action2

    expect { done in
      store.dispatch(combinedAction)
        .observeOn(MainScheduler.instance)
        .do(onCompleted: {
          XCTAssertEqual(store.state.actions, ["A", "AB"])
          done()
        })
    }
  }

  func testDispatchingAnObservableWithoutSubscribingExecutes() {
    let exp = expectation(description: "Waiting…")

    let action = AsyncActionCreator<State, Action> { dispatch, getState in
      Completable.create { observer in
        observer(.completed)
        exp.fulfill()
        return Disposables.create()
      }
    }

    let store = Store(reducer: StoreTests.reducer, initialState: State())
    store.dispatch(action)

    waitForExpectations(timeout: 1)
  }

  func testMultipleSerialSubscriptionsOnStoreDoNotExecuteObservableMultipleTimes() {
    let store = Store(reducer: UniflowTests.reducer, initialState: MyState())

    let dispatch = store.dispatch(PushItemAction(item: 99, delay: 0.1)).debug()

    let exp = expectation(description: "Waiting…")

    _ = dispatch
      .andThen(Completable.deferred {
        dispatch
      }.delay(.milliseconds(100), scheduler: MainScheduler.instance))
      .subscribe(onCompleted: {
        XCTAssertEqual(store.state.items, [99])
        exp.fulfill()
      })

    waitForExpectations(timeout: 1)
  }

  func testEverythingIsReleased() {
    var actionIsDisposed = false

    let action: AsyncActionCreator<MyState, MyAction> = AsyncActionCreator { dispatch, getState in
      return Completable.create { observer in
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 0.1) {
          dispatch(.addItem(100))
          observer(.completed)
        }
        return Disposables.create()
      }
        .do(onDispose: {
          actionIsDisposed = true
        })
    }

    let store = Store(reducer: UniflowTests.reducer, initialState: MyState())
    let exp = expectation(description: "Waiting…")

    _ = store.dispatch(action)
      .andThen(Completable.deferred {
        Completable.empty().delay(.milliseconds(100), scheduler: MainScheduler.instance)
      })
      .do(onDispose: {
        XCTAssertTrue(actionIsDisposed)
        exp.fulfill()
      })
      .subscribe()

    waitForExpectations(timeout: 1)
  }
}
