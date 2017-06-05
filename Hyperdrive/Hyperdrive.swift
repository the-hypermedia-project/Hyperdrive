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
func map<K,V>(_ source:[K:V], transform:((V) -> V)) -> [K:V] {
  var result = [K:V]()

  for (key, value) in source {
    result[key] = transform(value)
  }

  return result
}

/// Returns an absolute URI for a URI given a base URL
func absoluteURI(_ baseURL: URL?) -> (_ uri: String) -> String {
  return { uri in
    return URL(string: uri, relativeTo: baseURL)?.absoluteString ?? uri
  }
}

/// Traverses a representor and ensures that all URIs are absolute given a base URL
func absoluteRepresentor(_ baseURL: NSURL?) -> (_ original: Representor<HTTPTransition>) -> Representor<HTTPTransition> {
  return { original in
    let transitions = map(original.transitions) { transition in
      return HTTPTransition(uri: absoluteURI(baseURL as URL)(transition.uri)) { builder in
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
}


public typealias RepresentorResult = Result<Representor<HTTPTransition>, NSError>
public typealias RequestResult = Result<NSMutableURLRequest, NSError>
public typealias ResponseResult = Result<HTTPURLResponse, NSError>


/// A hypermedia API client
open class Hyperdrive {
  open static var errorDomain:String {
    return "Hyperdrive"
  }

  fileprivate let session:URLSession

  /// An array of the supported content types in order of preference
  let preferredContentTypes:[String]

  /** Initialize hyperdrive
  - parameter preferredContentTypes: An optional array of the supported content types in order of preference, when this is nil. All types supported by the Representor will be used.
  */
  public init(preferredContentTypes:[String]? = nil) {
    let configuration = URLSessionConfiguration.default
    session = URLSession(configuration: configuration)
    self.preferredContentTypes = preferredContentTypes ?? HTTPDeserialization.preferredContentTypes
  }

  // MARK: -

  /// Enter a hypermedia API given the root URI
  open func enter(_ uri:String, completion:((RepresentorResult) -> Void)) {
    request(uri, completion:completion)
  }

  // MARK: Subclass hooks

  /// Construct a request from a URI and parameters
  open func constructRequest(_ uri:String, parameters:[String:AnyObject]? = nil) -> RequestResult {
    let expandedURI = URITemplate(template: uri).expand(parameters ?? [:])

    let error = NSError(domain: Hyperdrive.errorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Creating NSURL from given URI failed"])
    return Result(NSURL(string: expandedURI), failWith: error).map { URL in
      let request = NSMutableURLRequest(url: URL as URL)
      request.setValue(preferredContentTypes.joined(separator: ", "), forHTTPHeaderField: "Accept")
      return request
    }
  }

  open func constructRequest(_ transition:HTTPTransition, parameters:[String:AnyObject]?  = nil, attributes:[String:AnyObject]? = nil) -> RequestResult {
    return constructRequest(transition.uri, parameters:parameters).map { request in
      request.httpMethod = transition.method

      if let attributes = attributes {
        request.httpBody = self.encodeAttributes(attributes, suggestedContentTypes: transition.suggestedContentTypes)
      }

      return request
    }
  }

  func encodeAttributes(_ attributes:[String:AnyObject], suggestedContentTypes:[String]) -> Data? {
    let JSONEncoder = { (attributes:[String:AnyObject]) -> Data? in
      return try? JSONSerialization.data(withJSONObject: attributes, options: JSONSerialization.WritingOptions(rawValue: 0))
    }

    let encoders:[String:(([String:AnyObject]) -> Data?)] = [
      "application/json": JSONEncoder
    ]

    for contentType in suggestedContentTypes {
      if let encoder = encoders[contentType] {
        return encoder(attributes)
      }
    }

    return JSONEncoder(attributes)
  }

  open func constructResponse(_ request:NSURLRequest, response:HTTPURLResponse, body:NSData?) -> Representor<HTTPTransition>? {
    if let body = body {
      let representor = HTTPDeserialization.deserialize(response, body: body as Data)
      if let representor = representor {
        return absoluteRepresentor(response.url as! NSURL)(representor)
      }
    }

    return nil
  }

  // MARK: Perform requests

  func request(_ request:URLRequest, completion:@escaping ((RepresentorResult) -> Void)) {
    let dataTask = session.dataTask(with: request, completionHandler: { (body, response, error) -> Void in
      if let error = error {
        DispatchQueue.main.async {
          completion(.failure(error))
        }
      } else {
        let representor = self.constructResponse(request, response:response as! HTTPURLResponse, body: body) ?? Representor<HTTPTransition>()
        DispatchQueue.main.async {
          completion(.Success(representor))
        }
      }
    })

    dataTask.resume()
  }

  /// Perform a request with a given URI and parameters
  open func request(_ uri:String, parameters:[String:AnyObject]? = nil, completion:((RepresentorResult) -> Void)) {
    switch constructRequest(uri, parameters: parameters) {
    case .Success(let request):
      self.request(request, completion:completion)
    case .Failure(let error):
      completion(.Failure(error))
    }
  }

  /// Perform a transition with a given parameters and attributes
  open func request(_ transition:HTTPTransition, parameters:[String:AnyObject]? = nil, attributes:[String:AnyObject]? = nil, completion:((RepresentorResult) -> Void)) {
    let result = constructRequest(transition, parameters: parameters, attributes: attributes)

    switch result {
    case .Success(let request):
      self.request(request, completion:completion)
    case .Failure(let error):
      completion(.Failure(error))
    }
  }
}
