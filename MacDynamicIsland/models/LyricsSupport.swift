import Foundation

enum LyricsLookupSource: Equatable {
    case netease
    case lrclib
}

enum LyricsLookupPolicy {
    static func sources(bundleIdentifier: String?) -> [LyricsLookupSource] {
        NeteaseLyricsPolicy.supports(bundleIdentifier: bundleIdentifier)
            ? [.netease, .lrclib]
            : [.lrclib]
    }
}

struct NeteaseArtistCandidate: Decodable, Equatable {
    let id: Int64
    let name: String
}

struct NeteaseSongCandidate: Decodable, Equatable {
    let id: Int64
    let name: String
    let durationMilliseconds: Double
    let status: Int
    let artists: [NeteaseArtistCandidate]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case durationMilliseconds = "duration"
        case status
        case artists
    }
}

struct NeteaseSearchResponse: Decodable {
    struct SearchResult: Decodable {
        let songs: [NeteaseSongCandidate]?
    }

    let result: SearchResult?

    var songs: [NeteaseSongCandidate] { result?.songs ?? [] }
}

struct NeteaseLyricsResponse: Decodable {
    struct LyricsBody: Decodable {
        let version: Int?
        let lyric: String?
    }

    let lrc: LyricsBody?
    let code: Int

    var synchronizedLyrics: String {
        guard code == 200 else { return "" }
        return lrc?.lyric?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum NeteaseLyricsPolicy {
    enum SearchError: Error {
        case invalidURL
        case invalidBody
    }

    static func supports(bundleIdentifier: String?) -> Bool {
        bundleIdentifier?.lowercased() == "com.netease.163music"
    }

    static func searchRequest(title: String, artist: String) throws -> URLRequest {
        try searchRequest(term: "\(title) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func searchRequest(term: String) throws -> URLRequest {
        guard let url = URL(string: "https://music.163.com/api/search/get/web") else {
            throw SearchError.invalidURL
        }
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "s", value: term),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "total", value: "true"),
            URLQueryItem(name: "limit", value: "20")
        ]
        guard let body = form.percentEncodedQuery?.data(using: .utf8) else {
            throw SearchError.invalidBody
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func searchTerms(title: String, artist: String) -> [String] {
        let cleanTitle = baseTitle(title)
        let exact = "\(title) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = "\(cleanTitle) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        var terms = [exact, cleaned, cleanTitle]
        var seen = Set<String>()
        terms.removeAll { !seen.insert($0).inserted || $0.isEmpty }
        return terms
    }

    static func lyricsURL(songID: Int64) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "music.163.com"
        components.path = "/api/song/lyric"
        components.queryItems = [
            URLQueryItem(name: "id", value: String(songID)),
            URLQueryItem(name: "lv", value: "1"),
            URLQueryItem(name: "kv", value: "1"),
            URLQueryItem(name: "tv", value: "-1")
        ]
        guard let url = components.url else { throw SearchError.invalidURL }
        return url
    }

    static func bestCandidate(
        in candidates: [NeteaseSongCandidate],
        title: String,
        artist: String,
        duration: Double
    ) -> NeteaseSongCandidate? {
        let wantedTitles = Set([normalized(title), normalized(baseTitle(title))])
        let wantedArtists = artistAliases(artist)

        return candidates
            .filter { candidate in
                let candidateTitles = Set([normalized(candidate.name), normalized(baseTitle(candidate.name))])
                guard candidate.status >= 0, !wantedTitles.isDisjoint(with: candidateTitles) else { return false }
                let hasVerifiedArtist = candidate.artists.contains { item in
                    guard item.id > 0 else { return false }
                    let name = normalized(item.name)
                    return wantedArtists.isEmpty || wantedArtists.contains { wantedArtist in
                        name == wantedArtist
                            || name.contains(wantedArtist)
                            || wantedArtist.contains(name)
                    }
                }
                guard hasVerifiedArtist else { return false }
                if duration > 0 {
                    return abs(candidate.durationMilliseconds / 1_000 - duration) <= 15
                }
                return true
            }
            .min { lhs, rhs in
                abs(lhs.durationMilliseconds / 1_000 - duration)
                    < abs(rhs.durationMilliseconds / 1_000 - duration)
            }
    }

    private static func baseTitle(_ title: String) -> String {
        var value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"\s*[\(（\[【][^\)）\]】]*[\)）\]】]\s*$"#,
            #"\s*[-–—]\s*(?:live|现场|伴奏|remaster|acoustic|纯享|版).*$"#
        ]
        for pattern in patterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func artistAliases(_ artist: String) -> Set<String> {
        let separated = artist.replacingOccurrences(
            of: #"\s+(?:feat\.?|ft\.?)\s+"#,
            with: "/",
            options: [.regularExpression, .caseInsensitive]
        )
        let values = separated.components(separatedBy: CharacterSet(charactersIn: "/／,，、&＆"))
            .map(normalized)
            .filter { !$0.isEmpty }
        return Set(values.isEmpty ? [normalized(artist)].filter { !$0.isEmpty } : values)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

struct LyricsSearchCandidate: Decodable, Equatable {
    let trackName: String
    let artistName: String
    let duration: Double?
    let plainLyrics: String?
    let syncedLyrics: String?

    var hasPlainLyrics: Bool {
        !(plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var hasSyncedLyrics: Bool {
        !(syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

enum LyricsSearchPolicy {
    enum SearchError: Error {
        case invalidURL
    }

    static func searchURL(title: String, artist: String?) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "lrclib.net"
        components.path = "/api/search"
        var queryItems = [URLQueryItem(name: "track_name", value: title)]
        if let artist, !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "artist_name", value: artist))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw SearchError.invalidURL }
        return url
    }

    static func bestCandidate(
        in candidates: [LyricsSearchCandidate],
        title: String,
        artist: String,
        duration: Double
    ) -> LyricsSearchCandidate? {
        let wantedTitle = normalized(title)
        let wantedArtist = normalized(artist)

        return candidates
            .filter { candidate in
                guard candidate.hasPlainLyrics || candidate.hasSyncedLyrics else { return false }
                let candidateTitle = normalized(candidate.trackName)
                let candidateArtist = normalized(candidate.artistName)
                let titleMatches = candidateTitle == wantedTitle
                    || candidateTitle.contains(wantedTitle)
                    || wantedTitle.contains(candidateTitle)
                let artistMatches = wantedArtist.isEmpty
                    || candidateArtist == wantedArtist
                    || candidateArtist.contains(wantedArtist)
                    || wantedArtist.contains(candidateArtist)
                return titleMatches && artistMatches
            }
            .max { score($0, title: wantedTitle, artist: wantedArtist, duration: duration)
                < score($1, title: wantedTitle, artist: wantedArtist, duration: duration) }
    }

    private static func score(
        _ candidate: LyricsSearchCandidate,
        title: String,
        artist: String,
        duration: Double
    ) -> Double {
        var value = candidate.hasSyncedLyrics ? 1_000.0 : 500.0
        if normalized(candidate.trackName) == title { value += 200 }
        if normalized(candidate.artistName) == artist { value += 400 }
        if duration > 0, let candidateDuration = candidate.duration {
            value += max(0, 120 - abs(candidateDuration - duration))
        }
        return value
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

enum LyricsDisplayMode: Equatable {
    case loading
    case synced
    case plain
    case hidden
}

enum LyricsDisplayPolicy {
    static func mode(
        isFetching: Bool,
        syncedLyricsCount: Int,
        currentLyrics: String
    ) -> LyricsDisplayMode {
        if isFetching { return .loading }
        if syncedLyricsCount > 0 { return .synced }
        if !currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .plain }
        return .hidden
    }

    static func plainPreview(_ lyrics: String, maximumLines: Int = 2) -> [String] {
        let lines: [String] = lyrics
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(lines.prefix(maximumLines))
    }
}

struct LyricsPanelLayout: Equatable {
    let currentLineSize: CGFloat = 13
    let secondaryLineSize: CGFloat = 10
    let lineSpacing: CGFloat = 2
    let maxPlainLines = 2
}
