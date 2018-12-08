//
//  MiddlewareTests.swift
//  UniflowTests
//
//  Created by Marc Bauer on 08.12.18.
//  Copyright © 2018 Marc Bauer. All rights reserved.
//

import Foundation
import NittyGritty
import RxSwift
import Uniflow
import XCTest

final class MiddlewareTests: XCTestCase {
  func testMiddleware() {
    func makeMiddleware(
      appending str: String
    ) -> Middleware<StoreTests.State, StoreTests.Action> {
      return Middleware { dispatch, getState, disposeBag in
        return { action, next in
          switch action {
            case .action(let value):
              next(.action(value + str))
          }
        }
      }
    }

    let dispatchingMiddleware = Middleware<
      StoreTests.State,
      StoreTests.Action
    > { dispatch, getState, disposeBag in
      return { action, next in
        switch action {
          case .action(let value) where value == "A123":
            dispatch(.action("B"))
            XCTAssertEqual(getState().actions, ["B1234"])
            next(.action(value + "4"))
          case .action(let value):
            next(.action(value + "4"))
        }
      }
    }

    let m1 = makeMiddleware(appending: "1")
    let m2 = makeMiddleware(appending: "2")
    let m3 = makeMiddleware(appending: "3")

    let store = Store(
      reducer: StoreTests.reducer,
      initialState: StoreTests.State(),
      middleware: m1 <> m2 <> m3 <> dispatchingMiddleware
    )

    store.dispatch(.action("A"))

    XCTAssertEqual(store.state.actions, ["B1234", "A1234"])
  }

  func testLiftedMiddlewareInstantiation() {
    var instantiationCount = 0

    enum MyAction {
      case action1(String)
      case action2(String)
    }

    let reducer = Reducer<StoreTests.State, MyAction> { state, action in
      switch action {
        case .action1(let value):
          state.actions.append(value)
        case .action2(let value):
          state.actions.append(value)
      }
    }

    let middleware = Middleware<
      StoreTests.State,
      MyAction
    > { dispatch, getState, disposeBag in
      instantiationCount += 1

      return { action, next in
        switch action {
          case .action1(let value):
            dispatch(.action2(value))
          case .action2:
            next(action)
        }
      }
    }

    let store = Store(
      reducer: reducer,
      initialState: StoreTests.State(),
      middleware: middleware.lift(action: Prism<MyAction, MyAction>(
        preview: { $0 },
        review: { $0 }
      ))
    )

    store.dispatch(.action1("A"))
    store.dispatch(.action1("B"))

    XCTAssertEqual(store.state.actions, ["A", "B"])
    XCTAssertEqual(instantiationCount, 1)
  }

  func testImmediateDispatchInMiddleware() {
    enum MyAction {
      case action1(String)
      case action2(String)
    }

    let reducer = Reducer<StoreTests.State, MyAction> { state, action in
      switch action {
        case .action1(let value):
          state.actions.append(value)
        case .action2(let value):
          state.actions.append(value)
      }
    }

    let middleware = Middleware<StoreTests.State, MyAction> { dispatch, getState, disposeBag in
      dispatch(.action1("X"))

      return { action, next in
        switch action {
          case .action1(let value):
            dispatch(.action2(value))
          case .action2:
            next(action)
        }
      }
    }

    let store = Store(
      reducer: reducer,
      initialState: StoreTests.State(),
      middleware: middleware
    )

    store.dispatch(.action1("A"))
    store.dispatch(.action1("B"))

    XCTAssertEqual(store.state.actions, ["X", "A", "B"])
  }

  func testMiddlewareWithActionCreators() {
    let middleware = Middleware<
      StoreTests.State,
      StoreTests.Action
    > { dispatch, getState, disposeBag in
      return { action, next in
        switch action {
          case .action(let value):
            next(.action(value + "1"))
        }
      }
    }

    let store = Store(
      reducer: StoreTests.reducer,
      initialState: StoreTests.State(),
      middleware: middleware
    )

    let exp = expectation(description: "Waiting…")

    let action1 = ActionCreator<StoreTests.State, StoreTests.Action> { dispatch, getState in
      DispatchQueue.global().asyncAfter(deadline: .now() + 0.1, execute: {
        XCTAssertEqual(getState().actions, [])
        dispatch(.action("A"))
        exp.fulfill()
      })
    }

    store.dispatch(action1)

    waitForExpectations(timeout: 1) { error in
      XCTAssertNil(error)
      XCTAssertEqual(store.state.actions, ["A1"])
    }
  }

  func testMiddlewareInitialState() {
    let middleware = Middleware<
      StoreTests.State,
      StoreTests.Action
    > { dispatch, getState, disposeBag in
      let initialValue = getState().actions.first ?? "FAIL"

      return { action, next in
        switch action {
          case .action(let value):
            next(.action(value + initialValue))
        }
      }
    }

    let store = Store(
      reducer: StoreTests.reducer,
      initialState: StoreTests.State(actions: ["A"]),
      middleware: middleware
    )

    store.dispatch(.action("B"))

    XCTAssertEqual(store.state.actions, ["A", "BA"])
  }

  func testMiddlewareDisposeBag() {
    let subject = BehaviorSubject<Int>(value: 0)
    var observableIsDisposed = false

    let middleware = Middleware<
      StoreTests.State,
      StoreTests.Action
    > { dispatch, getState, disposeBag in
      subject.subscribe(onDisposed: {
        observableIsDisposed = true
      })
        .disposed(by: disposeBag)

      return { action, next in
        next(action)
      }
    }

    var store: Store? = Store(
      reducer: StoreTests.reducer,
      initialState: StoreTests.State(),
      middleware: middleware
    )

    store?.dispatch(.action("A"))

    XCTAssertEqual(store?.state.actions, ["A"])
    XCTAssertFalse(observableIsDisposed)

    store = nil
    XCTAssertTrue(observableIsDisposed)
  }
}
