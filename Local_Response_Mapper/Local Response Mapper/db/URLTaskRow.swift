//
//  URLTaskRow.swift
//  Local Response Mapper
//

import Foundation
import GRDB

/// The part of a recorded call the request list and the endpoint tree draw —
/// and nothing else.
///
/// A recorded call carries its request body and its response body, which are
/// nearly all of its weight. The list is re-read in full after every committed
/// write, so reading those two columns here would read, decode and hold
/// megabytes of text that no row on screen shows. The detail pane fetches the
/// whole `URLTaskObject` by `taskId` for the one row it is following.
final class URLTaskRow: Codable, Identifiable, FetchableRecord {

    static let databaseTableName = URLTaskObject.databaseTableName

    var id: String { taskId }

    var taskId: String = ""
    var date: Double = 0
    var startTime: Double = 0
    var endTime: Double = 0
    var url: String = ""
    var method: String = ""
    var bundleID: String = ""
    var mimeType: String = ""
    var statusCode: Int = 0
    var isEdited: Bool = false
    var isRequestEdited: Bool = false

    /// The select list is built from these, so the columns read and the
    /// properties decoded cannot drift apart.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case taskId, date, startTime, endTime, url, method
        case bundleID, mimeType, statusCode, isEdited, isRequestEdited
    }

    static var selectedColumns: [Column] {
        CodingKeys.allCases.map { Column($0.rawValue) }
    }

    /// Whether this row says the same as `other`.
    ///
    /// A refresh that changed nothing the list shows — a request filtered out of
    /// view, most often — should not reach SwiftUI at all, and this is how that
    /// is told apart from a refresh that did change something.
    func sameContent(as other: URLTaskRow) -> Bool {
        taskId == other.taskId
            && statusCode == other.statusCode
            && endTime == other.endTime
            && startTime == other.startTime
            && date == other.date
            && url == other.url
            && method == other.method
            && bundleID == other.bundleID
            && mimeType == other.mimeType
            && isEdited == other.isEdited
            && isRequestEdited == other.isRequestEdited
    }

    /// Rows are re-fetched rather than mutated, so this is computed once per
    /// row and not once per redraw — the url column redraws on every refresh.
    lazy var getPathString: String = {
        guard let urlObj = URL(string: url) else {
            return ""
        }
        return (urlObj.host() ?? "") + urlObj.path()
    }()

    /// The same, with whatever the url carries after the `?`.
    ///
    /// Two calls to one endpoint often differ only in their parameters, so
    /// without these the rows read as duplicates — see the footer switch.
    /// Parameter by parameter rather than as one string: a single oversized
    /// value — a token, a signature — would otherwise be the whole column, so
    /// a value past `Constants.collapseLimit` is replaced by `"..."` and only
    /// its name is shown.
    ///
    /// Read straight off the url rather than through `URLComponents`, which
    /// percent-decodes what it hands back and gives nothing at all for a url it
    /// cannot parse. The column shows the query as it went over the wire; the
    /// tooltip still carries the whole url, and the detail pane lists the
    /// parameters decoded.
    lazy var getPathWithQuery: String = {
        guard let mark = url.firstIndex(of: "?") else { return getPathString }

        // A fragment is not part of the query and belongs to nobody here.
        var raw = url[url.index(after: mark)...]
        if let hash = raw.firstIndex(of: "#") {
            raw = raw[..<hash]
        }
        guard !raw.isEmpty else { return getPathString }

        let query = raw
            .split(separator: "&", omittingEmptySubsequences: false)
            .map { pair -> String in
                guard let equals = pair.firstIndex(of: "=") else { return String(pair) }
                let value = pair[pair.index(after: equals)...]
                guard value.count > Constants.collapseLimit else { return String(pair) }
                // Dropped whole rather than cut short: half a token says no
                // more than none of it, and the name is what identifies the
                // parameter in a row this narrow. Quoted so the row reads as a
                // value deliberately left out, not one that is literally three
                // dots.
                return "\(pair[..<equals])=\"...\""
            }
            .joined(separator: "&")

        return "\(getPathString)?\(query)"
    }()

    // Reused across every row/render — allocating a NumberFormatter per call is expensive.
    private static let timeDelayFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    var timeDelay: String {
        let diff = endTime - startTime
        guard diff > 0, let str = Self.timeDelayFormatter.string(from: NSNumber(value: diff)) else {
            return ""
        }
        return str
    }
}
