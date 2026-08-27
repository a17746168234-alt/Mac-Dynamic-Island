import Foundation

private enum LyricsTestFailure: Error {
    case assertion(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw LyricsTestFailure.assertion(message) }
}

@main
struct LyricsSupportTests {
    static func main() throws {
        try preservesReservedCharactersInSearchQueries()
        try skipsEmptyAndMismatchedSearchResults()
        try exposesPlainLyricsInsteadOfClaimingTheyAreUnavailable()
        try keepsLyricsPanelCompactAndReadable()
        try prioritizesNeteaseOnlyForTheNeteasePlayer()
        try buildsSafeNeteaseSearchAndSelectsTheVerifiedOriginalSong()
        try retriesNeteaseWithCleanedTitleAndArtistAliases()
        try decodesNeteaseSynchronizedLyrics()
        print("LyricsSupportTests: PASS")
    }

    private static func preservesReservedCharactersInSearchQueries() throws {
        let url = try LyricsSearchPolicy.searchURL(title: "A&B?", artist: "歌手 / Artist")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        try expect(items["track_name"] == "A&B?", "歌名中的特殊字符不得破坏查询参数")
        try expect(items["artist_name"] == "歌手 / Artist", "歌手名必须完整传给歌词服务")
    }

    private static func skipsEmptyAndMismatchedSearchResults() throws {
        let candidates = [
            LyricsSearchCandidate(trackName: "恋人", artistName: "福山雅治", duration: 279, plainLyrics: "错误歌词", syncedLyrics: "[00:01.00]错误歌词"),
            LyricsSearchCandidate(trackName: "恋人", artistName: "李荣浩", duration: 275, plainLyrics: nil, syncedLyrics: nil),
            LyricsSearchCandidate(trackName: "恋人", artistName: "李荣浩", duration: 276, plainLyrics: "正确歌词", syncedLyrics: "[00:01.00]正确歌词")
        ]
        let best = LyricsSearchPolicy.bestCandidate(
            in: candidates,
            title: "恋人",
            artist: "李荣浩",
            duration: 276
        )
        try expect(best?.plainLyrics == "正确歌词", "必须跳过空结果和同名但歌手不符的歌词")
    }

    private static func exposesPlainLyricsInsteadOfClaimingTheyAreUnavailable() throws {
        let preview = LyricsDisplayPolicy.plainPreview("第一行\n\n 第二行 \n第三行")
        try expect(preview == ["第一行", "第二行"], "普通歌词必须显示前两行作为可读回退")
        try expect(
            LyricsDisplayPolicy.mode(isFetching: false, syncedLyricsCount: 0, currentLyrics: "第一行") == .plain,
            "只有普通歌词时不得显示暂无歌词"
        )
        try expect(
            LyricsDisplayPolicy.mode(isFetching: false, syncedLyricsCount: 0, currentLyrics: "") == .hidden,
            "确实没有任何歌词时应直接隐藏歌词区域"
        )
    }

    private static func keepsLyricsPanelCompactAndReadable() throws {
        let layout = LyricsPanelLayout()
        try expect(layout.currentLineSize == 13, "实时歌词当前行需要清晰突出")
        try expect(layout.secondaryLineSize == 10, "辅助歌词行应降低视觉层级")
        try expect(layout.lineSpacing == 2, "歌词行距必须紧凑但可辨认")
        try expect(layout.maxPlainLines == 2, "普通歌词回退最多显示两行")
    }

