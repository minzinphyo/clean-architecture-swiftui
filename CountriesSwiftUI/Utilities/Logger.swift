//
//  Logger.swift
//  CountriesSwiftUI
//
//  Created by Min Zin Phyo on 13/07/2026.
//  Copyright © 2026 Alexey Naumov. All rights reserved.
//

import Foundation

enum Logger {

    static func line() {
        print("────────────────────────────────────────────────────────────")
    }

    static func request(_ request: URLRequest) {
        line()
        print("🌍 REQUEST")
        print("URL      : \(request.url?.absoluteString ?? "")")
        print("METHOD   : \(request.httpMethod ?? "")")

        if let headers = request.allHTTPHeaderFields,
           !headers.isEmpty {
            print("HEADERS")
            headers.forEach {
                print("  \($0.key): \($0.value)")
            }
        }

        if let body = request.httpBody,
           let string = String(data: body, encoding: .utf8) {
            print("BODY")
            print(string)
        }

        line()
    }

    static func response(
        _ response: HTTPURLResponse,
        data: Data
    ) {

        line()

        print("✅ RESPONSE")
        print("STATUS : \(response.statusCode)")
        print("URL    : \(response.url?.absoluteString ?? "")")

        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys]
           ),
           let string = String(data: pretty, encoding: .utf8) {

            print(string)

        } else {

            print(String(data: data, encoding: .utf8) ?? "No Body")
        }

        line()
    }

    static func error(_ error: Error) {

        line()

        print("❌ ERROR")
        print(error)

        if let decoding = error as? DecodingError {

            switch decoding {

            case .keyNotFound(let key, let context):

                print("")
                print("KEY NOT FOUND")
                print("Key   : \(key.stringValue)")
                print("Path  : \(path(context.codingPath))")
                print("Debug : \(context.debugDescription)")

            case .typeMismatch(let type, let context):

                print("")
                print("TYPE MISMATCH")
                print("Expected : \(type)")
                print("Path     : \(path(context.codingPath))")
                print("Debug    : \(context.debugDescription)")

            case .valueNotFound(let type, let context):

                print("")
                print("VALUE NOT FOUND")
                print("Expected : \(type)")
                print("Path     : \(path(context.codingPath))")
                print("Debug    : \(context.debugDescription)")

            case .dataCorrupted(let context):

                print("")
                print("DATA CORRUPTED")
                print("Path  : \(path(context.codingPath))")
                print("Debug : \(context.debugDescription)")

            @unknown default:
                break
            }
        }

        line()
    }

    private static func path(_ keys: [CodingKey]) -> String {
        keys
            .map(\.stringValue)
            .joined(separator: " → ")
    }
}
