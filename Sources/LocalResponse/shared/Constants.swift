//
//  File.swift
//
//
//  Created by Chandan on 16/08/24.
//

import Foundation

class Constants {

    static let localBaseUrlPort = 4040
    static let localBaseUrl = "http://localhost:\(localBaseUrlPort)"
    static let higlightThemeLight = "xcode"
    static let higlightThemeDark = "tomorrow-night-bright"
    static let contentEncodingKey = "Content-Encoding"

    static let schemaVersion: UInt64 = 21

    static let fontSize: CGFloat = 11
    static let fontSizeKey: String = "fontSize"
    static let recordBeginUrl = "POST /record-begin"
    static let recordEndUrl = "POST /record-end"
    static let checkMapResponse = "POST /check-map-response"
    static let overridenRequest = "POST /overriden-request"
}
