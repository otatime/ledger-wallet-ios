//
//  HTTPClientTask.swift
//  ledger-wallet-ios
//
//  Created by Nicolas Bigot on 12/02/2015.
//  Copyright (c) 2015 Ledger. All rights reserved.
//

import Foundation

extension HTTPClient {
    
    final class Task {
        
        typealias CompletionHandler = (NSData?, NSURLRequest, NSHTTPURLResponse?, NSError?) -> Void
        typealias Parameters = [String: AnyObject]
     
        enum Method: String {
            case GET = "GET"
            case HEAD = "HEAD"
            case POST = "POST"
            case PUT = "PUT"
            case DELETE = "DELETE"
        }
        
        enum Encoding {
            case URL
            case JSON
            
            func encode(URLRequest: NSMutableURLRequest, parameters: Parameters?) -> NSError? {
                if parameters == nil {
                    return nil
                }
                var error: NSError? = nil
                
                // set properly encoded parameters
                switch self {
                case .URL:
                    func query(parameters: [String: AnyObject]) -> String {
                        var components: [(String, String)] = []
                        for key in sorted(Array(parameters.keys), <) {
                            let value: AnyObject! = parameters[key]
                            components += queryComponents(key, value)
                        }
                        
                        return join("&", components.map{"\($0)=\($1)"} as [String])
                    }
                    
                    func encodesParametersInURL(method: Method) -> Bool {
                        switch method {
                        case .GET, .HEAD, .DELETE:
                            return true
                        default:
                            return false
                        }
                    }
                    
                    let method = Method(rawValue: URLRequest.HTTPMethod)
                    if method != nil && encodesParametersInURL(method!) {
                        if let URLComponents = NSURLComponents(URL: URLRequest.URL!, resolvingAgainstBaseURL: false) {
                            URLComponents.percentEncodedQuery = (URLComponents.percentEncodedQuery != nil ? URLComponents.percentEncodedQuery! + "&" : "") + query(parameters!)
                            URLRequest.URL = URLComponents.URL
                        }
                    } else {
                        if URLRequest.valueForHTTPHeaderField("Content-Type") == nil {
                            URLRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                        }
                        URLRequest.HTTPBody = query(parameters!).dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)
                    }
                case .JSON:
                    if let data = NSJSONSerialization.dataWithJSONObject(parameters!, options: nil, error: &error) {
                        URLRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        URLRequest.HTTPBody = data
                    }
                }
                return error
            }
            
            func queryComponents(key: String, _ value: AnyObject) -> [(String, String)] {
                var components: [(String, String)] = []
                if let dictionary = value as? [String: AnyObject] {
                    for (nestedKey, value) in dictionary {
                        components += queryComponents("\(key)[\(nestedKey)]", value)
                    }
                } else if let array = value as? [AnyObject] {
                    for value in array {
                        components += queryComponents("\(key)[]", value)
                    }
                } else {
                    components.extend([(escape(key), escape("\(value)"))])
                }
                
                return components
            }
            
            func escape(string: String) -> String {
                let legalURLCharactersToBeEscaped: CFStringRef = ":/?&=;+!@#$()',*"
                return CFURLCreateStringByAddingPercentEscapes(nil, string, nil, legalURLCharactersToBeEscaped, CFStringBuiltInEncodings.UTF8.rawValue) as String
            }
        }

        
    }
    
}