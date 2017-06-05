//
//  HyperBlueprint.swift
//  Hyperdrive
//
//  Created by Kyle Fuller on 12/04/2015.
//  Copyright (c) 2015 Apiary. All rights reserved.
//

import Foundation
import Representor
import URITemplate
import WebLinking
import Result


func absoluteURITemplate(_ baseURL:String, uriTemplate:String) -> String {
  switch (baseURL.hasSuffix("/"), uriTemplate.hasPrefix("/")) {
  case (true, true):
    return baseURL.substring(to: baseURL.characters.index(before: baseURL.endIndex)) + uriTemplate
  case (true, false):
    fallthrough
  case (false, true):
    return baseURL + uriTemplate
  case (false, false):
    return baseURL + "/" + uriTemplate
  }
}

private typealias Element = [String: AnyObject]

private func uriForAction(_ resource:Resource, action:Action) -> String {
  var uriTemplate = resource.uriTemplate

  // Empty action uriTemplate == no template
  if let uri = action.uriTemplate {
    if !uri.isEmpty {
      uriTemplate = uri
    }
  }

  return uriTemplate
}

private func decodeJSON(_ data:NSData) -> Result<AnyObject, NSError> {
  return Result(try JSONSerialization.JSONObjectWithData(data as Data, options: JSONSerialization.ReadingOptions(rawValue: 0)))
}

private func decodeJSON<T>(_ data:Data) -> Result<T, NSError> {
  return Result(try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions(rawValue: 0))).flatMap {
    if let value = $0 as? T {
      return .success(value)
    }

    let invaidJSONError = NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Returned JSON object was not of expected type."])
    return .failure(invaidJSONError)
  }
}

extension Resource {
  var dataStructure:[String:AnyObject]? {
    return content.filter {
      element in (element["element"] as? String) == "dataStructure"
    }.first
  }

  func actionForMethod(_ method:String) -> Action? {
    return actions.filter { action in
      return action.method == method
    }.first
  }
}


public typealias HyperBlueprintResultSuccess = (Hyperdrive, Representor<HTTPTransition>)
public typealias HyperBlueprintResult = Result<HyperBlueprintResultSuccess, NSError>

/// A subclass of Hyperdrive which supports requests from an API Blueprint
open class HyperBlueprint : Hyperdrive {
  let baseURL:URL
  let blueprint:Blueprint

  // MARK: Entering an API

  /// Enter an API from a blueprint hosted on Apiary using the given domain
  open class func enter(apiary: String, baseURL:URL? = nil, completion: @escaping ((HyperBlueprintResult) -> Void)) {
    let url = "https://jsapi.apiary.io/apis/\(apiary).apib"
    self.enter(blueprintURL: url, baseURL: baseURL, completion: completion)
  }

  /// Enter an API from a blueprint URI
  open class func enter(blueprintURL: String, baseURL:URL? = nil, completion: @escaping ((HyperBlueprintResult) -> Void)) {
    if let URL = URL(string: blueprintURL) {
      let request = NSMutableURLRequest(url: URL)
      request.setValue("text/vnd.apiblueprint+markdown; version=1A", forHTTPHeaderField: "Accept")
      let session = URLSession(configuration: URLSessionConfiguration.default)
      session.dataTask(with: request, completionHandler: { (body, response, error) in
        if let error = error {
          DispatchQueue.main.async {
            completion(.Failure(error))
          }
        } else if let body = body {
            self.enter(blueprint: body, baseURL: baseURL, completion: completion)
        } else {
          let error = NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Response has no body."])
          DispatchQueue.main.async {
            completion(.Failure(error))
          }
        }
        }) .resume()
    } else {
      let error = NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URI for blueprint \(blueprintURL)"])
      completion(.failure(error))
    }
  }

