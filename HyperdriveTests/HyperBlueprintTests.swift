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
    hyperdrive = HyperBlueprint(blueprint: blueprint, baseURL: NSURL(string: "https://polls.apiblueprint.org/")!)
  }

  // MARK: Root Resource

  func testRootResourceIncludesGETAction() {
    let representor = hyperdrive.rootRepresentor()
    XCTAssertEqual(representor.transitions["questions"]!.uri, "https://polls.apiblueprint.org/questions")
  }

  // MARK:

  func testResourceForResponse() {
    let URL = NSURL(string: "https://polls.apiblueprint.org/questions/5")!
    let response = NSHTTPURLResponse(URL: URL, statusCode: 200, HTTPVersion: nil, headerFields: nil)!
    let resource = hyperdrive.resourceForResponse(response)!

    XCTAssertEqual(resource.name, "Detail")
    XCTAssertEqual(resource.uriTemplate, "/questions/{id}")
  }

  // MARK: Constructing a response

  func testConstructingResponseShowsJSONAttributes() {
    let attributes = ["question": "Favourite Programming Language?"]
    let URL = NSURL(string: "https://polls.apiblueprint.org/questions/5")!
    let request = NSURLRequest(URL: URL)
    let response = NSHTTPURLResponse(URL: URL, statusCode: 200, HTTPVersion: nil, headerFields: ["Content-Type": "application/json"])!
    let body = NSJSONSerialization.dataWithJSONObject(attributes, options: NSJSONWritingOptions(0), error: nil)!

    let representor = hyperdrive.constructResponse(request, response: response, body: body)!

    XCTAssertEqual(representor.attributes as NSDictionary, attributes)
  }

  func testConstructingResponseShowsTransitions() {
    let URL = NSURL(string: "https://polls.apiblueprint.org/questions")!
    let request = NSURLRequest(URL: URL)
    let response = NSHTTPURLResponse(URL: URL, statusCode: 200, HTTPVersion: nil, headerFields: ["Content-Type": "application/json"])!
    let body = NSJSONSerialization.dataWithJSONObject([], options: NSJSONWritingOptions(0), error: nil)!

    let representor = hyperdrive.constructResponse(request, response: response, body: body)!
    let createTransition = representor.transitions["create"]

    XCTAssertTrue(createTransition != nil)
    XCTAssertEqual(createTransition!.uri, "https://polls.apiblueprint.org/questions")
    XCTAssertEqual(createTransition!.method, "POST")
  }

  func testConstructingResponseHidesTransitionsNotIncludedInAllowHeader() {
    let URL = NSURL(string: "https://polls.apiblueprint.org/questions")!
    let request = NSURLRequest(URL: URL)
    let headers = [
      "Allow": "HEAD, GET",
      "Content-Type": "application/json",
    ]
    let response = NSHTTPURLResponse(URL: URL, statusCode: 200, HTTPVersion: nil, headerFields: headers)!
    let body = NSJSONSerialization.dataWithJSONObject([], options: NSJSONWritingOptions(0), error: nil)!

    let representor = hyperdrive.constructResponse(request, response: response, body: body)!
    let createTransition = representor.transitions["create"]

    XCTAssertTrue(createTransition == nil)
  }

  func testConstructingResponseShowsWebLinkingHeaders() {
    let attributes = ["question": "Favourite Programming Language?"]
    let URL = NSURL(string: "https://polls.apiblueprint.org/questions/5")!
    let request = NSURLRequest(URL: URL)
    let headers = [
      "Content-Type": "application/json",
      "Link": "<https://polls.apiblueprint.org/questions/6>; rel=\"next\", <https://polls.apiblueprint.org/questions/4>; rel=\"prev\"; type=\"foo\"",
    ]
    let response = NSHTTPURLResponse(URL: URL, statusCode: 200, HTTPVersion: nil, headerFields: headers)!
    let body = NSJSONSerialization.dataWithJSONObject(attributes, options: NSJSONWritingOptions(0), error: nil)!

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
