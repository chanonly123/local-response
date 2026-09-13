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
    /// Request headers URLSession fills in itself — a `modifyRequest` rule that
    /// sets one of these is silently dropped on the way out.
    static let sessionManagedRequestHeaders = [
        contentLengthKey,
        "Connection",
        "Host",
        "Proxy-Authenticate",
        "Proxy-Authorization",
        "WWW-Authenticate"
    ]
    static let filterKey = "filterKey"

    static let schemaVersion: UInt64 = 32

    /// Set once the database files Realm left behind have been removed, so the
    /// sweep does not run on every launch forever.
    static let legacyRealmRemovedKey = "legacyRealmRemoved"

    /// Longest delay the mapper may hold a request for, in milliseconds.
    /// Bounded because the app waits it out on the rule lookup, and a stall
    /// past this stops looking like a slow server and starts looking like a
    /// hung mapper.
    static let maxMapDelayMs = 10_000

    /// The delay is set in tenths of a second, so this is what one press of the
    /// stepper is worth and what every stored value is a multiple of.
    static let mapDelayStepMs = 100

    /// Rule lookup gets its own budget: it has to outlast the longest delay the
    /// mapper can hold a request for, unlike the fire-and-forget record calls.
    static let mapCheckTimeout: TimeInterval = Double(maxMapDelayMs) / 1000 + 10

    static let fontSize: CGFloat = 11
    /// The range ⌘= and ⌘- move within. Named here rather than written into the
    /// two places that clamp: the menu command and the editor have to agree, or
    /// the size the menu refuses to pass is one the editor still accepts.
    static let fontSizeMin: CGFloat = 8
    static let fontSizeMax: CGFloat = 20
    static let fontSizeKey: String = "fontSize"
    static let leftViewModeKey: String = "leftViewMode"
    /// Master switch over every rule. Stored inverted — the key holds "rules are
    /// off" — so the value `UserDefaults` invents for a fresh install, `false`,
    /// is the one that leaves mapping working.
    static let mapRulesOffKey: String = "mapRulesOff"
    /// How long the mapper holds every request a rule matched, in milliseconds.
    /// One setting for all rules rather than a field on each.
    static let mapDelayMsKey: String = "mapDelayMs"
    /// Which columns the request table shows, and in what order — the encoded
    /// `TableColumnCustomization`.
    static let tableColumnsKey: String = "tableColumns"
    /// Stored inverted — the key holds "the query is hidden" — so the value
    /// `UserDefaults` invents for a fresh install, `false`, is the one that
    /// shows it.
    static let hideUrlQueryKey: String = "hideUrlQuery"
    /// Inverted for the same reason: a fresh install follows the newest call.
    static let autoScrollOffKey: String = "autoScrollOff"

    /// Longest a single value is shown in full wherever one is listed — a
    /// header, a query parameter, the url column.
    ///
    /// One oversized value — an auth token, a base64 blob — otherwise pushes
    /// everything around it out of view. Only the display is cut: copying,
    /// mapping and the stored record all keep the whole value.
    static let collapseLimit = 50
    static let contentRightPaneWidthKey: String = "contentRightPaneWidth"
    static let mapLocalRightPaneWidthKey: String = "mapLocalRightPaneWidth"
    static let recordBeginUrl = "POST /record-begin"
    static let recordEndUrl = "POST /record-end"
    static let recordUpdateUrl = "POST /record-update"
    static let checkMapResponse = "POST /check-map-response"
    /// Path only, no method: the mapped response is fetched with whatever
    /// method the app's own request used, so the route has to answer all of
    /// them. See `LocalResponse.injectorSessionOverrideResume`.
    static let overridenRequest = "/overriden-request"
}