    private static func buildsSafeNeteaseSearchAndSelectsTheVerifiedOriginalSong() throws {
        let request = try NeteaseLyricsPolicy.searchRequest(title: "恋人 & Live?", artist: "李荣浩")
        try expect(request.httpMethod == "POST", "网易云搜索必须使用 POST，避免特殊字符破坏 URL")
        try expect(request.url?.absoluteString == "https://music.163.com/api/search/get/web", "网易云搜索地址必须固定")
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        var components = URLComponents()
        components.percentEncodedQuery = body
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        try expect(items["s"] == "恋人 & Live? 李荣浩", "歌名、歌手和特殊字符必须完整传给网易云")
        try expect(items["type"] == "1" && items["limit"] == "20", "网易云搜索必须限定为歌曲并提供足够候选")

        let candidates = [
            NeteaseSongCandidate(
                id: 3325761527,
                name: "恋人",
                durationMilliseconds: 189_312,
                status: 0,
                artists: [NeteaseArtistCandidate(id: 0, name: "李荣浩-")]
            ),
            NeteaseSongCandidate(
                id: 2600493765,
                name: "恋人",
                durationMilliseconds: 275_912,
                status: 0,
                artists: [NeteaseArtistCandidate(id: 4292, name: "李荣浩")]
            ),
            NeteaseSongCandidate(
                id: 3313203938,
                name: "恋人(沉浸版)",
                durationMilliseconds: 276_035,
                status: 0,
                artists: [NeteaseArtistCandidate(id: 33913010, name: "七年同学")]
            )
        ]
        let best = NeteaseLyricsPolicy.bestCandidate(
            in: candidates,
            title: "恋人",
            artist: "李荣浩",
            duration: 276
        )
        try expect(best?.id == 2600493765, "必须按真实歌手和时长选择网易云原曲，不能被同名翻唱或伪造歌手误导")
    }

    private static func retriesNeteaseWithCleanedTitleAndArtistAliases() throws {
        try expect(
            NeteaseLyricsPolicy.searchTerms(
                title: "恋人 (Live版)",
                artist: "李荣浩 / 合作歌手"
            ) == ["恋人 (Live版) 李荣浩 / 合作歌手", "恋人 李荣浩 / 合作歌手", "恋人"],
            "网易云精确搜索失败后必须使用清理后的歌名和纯歌名继续查找"
        )

        let candidates = [
            NeteaseSongCandidate(
                id: 2600493765,
                name: "恋人",
                durationMilliseconds: 275_912,
                status: 0,
                artists: [NeteaseArtistCandidate(id: 4292, name: "李荣浩")]
            )
        ]
        let best = NeteaseLyricsPolicy.bestCandidate(
            in: candidates,
            title: "恋人 (Live版)",
            artist: "李荣浩 / 合作歌手",
            duration: 276
        )
        try expect(best?.id == 2600493765, "播放器附带版本后缀或多个歌手时仍应识别网易云原曲")

        let englishCandidates = [
            NeteaseSongCandidate(
                id: 1,
                name: "Fortnight",
                durationMilliseconds: 228_000,
                status: 0,
                artists: [NeteaseArtistCandidate(id: 11, name: "Taylor Dayne")]
            ),
            NeteaseSongCandidate(
                id: 2,
                name: "Fortnight",
                durationMilliseconds: 228_500,
                status: 0,
                artists: [NeteaseArtistCandidate(id: 12, name: "Taylor Swift")]
            )
        ]
        let englishBest = NeteaseLyricsPolicy.bestCandidate(
            in: englishCandidates,
            title: "Fortnight",
            artist: "Taylor Swift feat. Post Malone",
            duration: 228
        )
        try expect(englishBest?.id == 2, "英文歌手名不得按空格拆碎后误配到另一位同名歌手")
    }

    private static func prioritizesNeteaseOnlyForTheNeteasePlayer() throws {
        try expect(
            LyricsLookupPolicy.sources(bundleIdentifier: "com.netease.163music") == [.netease, .lrclib],
            "网易云播放器必须先查网易云歌词，再回退公共歌词库"
        )
        try expect(
            LyricsLookupPolicy.sources(bundleIdentifier: "com.spotify.client") == [.lrclib],
            "其他播放器不能无故请求网易云接口"
        )
    }

    private static func decodesNeteaseSynchronizedLyrics() throws {
        let data = Data(#"{"lrc":{"version":3,"lyric":"[00:26.02]爱像是一场小雨\n[00:33.37]滴入我回忆"},"code":200}"#.utf8)
        let response = try JSONDecoder().decode(NeteaseLyricsResponse.self, from: data)
        try expect(
            response.synchronizedLyrics == "[00:26.02]爱像是一场小雨\n[00:33.37]滴入我回忆",
            "网易云返回的时间轴歌词必须完整保留给实时逐行显示"
        )
    }
}

private func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw LyricsTestFailure.assertion("预期值不能为空") }
    return value
}
