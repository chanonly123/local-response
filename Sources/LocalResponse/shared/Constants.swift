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
    static let contentTypeKey = "Content-Type"
    static let contentLengthKey = "Content-Length"
    /// Headers the local server fills in itself when it serves a mapped
    /// response — whatever a rule sets for these is overwritten.
    static let serverManagedHeaders = [contentTypeKey, contentLengthKey]
    static let filterKey = "filterKey"

    static let schemaVersion: UInt64 = 25

    static let fontSize: CGFloat = 11
    static let fontSizeKey: String = "fontSize"
    static let leftViewModeKey: String = "leftViewMode"
    static let recordBeginUrl = "POST /record-begin"
    static let recordEndUrl = "POST /record-end"
    static let checkMapResponse = "POST /check-map-response"
    static let overridenRequest = "GET /overriden-request"
}
