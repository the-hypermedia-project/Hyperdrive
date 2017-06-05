//
//  HyperBlueprintTests.swift
//  Hyperdrive
//
//  Created by Kyle Fuller on 12/04/2015.
//  Copyright (c) 2015 Apiary. All rights reserved.
//

import Foundation
import XCTest
import Representor
import Hyperdrive


class HyperBlueprintTests: XCTestCase {
  var blueprint:Blueprint!
  var hyperdrive:HyperBlueprint!

  override func setUp() {
    let listAction = Action(name: "List", description: nil, method: "GET", parameters: [], uriTemplate: nil, relation: "questions", examples: nil)
    let createAction = Action(name: "Create", description: nil, method: "POST", parameters: [], uriTemplate: nil, relation: "create", examples: nil)
    let listResource = Resource(name: "Questions", description: nil, uriTemplate: "/questions", parameters: [], actions: [createAction, listAction])

    let viewAction = Action(name: "View", description: nil, method: "GET", parameters: [], uriTemplate: nil, relation: "question", examples: nil)
    let viewResource = Resource(name: "Detail", description: nil, uriTemplate: "/questions/{id}", parameters: [], actions: [viewAction])

    let resourceGroup = ResourceGroup(name: "Questions", description: nil, resources: [listResource, viewResource])
    blueprint = Blueprint(name: "Polls", description: nil, resourceGroups: [resourceGroup])
    hyperdrive = HyperBlueprint(blueprint: blueprint, baseURL: URL(string: "https://polls.apiblueprint.org/")!)
  }

  // MARK: Root Resource

  func testRootResourceIncludesGETAction() {
    let representor = hyperdrive.rootRepresentor()
    XCTAssertEqual(representor.transitions["questions"]?.uri, "https://polls.apiblueprint.org/questions")
  }

  // MARK:

  func testResourceForResponse() {
    let URL = Foundation.URL(string: "https://polls.apiblueprint.org/questions/5")!
    let response = HTTPURLResponse(url: URL, statusCode: 200, httpVersion: nil, headerFields: nil)!
    let resource = hyperdrive.resourceForResponse(response)!

    XCTAssertEqual(resource.name, "Detail")
    XCTAssertEqual(resource.uriTemplate, "/questions/{id}")
  }

  // MARK: Constructing a response

  func testConstructingResponseShowsJSONAttributes() {
    let attributes = ["question": "Favourite Programming Language?"]
    let URL = Foundation.URL(string: "https://polls.apiblueprint.org/questions/5")!
    let request = URLRequest(url: URL)
    let response = HTTPURLResponse(url: URL, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    let body = try! JSONSerialization.data(withJSONObject: attributes, options: JSONSerialization.WritingOptions(rawValue: 0))

    let representor = hyperdrive.constructResponse(request, response: response, body: body)!

    XCTAssertEqual(representor.attributes as NSDictionary, attributes)
  }

  func testConstructingResponseShowsTransitions() {
    let URL = Foundation.URL(string: "https://polls.apiblueprint.org/questions")!
    let request = URLRequest(url: URL)
    let response = HTTPURLResponse(url: URL, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    let body = try! JSONSerialization.data(withJSONObject: [], options: JSONSerialization.WritingOptions(rawValue: 0))

    let representor = hyperdrive.constructResponse(request, response: response, body: body)!
    let createTransition = representor.transitions["create"]

    XCTAssertTrue(createTransition != nil)
    XCTAssertEqual(createTransition!.uri, "https://polls.apiblueprint.org/questions")
    XCTAssertEqual(createTransition!.method, "POST")
  }

  func testConstructingResponseIncludesSelfTransition() {
    let URL = Foundation.URL(string: "https://polls.apiblueprint.org/questions")!
    let request = URLRequest(url: URL)
    let response = HTTPURLResponse(url: URL, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    let body = try! JSONSerialization.data(withJSONObject: [], options: JSONSerialization.WritingOptions(rawValue: 0))

    let representor = hyperdrive.constructResponse(request, response: response, body: body)!
    let transition = representor.transitions["self"]

    XCTAssertNotNil(transition)
    XCTAssertEqual(transition?.uri, "https://polls.apiblueprint.org/questions")
    XCTAssertEqual(transition?.method, "GET")
  }

  func testConstructingResponseHidesTransitionsNotIncludedInAllowHeader() {
    let URL = Foundation.URL(string: "https://polls.apiblueprint.org/questions")!
    let request = URLRequest(url: URL)
    let headers = [
      "Allow": "HEAD, GET",
      "Content-Type": "application/json",
    ]
    let response = HTTPURLResponse(url: URL, statusCode: 200, httpVersion: nil, headerFields: headers)!
    let body = try! JSONSerialization.data(withJSONObject: [], options: JSONSerialization.WritingOptions(rawValue: 0))

    let representor = hyperdrive.constructResponse(request, response: response, body: body)!
    let createTransition = representor.transitions["create"]

    XCTAssertNil(createTransition)
  }

  func testConstructingResponseShowsWebLinkingHeaders() {
    let attributes = ["question": "Favourite Programming Language?"]
    let URL = Foundation.URL(string: "https://polls.apiblueprint.org/questions/5")!
    let request = URLRequest(url: URL)
    let headers = [
      "Content-Type": "application/json",
      "Link": "<https://polls.apiblueprint.org/questions/6>; rel=\"next\", <https://polls.apiblueprint.org/questions/4>; rel=\"prev\"; type=\"foo\"",
    ]
    let response = HTTPURLResponse(url: URL, statusCode: 200, httpVersion: nil, headerFields: headers)!
    let body = try! JSONSerialization.data(withJSONObject: attributes, options: JSONSerialization.WritingOptions(rawValue: 0))

    let representor = hyperdrive.constructResponse(request, response: response, body: body)!
    let nextTransition = representor.transitions["next"]!
    let prevTransition = representor.transitions["prev"]!

    XCTAssertEqual(prevTransition.uri, "https://polls.apiblueprint.org/questions/4")
    XCTAssertEqual(prevTransition.method, "GET")
    XCTAssertEqual(prevTransition.suggestedContentTypes, ["foo"])
    XCTAssertEqual(nextTransition.uri, "https://polls.apiblueprint.org/questions/6")
    XCTAssertEqual(nextTransition.method, "GET")
    XCTAssertEqual(nextTransition.suggestedContentTypes, [])
  }
}
