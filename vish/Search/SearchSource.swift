protocol SearchSource: Sendable {
    func search(_ query: String) -> [SearchResult]
}
