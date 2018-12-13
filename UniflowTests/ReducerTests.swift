//
//  ReducerTests.swift
//  UniflowTests
//
//  Created by Marc Bauer on 16.01.18.
//  Copyright © 2018 nesiumdotcom. All rights reserved.
//

import Foundation
import NSMFoundation
import Uniflow
import XCTest

class ReducerTests: XCTestCase {
  struct ArrayState {
    var arr = [String]()
  }

  struct State {
    var str: String
    var num: Int
    var arr: ArrayState
  }

  enum IntAction {
    case add(Int)
  }

  enum StringAction {
    case append(String)
  }

  enum ArrayAction {
    case append(String)
  }

  enum StateAction {
    case intAction(IntAction)
    case stringAction(StringAction)
    case arrayAction(ArrayAction)
  }

  func testReducerComposition() {
    let StringReducer = Reducer<String, StringAction> { state, action in
      switch action {
        case .append(let suffix):
          state.append(suffix)
      }
    }

    let IntReducer = Reducer<Int, IntAction> { state, action in
      switch action {
        case .add(let num):
          state += num
      }
    }

    let ArrReducer = Reducer<ArrayState, ArrayAction> { state, action in
      switch action {
        case .append(let item):
          state.arr.append(item)
      }
    }

    let StateReducer =
      IntReducer.lift(state: MutatingLens(keyPath: \State.num), action: StateAction.prism.intAction)
      <> StringReducer.lift(state: \State.str, action: StateAction.prism.stringAction)
      <> ArrReducer.lift(state: \State.arr, action: StateAction.prism.arrayAction)

    let stringMiddleware = Middleware<String, StringAction> { dispatch, getState, disposeBag in
      return { action, next in
        switch action {
          case .append(let str):
            next(.append(str + "_" + str))
        }
      }
    }

    let intMiddleware = Middleware<Int, IntAction> { dispatch, getState, disposeBag in
      return { action, next in
        switch action {
          case .add(let num):
            next(.add(num * 2))
        }
      }
    }

    let stringMiddlewareOnWholeState = Middleware<State, StringAction> { dispatch, getState, disposeBag in
      return { action, next in
        switch action {
          case .append(let str):
            next(.append(str + "."))
        }
      }
    }

    let middleware: Middleware<State, StateAction> =
      stringMiddleware.lift(
        state: \State.str,
        action: StateAction.prism.stringAction
      )
      <>
      intMiddleware.lift(
        state: \State.num,
        action: StateAction.prism.intAction
      )
      <>
      stringMiddlewareOnWholeState.lift(
        action: StateAction.prism.stringAction
      )

    let store = Store(
      reducer: StateReducer,
      initialState: .init(str: "A", num: 1, arr: .init()),
      middleware: middleware
    )

    store.dispatch(.intAction(.add(1)))
    XCTAssertEqual(store.state.num, 3)
    XCTAssertEqual(store.state.str, "A")
    XCTAssertEqual(store.state.arr.arr, [])

    store.dispatch(.stringAction(.append("B")))
    XCTAssertEqual(store.state.num, 3)
    XCTAssertEqual(store.state.str, "AB_B.")
    XCTAssertEqual(store.state.arr.arr, [])

    store.dispatch(.arrayAction(.append("#")))
    XCTAssertEqual(store.state.num, 3)
    XCTAssertEqual(store.state.str, "AB_B.")
    XCTAssertEqual(store.state.arr.arr, ["#"])

    store.dispatch(.intAction(.add(3)))
    XCTAssertEqual(store.state.num, 9)
    XCTAssertEqual(store.state.str, "AB_B.")
    XCTAssertEqual(store.state.arr.arr, ["#"])

    store.dispatch(.arrayAction(.append("#")))
    XCTAssertEqual(store.state.num, 9)
    XCTAssertEqual(store.state.str, "AB_B.")
    XCTAssertEqual(store.state.arr.arr, ["#", "#"])
  }
}


extension ReducerTests.StateAction {
  enum prism {
    static let intAction = Prism<ReducerTests.StateAction, ReducerTests.IntAction>(
      preview: { (stateAction: ReducerTests.StateAction) -> ReducerTests.IntAction? in
        if case let .intAction(action) = stateAction {
          return action
        }
        return nil
      },
      review: ReducerTests.StateAction.intAction
    )

    static let stringAction = Prism<ReducerTests.StateAction, ReducerTests.StringAction>(
      preview: { (stateAction: ReducerTests.StateAction) -> ReducerTests.StringAction? in
        if case let .stringAction(action) = stateAction {
          return action
        }
        return nil
      },
      review: ReducerTests.StateAction.stringAction
    )

    static let arrayAction = Prism<ReducerTests.StateAction, ReducerTests.ArrayAction>(
      preview: { (stateAction: ReducerTests.StateAction) -> ReducerTests.ArrayAction? in
        if case let .arrayAction(action) = stateAction {
          return action
        }
        return nil
      },
      review: ReducerTests.StateAction.arrayAction
    )
  }
}
