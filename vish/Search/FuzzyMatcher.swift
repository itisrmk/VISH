import Foundation

enum FuzzyMatcher {
    static func score(query: String, candidate: String) -> Double? {
        guard !query.isEmpty, !candidate.isEmpty else { return nil }
        if candidate == query { return 1 }
        if candidate.hasPrefix(query) { return 0.95 }
        if candidate.contains(query) { return 0.8 }
        return subsequenceScore(query: query, candidate: candidate)
    }

    private static func subsequenceScore(query: String, candidate: String) -> Double? {
        var queryIndex = query.startIndex
        var hits = 0

        for character in candidate {
            guard character == query[queryIndex] else { continue }
            hits += 1
            query.formIndex(after: &queryIndex)
            if queryIndex == query.endIndex {
                return 0.35 + Double(hits) / Double(candidate.count + query.count)
            }
        }

        return nil
    }
}
