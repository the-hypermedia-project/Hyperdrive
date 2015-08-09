//
//  HyperdriveGitHubTest.swift
//  Hyperdrive
//
//  Created by Z on 8/8/15.
//  Copyright (c) 2015 Apiary. All rights reserved.
//

import Foundation
import XCTest
import Representor
import Hyperdrive

class GitHubAdapterTests: XCTestCase {

  func testGitHubRoot() {
    let hyperdrive = Hyperdrive(preferredContentTypes: ["application/vnd.github.v3+json"])
    
    let expectation = expectationWithDescription("...")
    
    hyperdrive.enter("https://api.github.com/") { result in
      switch result {
      case .Success(let representor):
        println("The API has offered us the following transitions: \(representor.transitions)")
        
      case .Failure(let error):
        println("Unfortunately there was an error: \(error)")
      }
      
      expectation.fulfill()
    }
    
    waitForExpectationsWithTimeout(10) { error in
      if let error = error {
        print("Error: \(error.localizedDescription)")
      }
    }
  }
  
}