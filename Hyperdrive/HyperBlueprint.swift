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


func absoluteURITemplate(baseURL:String, uriTemplate:String) -> String {
  switch (baseURL.hasSuffix("/"), uriTemplate.hasPrefix("/")) {
  case (true, true):
    return baseURL.substringToIndex(baseURL.endIndex.predecessor()) + uriTemplate
  case (true, false):
    fallthrough
  case (false, true):
    return baseURL + uriTemplate
  case (false, false):
    return baseURL + "/" + uriTemplate
  }
}

private func uriForAction(resource:Resource, action:Action) -> String {
  var uriTemplate = resource.uriTemplate

  // Empty action uriTemplate == no template
  if let uri = action.uriTemplate {
    if !uri.isEmpty {
      uriTemplate = uri
    }
  }

  return uriTemplate
}

private func decodeJSON(data:NSData) -> Result<AnyObject, NSError> {
  return Result(try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions(rawValue: 0)))
}

private func decodeJSON<T>(data:NSData) -> Result<T, NSError> {
  return Result(try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions(rawValue: 0))).flatMap {
    if let value = $0 as? T {
      return .Success(value)
    }

    let invaidJSONError = NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Returned JSON object was not of expected type."])
    return .Failure(invaidJSONError)
  }
}

extension Resource {
  var dataStructure:[String:AnyObject]? {
    return content.filter {
      element in (element["element"] as? String) == "dataStructure"
    }.first
  }

  var typeDefinition:[String:AnyObject]? {
    return dataStructure?["typeDefinition"] as? [String:AnyObject]
  }

  var typeSpecification:[String:AnyObject]? {
    return typeDefinition?["typeSpecification"] as? [String:AnyObject]
  }

  func actionForMethod(method:String) -> Action? {
    return actions.filter { action in
      return action.method == method
    }.first
  }
}


public typealias HyperBlueprintResultSuccess = (Hyperdrive, Representor<HTTPTransition>)
public typealias HyperBlueprintResult = Result<HyperBlueprintResultSuccess, NSError>

/// A subclass of Hyperdrive which supports requests from an API Blueprint
public class HyperBlueprint : Hyperdrive {
  let baseURL:NSURL
  let blueprint:Blueprint

  // MARK: Entering an API

  /// Enter an API from a blueprint hosted on Apiary using the given domain
  public class func enter(apiary  apiary: String, baseURL:NSURL? = nil, completion: (HyperBlueprintResult -> Void)) {
    let url = "https://jsapi.apiary.io/apis/\(apiary).apib"
    self.enter(blueprintURL: url, baseURL: baseURL, completion: completion)
  }

