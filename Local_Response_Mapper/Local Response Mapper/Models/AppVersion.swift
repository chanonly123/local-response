//
//  AppVersion.swift
//  Local Response Mapper
//

import Foundation

/// Ordering for release tags like `2.0.30`.
enum AppVersion {

    /// True when `latest` names a later release than `current`.
    ///
    /// Compared one component at a time. Joining the digits into a single
    /// number instead ("2.0.30" -> 2030) makes the value depend on how wide
    /// each component happens to be, which reads 3.0.0 (300) as older than
    /// 2.0.30 (2030) and 2.1.0 (210) as older than 2.0.10 (2010).
    ///
    /// A leading `v` is accepted, and a missing component counts as zero, so
    /// `v3.0` and `3.0.0` are the same release.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        let new = components(latest)
        let old = components(current)
        guard !new.isEmpty, !old.isEmpty else { return false }

        for index in 0..<max(new.count, old.count) {
            let lhs = index < new.count ? new[index] : 0
            let rhs = index < old.count ? old[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    /// `nil`-free split into numeric components. Anything that isn't a plain
    /// dotted number — an empty tag, `nightly`, `3.0.0-beta1` — comes back
    /// empty, so it can never be taken for an upgrade.
    private static func components(_ version: String) -> [Int] {
        let trimmed = version
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "v" || $0 == "V" })
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard !numbers.isEmpty, numbers.count == parts.count else { return [] }
        return numbers
    }
}
