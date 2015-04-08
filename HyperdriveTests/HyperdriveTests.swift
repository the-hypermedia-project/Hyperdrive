//
//  HyperdriveTests.swift
//  HyperdriveTests
//
//  Created by Kyle Fuller on 08/04/2015.
//  Copyright (c) 2015 Apiary. All rights reserved.
//

import Foundation
import XCTest
import Representor
import Hyperdrive


class HyperdriveTests: XCTestCase {
  var hyperdrive:Hyperdrive!

  override func setUp() {
    hyperdrive = Hyperdrive()
  }

  // MARK: Constructing a request

  func testConstructingRequestReturnsWithAcceptHeaderRequest() {
    let request = hyperdrive.constructRequest("https://hyperdrive-tests.fuller.li/")
    let header = request.allHTTPHeaderFields!["Accept"] as String

    XCTAssertEqual(header, "application/vnd.siren+json; application/hal+json")
  }

  func xtestConstructingRequestExpandsURITemplate() {
    let request = hyperdrive.constructRequest("https://hyperdrive-tests.fuller.li/{username}", parameters:["username": "kyle"])

    XCTAssertEqual(request.URL!.absoluteString!, "https://hyperdrive-tests.fuller.li/kyle")
  }

  // MARK: Constructing a request

  func testConstructingRequestFromTransitionReturnsWithAcceptHeaderRequest() {
    let transition = HTTPTransition(uri: "https://hyperdrive-tests.fuller.li/users") { builder in

    }
    let request = hyperdrive.constructRequest(transition)
    let header = request.allHTTPHeaderFields!["Accept"] as String

    XCTAssertEqual(header, "application/vnd.siren+json; application/hal+json")
  }

  func xtestConstructingRequestFromTransitionExpandsURITemplate() {
    let transition = HTTPTransition(uri: "https://hyperdrive-tests.fuller.li/users") { builder in

    }
    let request = hyperdrive.constructRequest(transition, parameters:["username": "kyle"])

    XCTAssertEqual(request.URL!.absoluteString!, "https://hyperdrive-tests.fuller.li/kyle")
  }

  func testConstructingRequestFromTransitionWithMethod() {
    let transition = HTTPTransition(uri: "https://hyperdrive-tests.fuller.li/kyle") { builder in
      builder.method = "PATCH"
    }
    let request = hyperdrive.constructRequest(transition)

    XCTAssertEqual(request.HTTPMethod, "PATCH")
  }

  func testConstructingRequestFromTransitionWithJSONAttributes() {
    let transition = HTTPTransition(uri: "https://hyperdrive-tests.fuller.li/users") { builder in
      builder.suggestedContentTypes = ["application/json"]
    }
    let request = hyperdrive.constructRequest(transition, attributes:["username": "kyle"])

    let body = request.HTTPBody!
    let decodedBody = NSJSONSerialization.JSONObjectWithData(body, options: NSJSONReadingOptions(0), error: nil) as NSDictionary
    XCTAssertEqual(decodedBody, ["username": "kyle"])
  }

  func xtestConstructingRequestFromTransitionWithFormEncodedAttributes() {

  }

  // MARK: Constructing a response

  func testConstructingResponseFromSirenBody() {
    let URL = NSURL(string: "https://hyperdrive-tests.fuller.li/users")!
    let response = NSHTTPURLResponse(URL: URL, statusCode: 200, HTTPVersion: "1.1", headerFields: ["Content-Type": "application/vnd.siren+json"])!
    let attributes = [
      "properties": [
        "test": "hello world"
      ]
    ]
    let body = NSJSONSerialization.dataWithJSONObject(attributes, options: NSJSONWritingOptions(0), error: nil)!

    let representor = hyperdrive.constructResponse(response, body:body)!
    XCTAssertEqual(representor.attributes["test"] as String, "hello world")
  }
}

