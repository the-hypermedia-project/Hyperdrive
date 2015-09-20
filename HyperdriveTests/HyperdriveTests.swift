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

  // MARK: Constructing a request from a URI

  func testConstructingRequestReturnsWithAcceptHeaderRequest() {
    let result = hyperdrive.constructRequest("https://hyperdrive-tests.fuller.li/")

    switch result {
    case .Success(let request):
      let header = request.allHTTPHeaderFields!["Accept"]
      XCTAssertEqual(header, "application/vnd.siren+json, application/hal+json")
    case .Failure(let error):
      XCTFail(error.description)
    }
  }

  func testConstructingRequestReturnsWithAcceptHeaderRequestUsingSuppliedContentTypes() {
    hyperdrive = Hyperdrive(preferredContentTypes: ["application/hal+json"])
    let result = hyperdrive.constructRequest("https://hyperdrive-tests.fuller.li/")

    switch result {
    case .Success(let request):
      let header = request.allHTTPHeaderFields!["Accept"]
      XCTAssertEqual(header, "application/hal+json")
    case .Failure(let error):
      XCTFail(error.description)
    }
  }

  func testConstructingRequestExpandsURITemplate() {
    let result = hyperdrive.constructRequest("https://hyperdrive-tests.fuller.li/{username}", parameters:["username": "kyle"])

    switch result {
    case .Success(let request):
      XCTAssertEqual(request.URL?.absoluteString, "https://hyperdrive-tests.fuller.li/kyle")
    case .Failure(let error):
      XCTFail(error.description)
    }
  }

  // MARK: Constructing a request from a transition

  func testConstructingRequestFromTransitionReturnsWithAcceptHeaderRequest() {
    let transition = HTTPTransition(uri: "https://hyperdrive-tests.fuller.li/users") { builder in }
    let result = hyperdrive.constructRequest(transition)

    switch result {
    case .Success(let request):
      let header = request.allHTTPHeaderFields!["Accept"]
      XCTAssertEqual(header, "application/vnd.siren+json, application/hal+json")
    case .Failure(let error):
      XCTFail(error.description)
    }
  }

  func testConstructingRequestFromTransitionExpandsURITemplate() {
    let transition = HTTPTransition(uri: "https://hyperdrive-tests.fuller.li/{username}") { builder in }
    let result = hyperdrive.constructRequest(transition, parameters:["username": "kyle"])

    switch result {
    case .Success(let request):
      XCTAssertEqual(request.URL?.absoluteString, "https://hyperdrive-tests.fuller.li/kyle")
    case .Failure(let error):
      XCTFail(error.description)
    }
  }

  func testConstructingRequestFromTransitionWithMethod() {
    let transition = HTTPTransition(uri: "https://hyperdrive-tests.fuller.li/kyle") { builder in
      builder.method = "PATCH"
    }
    let result = hyperdrive.constructRequest(transition)

    switch result {
    case .Success(let request):
      XCTAssertEqual(request.HTTPMethod, "PATCH")
    case .Failure(let error):
      XCTFail(error.description)
    }
  }

  func testConstructingRequestFromTransitionWithJSONAttributes() {
    let transition = HTTPTransition(uri: "https://hyperdrive-tests.fuller.li/users") { builder in
      builder.suggestedContentTypes = ["application/json"]
    }
    let result = hyperdrive.constructRequest(transition, attributes:["username": "kyle"])

    switch result {
    case .Success(let request):
      let body = request.HTTPBody!
      let decodedBody = try? NSJSONSerialization.JSONObjectWithData(body, options: NSJSONReadingOptions(rawValue: 0)) as! NSDictionary
      XCTAssertEqual(decodedBody, ["username": "kyle"])
    case .Failure(let error):
      XCTFail(error.description)
    }
  }

  func xtestConstructingRequestFromTransitionWithFormEncodedAttributes() {

  }

  // MARK: Constructing a response

  func testConstructingResponseFromSirenBody() {
    let URL = NSURL(string: "https://hyperdrive-tests.fuller.li/users")!
    let request = NSURLRequest(URL: URL)
    let response = NSHTTPURLResponse(URL: URL, statusCode: 200, HTTPVersion: "1.1", headerFields: ["Content-Type": "application/vnd.siren+json"])!
    let attributes = [
      "properties": [
        "test": "hello world"
      ]
    ]
    let body = try! NSJSONSerialization.dataWithJSONObject(attributes, options: NSJSONWritingOptions(rawValue: 0))

    let representor = hyperdrive.constructResponse(request, response: response, body:body)!
    XCTAssertEqual(representor.attributes["test"] as? String, "hello world")
  }
}