  class func enter(blueprint: Data, baseURL:URL? = nil, completion: @escaping ((HyperBlueprintResult) -> Void)) {
    let parserURL = URL(string: "https://api.apiblueprint.org/parser")!
    let request = NSMutableURLRequest(url: parserURL)
    request.httpMethod = "POST"
    request.httpBody = blueprint
    request.setValue("text/vnd.apiblueprint+markdown; version=1A", forHTTPHeaderField: "Content-Type")
    request.setValue("application/vnd.apiblueprint.parseresult+json; version=2.2", forHTTPHeaderField: "Accept")

    let session = URLSession(configuration: URLSessionConfiguration.default)
    session.dataTask(with: request, completionHandler: { (body, response, error) in
      if let error = error {
        DispatchQueue.main.async {
          completion(.Failure(error))
        }
      } else if let body = body {
        switch decodeJSON(body) {
        case .Success(let parseResult):
          if let ast = parseResult["ast"] as? [String:AnyObject] {
            let blueprint = Blueprint(ast: ast)
            self.enter(blueprint, baseURL: baseURL, completion: completion)
          } else {
            DispatchQueue.main.async {
              completion(.Failure(error ?? NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Server returned invalid API Blueprint AST."])))
            }
          }
        case .Failure(let error):
          DispatchQueue.main.async {
            completion(.Failure(error ?? NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Server returned invalid API Blueprint AST."])))
          }
        }
      } else {
        let error = NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Response has no body."])
        DispatchQueue.main.async {
          completion(.Failure(error))
        }
      }
    }) .resume()
  }

  /// Enter an API with a blueprint
  fileprivate class func enter(_ blueprint:Blueprint, baseURL:URL? = nil, completion: @escaping ((HyperBlueprintResult) -> Void)) {
    if let baseURL = baseURL {
      let hyperdrive = self.init(blueprint: blueprint, baseURL: baseURL)
      let representor = hyperdrive.rootRepresentor()
      DispatchQueue.main.async {
        completion(.success((hyperdrive, representor)))
      }
    } else {
      let host = (blueprint.metadata).filter { metadata in metadata.name == "HOST" }.first
      if let host = host {
        if let baseURL = URL(string: host.value) {
          let hyperdrive = self.init(blueprint: blueprint, baseURL: baseURL)
          let representor = hyperdrive.rootRepresentor()
          DispatchQueue.main.async {
            completion(.success((hyperdrive, representor)))
          }
          return
        }
      }

      let error = NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [
        NSLocalizedDescriptionKey: "Entering an API Blueprint hyperdrive without a base URL.",
      ])
      DispatchQueue.main.async {
        completion(.failure(error))
      }
    }
  }

  public required init(blueprint:Blueprint, baseURL:URL) {
    self.blueprint = blueprint
    self.baseURL = baseURL
  }

  fileprivate var resources:[Resource] {
    let resources = blueprint.resourceGroups.map { $0.resources }
    return resources.reduce([], +)
  }

  /// Returns a representor representing all available links
  open func rootRepresentor() -> Representor<HTTPTransition> {
    return Representor { builder in
      for resource in self.resources {
        let actions = resource.actions.filter { action in
          let hasAction = (action.relation != nil) && !action.relation!.isEmpty
          return hasAction && action.method == "GET"
        }

        for action in actions {
          let relativeURI = uriForAction(resource, action: action)
          let absoluteURI = absoluteURITemplate(self.baseURL.absoluteString, uriTemplate: relativeURI)
          let transition = HTTPTransition.from(resource: resource, action: action, URL: absoluteURI)
          builder.addTransition(action.relation!, transition)
        }
      }
    }
  }

  open override func constructRequest(_ uri: String, parameters: [String : AnyObject]?) -> RequestResult {
    return super.constructRequest(uri, parameters: parameters).map { request in
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      return request
    }
  }

  open override func constructResponse(_ request: NSURLRequest, response: HTTPURLResponse, body: NSData?) -> Representor<HTTPTransition>? {
    if let resource = resourceForResponse(response) {
      return Representor { builder in
        var uriTemplate = resource.actionForMethod(request.httpMethod ?? "GET")?.uriTemplate
        if (uriTemplate == nil) || !uriTemplate!.isEmpty {
          uriTemplate = resource.uriTemplate
        }

        let template = URITemplate(template: absoluteURITemplate(self.baseURL.absoluteString, uriTemplate: uriTemplate!))
        let parameters = template.extract(response.url!.absoluteString)

        self.addResponse(resource, parameters: parameters as! [String : AnyObject], request: ((((request as URLRequest) as URLRequest) as URLRequest) as URLRequest) as URLRequest, response: response, body: body, builder: builder)

        if response.url != nil {
          var allowedMethods:[String]? = nil

          if let allow = response.allHeaderFields["Allow"] as? String {
            allowedMethods = allow.componentsSeparatedByString(",").map {
              $0.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
            }
          }

          self.addTransitions(resource, parameters: parameters as! [String : AnyObject], builder: builder, allowedMethods: allowedMethods)
        }

        for link in response.links {
          if let relation = link.relationType {
            builder.addTransition(relation, uri: link.uri) { builder in
              builder.method = "GET"

              if let type = link.type {
                builder.suggestedContentTypes = [type]
              }
            }
          }
        }

        if builder.transitions["self"] == nil {
          if let URL = response.url?.absoluteString {
            builder.addTransition("self", uri: URL) { builder in
              builder.method = "GET"
            }
          }
        }
      }
    }

    return nil
  }

  open func resourceForResponse(_ response: HTTPURLResponse) -> Resource? {
    if let URL = response.url?.absoluteString {
      return resources.filter { resource in
        let template = URITemplate(template: absoluteURITemplate(baseURL.absoluteString, uriTemplate: resource.uriTemplate))
        let extract = template.extract(URL)
        return extract != nil
      }.first
    }

    return nil
  }

  open func actionForResource(_ resource:Resource, method:String) -> Action? {
    return resource.actions.filter { action in action.method == method }.first
  }

  func resource(named:String) -> Resource? {
    return resources.filter { resource in resource.name == named }.first
  }

  // MARK: -

  func addResponse(_ resource:Resource, parameters:[String:AnyObject]?, request:URLRequest, response:HTTPURLResponse, body:Data?, builder:RepresentorBuilder<HTTPTransition>) {
    if let body = body {
      if response.mimeType == "application/json" {
        if let object = decodeJSON(body).value {
          addObjectResponse(resource, parameters: parameters, request: request, response: response, object: object, builder: builder)
        }
      }
    }
  }

  /// Returns any required URI Parameters for the given resource and attributes to determine the URI for the resource
  open func parameters(resource:Resource, attributes:[String:AnyObject]) -> [String:AnyObject]? {
    // By default, check if the attributes includes a URL we can use to extract the parameters
    if let url = attributes["url"] as? String {
      return resources.flatMap {
        URITemplate(template: $0.uriTemplate).extract(url)
      }.first as! [String : AnyObject]
    }

    return nil
  }

  func addObjectResponse(_ resource:Resource, parameters:[String:AnyObject]?, request:URLRequest, response:HTTPURLResponse, object:AnyObject, builder:RepresentorBuilder<HTTPTransition>) {
    if let attributes = object as? [String:AnyObject] {
      addAttributes([:], resource:resource, request: request, response: response, attributes: attributes, builder: builder)
    } else if let objects = object as? [[String:AnyObject]] {  // An array of other resources
      let resourceName = resource.dataStructure
        .flatMap(selectFirstContent)
        .flatMap(selectFirstContent)
        .flatMap { $0["element"] as? String }

      if let resourceName = resourceName, let embeddedResource = self.resource(named: resourceName) {
        let relation = resource.actionForMethod(request.HTTPMethod ?? "GET")?.relation ?? "objects"
        for object in objects {
          builder.addRepresentor(relation) { builder in
            self.addObjectResponse(embeddedResource, parameters: parameters, request: request, response: response, object: object, builder: builder)
          }
        }
      }
    }
  }

  func addObjectResponseOfResource(_ relation:String, resource:Resource, request:URLRequest, response:HTTPURLResponse, object:AnyObject, builder:RepresentorBuilder<HTTPTransition>) {
    if let attributes = object as? [String:AnyObject] {
      builder.addRepresentor(relation) { builder in
        self.addAttributes([:], resource: resource, request: request, response: response, attributes: attributes, builder: builder)
      }
    } else if let objects = object as? [[String:AnyObject]] {
      for object in objects {
        addObjectResponseOfResource(relation, resource: resource, request: request, response: response, object: object as AnyObject, builder: builder)
      }
    }
  }

  func addAttributes(_ parameters:[String:AnyObject]?, resource:Resource, request:URLRequest, response:HTTPURLResponse, attributes:[String:AnyObject], builder:RepresentorBuilder<HTTPTransition>) {
    let action = actionForResource(resource, method: request.HTTPMethod!)

    // Find's the Resource structure for an attribute in the current resource response
    func resourceForAttribute(_ key: String) -> Resource? {
      // TODO: Rewrite this to use proper refract structures
        // Find the element value for the MSON object key
       return resource.dataStructure
          .flatMap(selectFirstContent)
          .flatMap(selectElementArrayContent)
          .flatMap(selectValueWithKey(key))  // finds the member's value for the member matching key
          .flatMap(selectFirstContent)
          .flatMap(selectElementValue)
          .flatMap { self.resource(named: $0) }
    }
      

    for (key, value) in attributes {
      if let resource = resourceForAttribute(key) {
        self.addObjectResponseOfResource(key, resource:resource, request: request, response: response, object: value, builder: builder)
      } else {
        builder.addAttribute(key, value: value)
      }
    }

    let params = (parameters ?? [:]) + (self.parameters(resource:resource, attributes:attributes) ?? [:])
    addTransitions(resource, parameters:params, builder: builder)
  }

  func addTransitions(_ resource:Resource, parameters:[String:AnyObject]?, builder:RepresentorBuilder<HTTPTransition>, allowedMethods:[String]? = nil) {
    let resourceURI = absoluteURITemplate(self.baseURL.absoluteString, uriTemplate: URITemplate(template: resource.uriTemplate).expand(parameters ?? [:]))

    for action in resource.actions {
      var actionURI = resourceURI

      if action.uriTemplate != nil && !action.uriTemplate!.isEmpty {
        actionURI = absoluteURITemplate(self.baseURL.absoluteString, uriTemplate: URITemplate(template: action.uriTemplate!).expand(parameters ?? [:]))
      }

      if let relation = action.relation {
        let transition = HTTPTransition.from(resource:resource, action:action, URL:actionURI)
        if let allowedMethods = allowedMethods {
          if !allowedMethods.contains(transition.method) {
            continue
          }
        }
        builder.addTransition(relation, transition)
      }
    }
  }
}

// Merge two dictionaries together
func +<K,V>(lhs:Dictionary<K,V>, rhs:Dictionary<K,V>) -> Dictionary<K,V> {
  var dictionary = [K:V]()

  for (key, value) in rhs {
    dictionary[key] = value
  }

  for (key, value) in lhs {
    dictionary[key] = value
  }

  return dictionary
}


// Refract Traversal
private func selectContent(_ element: Element) -> AnyObject? {
  return element["content"]
}

private func selectElementArrayContent(_ element: Element) -> [Element]? {
  return selectContent(element) as? [Element]
}

private func selectFirstContent(_ element: Element) -> Element? {
  return selectElementArrayContent(element)?.first
}

/// Traverses a collection of member elements in search for the value for a key
private func selectValueWithKey<T: Equatable>(_ key: T) -> ([Element]) -> Element? {
  return { element in
    return element.flatMap(selectContent)
      .filter { element in
        if let elementKey = element["key"] as? [String: AnyObject], let keyContent = elementKey["content"] as? T {
          return keyContent == key
        }
        return false
      }
      .flatMap { $0["value"] as? Element }
      .first
  }
}

private func selectElementValue(_ element: Element) -> String? {
  return element["element"] as? String
}
