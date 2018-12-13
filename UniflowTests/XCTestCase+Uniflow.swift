//
//  XCTestCase+Uniflow.swift
//  UniflowTests
//
//  Created by Marc Bauer on 11.11.17.
//  Copyright © 2017 nesiumdotcom. All rights reserved.
//

import Foundation
import RxSwift
import XCTest

extension XCTestCase {
  func expect(
    timeout: TimeInterval = 1,
    _ observable: (_ done: @escaping () -> ()) -> Observable<Void>) {
    let exp = expectation(description: "Waiting…")
    var done: Bool = false
    _ = observable({ done = true })
      .subscribe(
        onError: {
          XCTFail($0.localizedDescription)
          exp.fulfill()
        },
        onDisposed: {
          XCTAssertTrue(done, "Should reach expected end of tested observable")
          exp.fulfill()
        }
      )
    waitForExpectations(timeout: timeout)
  }

  func expect(
    timeout: TimeInterval = 1,
    _ completable: (_ done: @escaping () -> ()) -> Completable) {
    let exp = expectation(description: "Waiting…")
    var done: Bool = false
    _ = completable({ done = true })
      .subscribe(
        onCompleted: {
          XCTAssertTrue(done, "Should reach expected end of tested observable")
          exp.fulfill()
        },
        onError: {
          XCTFail($0.localizedDescription)
          exp.fulfill()
        }
      )

    waitForExpectations(timeout: timeout)
  }
}
