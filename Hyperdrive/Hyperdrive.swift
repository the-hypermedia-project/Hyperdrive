//
//  Hyperdrive.swift
//  Hyperdrive
//
//  Created by Kyle Fuller on 08/04/2015.
//  Copyright (c) 2015 Apiary. All rights reserved.
//

import Foundation
import Representor
import URITemplate
import Result


/// Map a dictionaries values
func map<K,V>(source:[K:V], transform:(V -> V)) -> [K:V] {
  var result = [K:V]()

  for (key, value) in source {
    result[key] = transform(value)
  }

  return result
}

/// Returns an absolute URI for a URI given a base URL
func absoluteURI(baseURL:NSURL?)(uri:String) -> String {
  return NSURL(string: uri, relativeToURL: baseURL)?.absoluteString ?? uri
}

/// Traverses a representor and ensures that all URIs are absolute given a base URL
func absoluteRepresentor(baseURL:NSURL?)(original:Representor<HTTPTransition>) -> Representor<HTTPTransition> {
  let transitions = map(original.transitions) { transition in
    return HTTPTransition(uri: absoluteURI(baseURL)(uri: transition.uri)) { builder in
      builder.method = transition.method
      builder.suggestedContentTypes = transition.suggestedContentTypes

      for (name, attribute) in transition.attributes {
        builder.addAttribute(name, value: attribute.value, defaultValue: attribute.defaultValue)
      }

      for (name, parameter) in transition.parameters {
        builder.addParameter(name, value: parameter.value, defaultValue: parameter.defaultValue)
      }
    }
  }

  let representors = map(original.representors) { representors in
    representors.map(absoluteRepresentor(baseURL))
  }

  return Representor(transitions: transitions, representors: representors, attributes: original.attributes, metadata: original.metadata)
}


public typealias RepresentorResult = Result<Representor<HTTPTransition>, NSError>
public typealias RequestResult = Result<NSMutableURLRequest, NSError>
public typealias ResponseResult = Result<NSHTTPURLResponse, NSError>


/// A hypermedia API client
public class Hyperdrive {
  public static var errorDomain:String {
    return "Hyperdrive"
  }

  private let session:NSURLSession

  /// An array of the supported content types in order of preference
  let preferredContentTypes:[String]

  /** Initialize hyperdrive
  - parameter preferredContentTypes: An optional array of the supported content types in order of preference, when this is nil. All types supported by the Representor will be used.
  */
  public init(preferredContentTypes:[String]? = nil) {
    let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
    session = NSURLSession(configuration: configuration)
    self.preferredContentTypes = preferredContentTypes ?? HTTPDeserialization.preferredContentTypes
  }

  // MARK: -

  /// Enter a hypermedia API given the root URI
  public func enter(uri:String, completion:(RepresentorResult -> Void)) {
    request(uri, completion:completion)
  }

  // MARK: Subclass hooks

  /// Construct a request from a URI and parameters
  public func constructRequest(uri:String, parameters:[String:AnyObject]? = nil) -> RequestResult {
    let expandedURI = URITemplate(template: uri).expand(parameters ?? [:])

    let error = NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Creating NSURL from given URI failed"])
    return Result(NSURL(string: expandedURI), failWith: error).map { URL in
      let request = NSMutableURLRequest(URL: URL)
      request.setValue(preferredContentTypes.joinWithSeparator("; "), forHTTPHeaderField: "Accept")
      return request
    }
  }

  public func constructRequest(transition:HTTPTransition, parameters:[String:AnyObject]?  = nil, attributes:[String:AnyObject]? = nil) -> RequestResult {
    return constructRequest(transition.uri, parameters:parameters).map { request in
      request.HTTPMethod = transition.method

      if let attributes = attributes {
        request.HTTPBody = self.encodeAttributes(attributes, suggestedContentTypes: transition.suggestedContentTypes)
      }

      return request
    }
  }

  func encodeAttributes(attributes:[String:AnyObject], suggestedContentTypes:[String]) -> NSData? {
    let JSONEncoder = { (attributes:[String:AnyObject]) -> NSData? in
      return try? NSJSONSerialization.dataWithJSONObject(attributes, options: NSJSONWritingOptions(rawValue: 0))
    }

    let encoders:[String:([String:AnyObject] -> NSData?)] = [
      "application/json": JSONEncoder
    ]

    for contentType in suggestedContentTypes {
      if let encoder = encoders[contentType] {
        return encoder(attributes)
      }
    }

    return JSONEncoder(attributes)
  }

  public func constructResponse(request:NSURLRequest, response:NSHTTPURLResponse, body:NSData?) -> Representor<HTTPTransition>? {
    if let body = body {
      let representor = HTTPDeserialization.deserialize(response, body: body)
      if let representor = representor {
        return absoluteRepresentor(response.URL)(original: representor)
      }
    }

    return nil
  }

  // MARK: Perform requests

  func request(request:NSURLRequest, completion:(RepresentorResult -> Void)) {
    let dataTask = session.dataTaskWithRequest(request, completionHandler: { (body, response, error) -> Void in
      if let error = error {
        dispatch_async(dispatch_get_main_queue()) {
          completion(.Failure(error))
        }
      } else {
        let representor = self.constructResponse(request, response:response as! NSHTTPURLResponse, body: body) ?? Representor<HTTPTransition>()
        dispatch_async(dispatch_get_main_queue()) {
          completion(.Success(representor))
        }
      }
    })

    dataTask.resume()
  }

  /// Perform a request with a given URI and parameters
  public func request(uri:String, parameters:[String:AnyObject]? = nil, completion:(RepresentorResult -> Void)) {
    switch constructRequest(uri, parameters: parameters) {
    case .Success(let request):
      self.request(request, completion:completion)
    case .Failure(let error):
      completion(.Failure(error))
    }
  }

  /// Perform a transition with a given parameters and attributes
  public func request(transition:HTTPTransition, parameters:[String:AnyObject]? = nil, attributes:[String:AnyObject]? = nil, completion:(RepresentorResult -> Void)) {
    let result = constructRequest(transition, parameters: parameters, attributes: attributes)

    switch result {
    case .Success(let request):
      self.request(request, completion:completion)
    case .Failure(let error):
      completion(.Failure(error))
    }
  }
}