  /// Enter an API from a blueprint URI
  public class func enter(blueprintURL  blueprintURL: String, baseURL:NSURL? = nil, completion: (HyperBlueprintResult -> Void)) {
    if let URL = NSURL(string: blueprintURL) {
      let request = NSMutableURLRequest(URL: URL)
      request.setValue("text/vnd.apiblueprint+markdown; version=1A", forHTTPHeaderField: "Accept")
      let session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration())
      session.dataTaskWithRequest(request) { (body, response, error) in
        if let error = error {
          dispatch_async(dispatch_get_main_queue()) {
            completion(.Failure(error))
          }
        } else if let body = body {
            self.enter(blueprint: body, baseURL: baseURL, completion: completion)
        } else {
          let error = NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Response has no body."])
          dispatch_async(dispatch_get_main_queue()) {
            completion(.Failure(error))
          }
        }
        }.resume()
    } else {
      let error = NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URI for blueprint \(blueprintURL)"])
      completion(.Failure(error))
    }
  }

  class func enter(blueprint  blueprint: NSData, baseURL:NSURL? = nil, completion: (HyperBlueprintResult -> Void)) {
    let parserURL = NSURL(string: "http://api.apiblueprint.org/parser")!
    let request = NSMutableURLRequest(URL: parserURL)
    request.HTTPMethod = "POST"
    request.HTTPBody = blueprint
    request.setValue("text/vnd.apiblueprint+markdown; version=1A", forHTTPHeaderField: "Content-Type")
    request.setValue("application/vnd.apiblueprint.parseresult.raw+json; version=1.0", forHTTPHeaderField: "Accept")

    let session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration())
    session.dataTaskWithRequest(request) { (body, response, error) in
      if let error = error {
        dispatch_async(dispatch_get_main_queue()) {
          completion(.Failure(error))
        }
      } else if let body = body {
        switch decodeJSON(body) {
        case .Success(let parseResult):
          if let ast = parseResult["ast"] as? [String:AnyObject] {
            let blueprint = Blueprint(ast: ast)
            self.enter(blueprint, baseURL: baseURL, completion: completion)
          } else {
            dispatch_async(dispatch_get_main_queue()) {
              completion(.Failure(error ?? NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Server returned invalid API Blueprint AST."])))
            }
          }
        case .Failure(let error):
          dispatch_async(dispatch_get_main_queue()) {
            completion(.Failure(error ?? NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Server returned invalid API Blueprint AST."])))
          }
        }
      } else {
        let error = NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Response has no body."])
        dispatch_async(dispatch_get_main_queue()) {
          completion(.Failure(error))
        }
      }
    }.resume()
  }

  /// Enter an API with a blueprint
  private class func enter(blueprint:Blueprint, baseURL:NSURL? = nil, completion: (HyperBlueprintResult -> Void)) {
    if let baseURL = baseURL {
      let hyperdrive = self.init(blueprint: blueprint, baseURL: baseURL)
      let representor = hyperdrive.rootRepresentor()
      dispatch_async(dispatch_get_main_queue()) {
        completion(.Success((hyperdrive, representor)))
      }
    } else {
      let host = (blueprint.metadata).filter { metadata in metadata.name == "HOST" }.first
      if let host = host {
        if let baseURL = NSURL(string: host.value) {
          let hyperdrive = self.init(blueprint: blueprint, baseURL: baseURL)
          let representor = hyperdrive.rootRepresentor()
          dispatch_async(dispatch_get_main_queue()) {
            completion(.Success((hyperdrive, representor)))
          }
          return
        }
      }

      let error = NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [
        NSLocalizedDescriptionKey: "Entering an API Blueprint hyperdrive without a base URL.",
      ])
      dispatch_async(dispatch_get_main_queue()) {
        completion(.Failure(error))
      }
    }
  }

  public required init(blueprint:Blueprint, baseURL:NSURL) {
    self.blueprint = blueprint
    self.baseURL = baseURL
  }

  private var resources:[Resource] {
    let resources = blueprint.resourceGroups.map { $0.resources }
    return resources.reduce([], combine: +)
  }

  /// Returns a representor representing all available links
  public func rootRepresentor() -> Representor<HTTPTransition> {
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

  public override func constructRequest(uri: String, parameters: [String : AnyObject]?) -> RequestResult {
    return super.constructRequest(uri, parameters: parameters).map { request in
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      return request
    }
  }

  public override func constructResponse(request: NSURLRequest, response: NSHTTPURLResponse, body: NSData?) -> Representor<HTTPTransition>? {
    if let resource = resourceForResponse(response) {
      return Representor { builder in
        var uriTemplate = resource.actionForMethod(request.HTTPMethod ?? "GET")?.uriTemplate
        if (uriTemplate == nil) || !uriTemplate!.isEmpty {
          uriTemplate = resource.uriTemplate
        }

        let template = URITemplate(template: absoluteURITemplate(self.baseURL.absoluteString, uriTemplate: uriTemplate!))
        let parameters = template.extract(response.URL!.absoluteString)

        self.addResponse(resource, parameters: parameters, request: request, response: response, body: body, builder: builder)

        if response.URL != nil {
          var allowedMethods:[String]? = nil

          if let allow = response.allHeaderFields["Allow"] as? String {
            allowedMethods = allow.componentsSeparatedByString(",").map {
              $0.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
            }
          }

          self.addTransitions(resource, parameters: parameters, builder: builder, allowedMethods: allowedMethods)
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
          if let URL = response.URL?.absoluteString {
            builder.addTransition("self", uri: URL) { builder in
              builder.method = "GET"
            }
          }
        }
      }
    }

    return nil
  }

  public func resourceForResponse(response: NSHTTPURLResponse) -> Resource? {
    if let URL = response.URL?.absoluteString {
      return resources.filter { resource in
        let template = URITemplate(template: absoluteURITemplate(baseURL.absoluteString, uriTemplate: resource.uriTemplate))
        let extract = template.extract(URL)
        return extract != nil
      }.first
    }

    return nil
  }

  public func actionForResource(resource:Resource, method:String) -> Action? {
    return resource.actions.filter { action in action.method == method }.first
  }

  func resource(named  named:String) -> Resource? {
    return resources.filter { resource in resource.name == named }.first
  }

  // MARK: -

  func addResponse(resource:Resource, parameters:[String:AnyObject]?, request:NSURLRequest, response:NSHTTPURLResponse, body:NSData?, builder:RepresentorBuilder<HTTPTransition>) {
    if let body = body {
      if response.MIMEType == "application/json" {
        if let object = decodeJSON(body).value {
          addObjectResponse(resource, parameters: parameters, request: request, response: response, object: object, builder: builder)
        }
      }
    }
  }

  /// Returns any required URI Parameters for the given resource and attributes to determine the URI for the resource
  public func parameters(resource  resource:Resource, attributes:[String:AnyObject]) -> [String:AnyObject]? {
    // By default, check if the attributes includes a URL we can use to extract the parameters
    if let url = attributes["url"] as? String {
      return resources.flatMap {
        URITemplate(template: $0.uriTemplate).extract(url)
      }.first
    }

    return nil
  }

  func addObjectResponse(resource:Resource, parameters:[String:AnyObject]?, request:NSURLRequest, response:NSHTTPURLResponse, object:AnyObject, builder:RepresentorBuilder<HTTPTransition>) {
    if let attributes = object as? [String:AnyObject] {
      addAttributes([:], resource:resource, request: request, response: response, attributes: attributes, builder: builder)
    } else if let objects = object as? [[String:AnyObject]] {  // An array of other resources
      if let typeSpecification = resource.typeSpecification {
        let name = typeSpecification["name"] as? String ?? ""
        if name == "array" {
          if let nestedTypes = typeSpecification["nestedTypes"] as? [[String:AnyObject]] {
            if let literal = nestedTypes.first?["literal"] as? String {
              let relation = resource.actionForMethod(request.HTTPMethod ?? "GET")?.relation ?? "objects"
              if let embeddedResource = self.resource(named: literal) {
                for object in objects {
                  builder.addRepresentor(relation) { builder in
                    self.addObjectResponse(embeddedResource, parameters: parameters, request: request, response: response, object: object, builder: builder)
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  func addObjectResponseOfResource(relation:String, resource:Resource, request:NSURLRequest, response:NSHTTPURLResponse, object:AnyObject, builder:RepresentorBuilder<HTTPTransition>) {
    if let attributes = object as? [String:AnyObject] {
      builder.addRepresentor(relation) { builder in
        self.addAttributes([:], resource: resource, request: request, response: response, attributes: attributes, builder: builder)
      }
    } else if let objects = object as? [[String:AnyObject]] {
      for object in objects {
        addObjectResponseOfResource(relation, resource: resource, request: request, response: response, object: object, builder: builder)
      }
    }
  }

  func addAttributes(parameters:[String:AnyObject]?, resource:Resource, request:NSURLRequest, response:NSHTTPURLResponse, attributes:[String:AnyObject], builder:RepresentorBuilder<HTTPTransition>) {
    let action = actionForResource(resource, method: request.HTTPMethod!)

    func resourceForAttribute(key:String) -> Resource? {
      // TODO: Rewrite this to use proper refract structures
      if let dataStructure = resource.dataStructure {
        if let sections = dataStructure["sections"] as? [[String:AnyObject]] {
          if let section = sections.first {
            if (section["class"] as? String ?? "") == "memberType" {
              if let members = section["content"] as? [[String:AnyObject]] {
                func findMember(member:[String:AnyObject]) -> Bool {
                  if let content = member["content"] as? [String:AnyObject] {
                    if let name = content["name"] as? [String:String] {
                      if let literal = name["literal"] {
                        return literal == key
                      }
                    }
                  }

                  return false
                }

                if let member = members.filter(findMember).first {
                  if let content = member["content"] as? [String:AnyObject] {
                    if let definition = content["valueDefinition"] as? [String:AnyObject] {
                      if let typeDefinition = definition["typeDefinition"] as? [String:AnyObject] {
                        if let typeSpecification = typeDefinition["typeSpecification"] as? [String:AnyObject] {
                          if let name = typeSpecification["name"] as? String {
                            if name == "array" {
                              if let literal = (typeSpecification["nestedTypes"] as? [[String:AnyObject]])?.first?["literal"] as? String {
                                return self.resource(named:literal)
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      
      return nil
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

  func addTransitions(resource:Resource, parameters:[String:AnyObject]?, builder:RepresentorBuilder<HTTPTransition>, allowedMethods:[String]? = nil) {
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
