import Darwin
import Foundation

@main
struct PreviewBmsSourceTests {
    @MainActor
    static func main() {
        do {
            try runPure()
            try runBridge()
            print("PreviewBmsSourceTests passed")
        } catch {
            fputs("\(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func runPure() throws {
        testMetadataLeavesMissingFieldsEmpty()
        testGenreAliasAndLastHeaderWins()
        testMetadataKeepsCallerNoteCount()
        testJudgeRankStaysApartFromRankAndVolumeIsStored()
        testPlayerLayoutAndPackedFormula()
        testHeadersSurviveWavRewriteWithoutMovingBga()
        testPathWavRelativeAbsoluteAndBgaUntouched()
        testPathWavBackslashSpaceAndMissingSeparator()
        testNoPathWavKeepsChartDirectoryAndBytes()
        testAbsoluteWavIgnoresPathWav()
        testCacheReplaysUntilReload()
        testCacheUsesInjectedChoicesWithoutRolling()
        try testDefaultChoiceStaysInRangeAndReplays()
    }

    @MainActor
    private static func runBridge() throws {
        try testExclusiveBranchesStayApart()
        try testReloadChangesBranchWithoutTouchingEdit()
        try testUnsavedCurrentBytesFeedTheBranch()
        try testCompactAliasAndNestedInactive()
        try testRondamEndIfAndBytesBetweenRandomAndIf()
        try testCp932BomSurvivesExpansion()
        try testPathWavComesFromTheSameBranch()
        try testPlainEditPreviewReadsCurrentBytes()
    }

    private static func testMetadataLeavesMissingFieldsEmpty() {
        let song = PreviewBmsSource.metadata(from: Data("#WAV01 kick.wav\n#00011:01\n".utf8))
        require(song.title == nil, "missing title stays empty")
        require(song.artist == nil, "missing artist stays empty")
        require(song.genre == nil, "missing genre stays empty")
        require(song.playLevel == nil, "missing playlevel stays empty")
        require(song.rank == nil, "missing rank stays empty")
        require(song.notes == nil, "notes are not invented")
        require(song.title != "Untitled" && song.rank != "3" && song.playLevel != "1", "no placeholder song info")
    }

    private static func testGenreAliasAndLastHeaderWins() {
        let text = "#GENLE Old\n#GENRE Jazz\n#TITLE  Night  Stage  \n#ARTIST A B\n#PLAYLEVEL 07\n#RANK 2\n"
        let song = PreviewBmsSource.metadata(from: Data(text.utf8))
        require(song.genre == "Jazz", "GENRE replaces GENLE")
        require(song.title == "Night  Stage", "title keeps internal spaces")
        require(song.artist == "A B", "artist keeps the rest of the line")
        require(song.playLevel == "07", "playlevel stays the source text")
        require(song.rank == "2", "rank stays the source text")
        let onlyAlias = PreviewBmsSource.metadata(from: Data("#GENLE Rock\n".utf8))
        require(onlyAlias.genre == "Rock" && onlyAlias.title == nil, "GENLE fills genre and nothing else")
    }

    private static func testMetadataKeepsCallerNoteCount() {
        let song = PreviewBmsSource.metadata(from: Data("#TITLE A\n".utf8), noteCount: 4)
        require(song.title == "A" && song.notes == 4, "caller note count is stored")
        let failed = PreviewBmsSource.metadata(from: Data([0xFF, 0xFE, 0x00]), noteCount: 2)
        require(failed.title == nil && failed.notes == 2, "undecodable text does not replace a counted note total")
    }

    private static func testJudgeRankStaysApartFromRankAndVolumeIsStored() {
        let mixed = Data("#RANK 3\n#JUDGERANK 100\n#VOLWAV 80\n#PLAYER 2\n#RANKING 9\n".utf8)
        let song = PreviewBmsSource.metadata(from: mixed)
        require(song.rank == "3", "BMS rank stays the exact RANK header")
        require(song.judgeRank == "100", "JUDGERANK is its own field")
        require(song.volwav == "80", "VOLWAV text is kept")
        require(song.player == "2", "PLAYER text is kept")
        require(PreviewBmsSource.parsedPlayerHeader(song.player) == 2, "PLAYER 2 parses as couple/battle")
        let onlyJudge = PreviewBmsSource.metadata(from: Data("#JUDGERANK 100\n".utf8))
        require(onlyJudge.rank == nil && onlyJudge.judgeRank == "100", "judge rank 100 does not become BMS rank 100")
        require(PreviewBmsSource.parsedPlayerHeader(nil) == nil, "missing PLAYER stays empty")
        require(PreviewBmsSource.parsedPlayerHeader(" 3 ") == 3, "PLAYER 3 is double")
        require(PreviewBmsSource.parsedPlayerHeader("nope") == nil, "a non-integer PLAYER is not invented")
    }

    private static func testPlayerLayoutAndPackedFormula() {
        let single = PreviewBmsSource.playerLayout(modeHint: "")
        require(single.supportedByUbmSkin && single.playerHeader == 1, "empty hint is beat 7 single")
        require(PreviewBmsSource.playerLayout(modeHint: "beat-5k").playerHeader == 1, "5k is single")
        require(PreviewBmsSource.playerLayout(modeHint: "beat-7k-battle").playerHeader == 2, "7k battle is player 2")
        require(PreviewBmsSource.playerLayout(modeHint: "beat-5k-battle").playerHeader == 2, "5k battle is player 2")
        require(PreviewBmsSource.playerLayout(modeHint: "beat-14k").playerHeader == 3, "14k is double")
        require(PreviewBmsSource.playerLayout(modeHint: "beat-10k").playerHeader == 3, "10k is double")
        let popn = PreviewBmsSource.playerLayout(modeHint: "popn-9k")
        require(!popn.supportedByUbmSkin && popn.playerHeader == nil, "popn is outside the skin")
        let keys = PreviewBmsSource.playerLayout(modeHint: "keyboard-36k")
        require(!keys.supportedByUbmSkin && keys.playerHeader == nil, "36k is not given fake columns")
        let doubledKeyboard = PreviewBmsSource.playerLayout(modeHint: "keyboard-24k-double")
        require(!doubledKeyboard.supportedByUbmSkin && doubledKeyboard.playerHeader == nil, "24k double is not forced to player 3")
        require(PreviewBmsSource.previewPacked(autoSeparate: false, playerHeader: 1), "separation off packs every player")
        require(PreviewBmsSource.previewPacked(autoSeparate: true, playerHeader: 3), "player 3 stays packed")
        require(!PreviewBmsSource.previewPacked(autoSeparate: true, playerHeader: 1), "single with separation is not packed")
        require(!PreviewBmsSource.previewPacked(autoSeparate: true, playerHeader: 2), "battle with separation is not packed")
    }

    private static func testHeadersSurviveWavRewriteWithoutMovingBga() {
        let chart = """
        #TITLE Song
        #ARTIST Ada
        #GENRE Drum
        #PLAYLEVEL 7
        #RANK 3
        #PLAYER 2
        #VOLWAV 80
        #PATH_WAV wavs
        #WAV01 hit.wav
        #BMP01 shot.bmp
        """
        let source = Data(chart.utf8)
        let directory = URL(fileURLWithPath: "/song", isDirectory: true)
        let prepared = PreviewBmsSource.previewDocumentData(data: source, chartDirectory: directory)
        let text = String(decoding: prepared, as: UTF8.self)
        require(text.contains("#TITLE Song") && text.contains("#ARTIST Ada") && text.contains("#GENRE Drum"), "song headers survive the wav rewrite")
        require(text.contains("#PLAYLEVEL 7") && text.contains("#RANK 3") && text.contains("#PLAYER 2") && text.contains("#VOLWAV 80"), "level rank player and volume text stay")
        require(text.contains("#WAV01 /song/wavs/hit.wav"), "only the wav path is rewritten")
        require(text.contains("#BMP01 shot.bmp") && !text.contains("/song/wavs/shot"), "bga name does not follow PATH_WAV")
        require(source == Data(chart.utf8), "the editor bytes stay unchanged")
        let resources = PreviewBmsSource.resources(from: source, chartDirectory: directory)
        require(resources.bgaDirectory?.path == "/song", "bga directory is still the chart directory")
        require(resources.wavDirectory?.path == "/song/wavs", "wav directory follows PATH_WAV")
    }

    private static func testPathWavRelativeAbsoluteAndBgaUntouched() {
        let chart = """
        #PATH_WAV wavs
        #WAV01 my kick.wav
        #BMP01 movie\\shot.bmp
        #TITLE Song
        """
        let directory = URL(fileURLWithPath: "/song", isDirectory: true)
        let source = Data(chart.utf8)
        let resources = PreviewBmsSource.resources(from: source, chartDirectory: directory)
        require(resources.pathWav == "wavs", "path wav value is kept")
        require(resources.wavDirectory?.path == "/song/wavs", "relative path wav joins the chart directory")
        require(resources.bgaDirectory?.path == "/song", "bga directory stays the chart directory")
        require(resources.wavFiles["01"] == "/song/wavs/my kick.wav", "spaced wav name joins under path wav")
        require(resources.bmpFiles["01"] == "movie\\shot.bmp", "bmp name is not joined to path wav")
        let prepared = PreviewBmsSource.previewDocumentData(data: source, chartDirectory: directory)
        let text = String(decoding: prepared, as: UTF8.self)
        require(text.contains("#WAV01 /song/wavs/my kick.wav"), "preview copy rewrites the wav line")
        require(text.contains("#BMP01 movie\\shot.bmp"), "bmp line stays in the preview copy")
        require(!text.contains("/song/wavs/movie"), "path wav is not applied to the bmp")
        require(text.contains("#TITLE Song"), "title stays with the wav table")
        require(source == Data(chart.utf8), "preparing audio data does not edit the source bytes")

        let absolute = Data("#PATH_WAV /library/kicks\n#WAV01 hit.wav\n#BMP01 keep.bmp\n".utf8)
        let elsewhere = URL(fileURLWithPath: "/elsewhere", isDirectory: true)
        let resolved = PreviewBmsSource.resources(from: absolute, chartDirectory: elsewhere)
        require(resolved.wavFiles["01"] == "/library/kicks/hit.wav", "absolute path wav ignores the chart directory")
        require(resolved.wavDirectory?.path == "/library/kicks", "wav directory is the absolute path")
        require(resolved.bgaDirectory?.path == "/elsewhere", "absolute path wav does not move bga")
        require(resolved.bmpFiles["01"] == "keep.bmp", "bmp stays a chart-relative name")
    }

    private static func testPathWavBackslashSpaceAndMissingSeparator() {
        let chart = "#PATH_WAV sub\\dir\n#WAV01 a\\b.wav\n#WAV02 my kick.wav\n"
        let directory = URL(fileURLWithPath: "/song", isDirectory: true)
        let resources = PreviewBmsSource.resources(from: Data(chart.utf8), chartDirectory: directory)
        require(resources.wavFiles["01"] == "/song/sub/dir/a/b.wav", "backslashes in path wav and the file become separators")
        require(resources.wavFiles["02"] == "/song/sub/dir/my kick.wav", "missing trailing separator still joins")
        let spaced = PreviewBmsSource.resources(
            from: Data("#PATH_WAV wav folder\n#WAV01 kick.wav\n".utf8),
            chartDirectory: directory
        )
        require(spaced.wavFiles["01"] == "/song/wav folder/kick.wav", "path wav may contain spaces")
        let drive = PreviewBmsSource.openPath(fileName: "hit.wav", pathWav: "C:\\wavs", chartDirectory: directory)
        require(drive == "C:/wavs/hit.wav", "a drive path is not prefixed with the chart directory")
        require(!drive.contains("/song/"), "drive path wav does not use the chart folder")
    }

    private static func testNoPathWavKeepsChartDirectoryAndBytes() {
        let chart = "#WAV01 kick.wav\n#BMP01 shot.bmp\n#TITLE Plain\n"
        let source = Data(chart.utf8)
        let directory = URL(fileURLWithPath: "/song", isDirectory: true)
        let resources = PreviewBmsSource.resources(from: source, chartDirectory: directory)
        require(resources.pathWav == nil, "no path wav header")
        require(resources.wavDirectory?.path == "/song", "wav falls back to the chart directory")
        require(resources.bgaDirectory?.path == "/song", "bga uses the same chart directory")
        require(resources.wavFiles["01"] == "/song/kick.wav", "plain wav name joins the chart directory")
        require(resources.bmpFiles["01"] == "shot.bmp", "bmp is unchanged")
        let prepared = PreviewBmsSource.previewDocumentData(data: source, chartDirectory: directory)
        require(prepared == source, "no path wav leaves the preview bytes alone")
    }

    private static func testAbsoluteWavIgnoresPathWav() {
        let resources = PreviewBmsSource.resources(
            from: Data("#PATH_WAV /library/kicks\n#WAV01 /other/hit.wav\n".utf8),
            chartDirectory: URL(fileURLWithPath: "/song", isDirectory: true)
        )
        require(resources.wavFiles["01"] == "/other/hit.wav", "an absolute wav file ignores path wav")
    }

    private static func testCacheReplaysUntilReload() {
        var cache = PreviewBmsRandomCache()
        let raw = Data("raw-a".utf8)
        var calls = 0
        let expand: (Data, [Int]) throws -> Data = { data, values in
            calls += 1
            var copy = Data()
            copy.append(data)
            copy.append(Data("|\(values)".utf8))
            return copy
        }
        let first = try! cache.resolve(raw: raw, maxima: [2], injected: [1], expand: expand)
        let second = try! cache.resolve(raw: raw, maxima: [2], injected: [2], expand: expand)
        require(calls == 1, "same raw bytes expand once")
        require(second.reused && second.branch == first.branch, "a new injection does not change the cached branch")
        require(second.branch.values == [1], "stored choice stays 1")
        require(raw == Data("raw-a".utf8), "resolve does not edit the raw bytes")
        cache.reload()
        let third = try! cache.resolve(raw: raw, maxima: [2], injected: [2], expand: expand)
        require(!third.reused && calls == 2, "reload expands again")
        require(third.branch.values == [2], "reload takes the new injection")
        require(third.branch.expanded != first.branch.expanded, "the new choice changes the branch")
        let edited = Data("raw-b".utf8)
        let fourth = try! cache.resolve(raw: edited, maxima: [2], injected: [1], expand: expand)
        require(!fourth.reused && calls == 3, "edited bytes expand again")
        require(fourth.branch.expanded.starts(with: edited), "the new raw bytes are the source")
    }

    private static func testCacheUsesInjectedChoicesWithoutRolling() {
        let values = PreviewBmsRandomCache.choose(maxima: [4, 2], injected: [3, 1])
        require(values == [3, 1], "in-range injection is used as given")
        let missing = PreviewBmsRandomCache.choose(maxima: [], injected: nil)
        require(missing.isEmpty, "no random header produces no choice")
    }

    private static func testDefaultChoiceStaysInRangeAndReplays() throws {
        var cache = PreviewBmsRandomCache()
        var calls = 0
        let first = cache.resolve(raw: Data("once".utf8), maxima: [4, 1], injected: nil) { data, values in
            calls += 1
            require(values.count == 2 && (1...4).contains(values[0]) && values[1] == 1, "default choice is inside 1...max")
            return data
        }
        let second = cache.resolve(raw: Data("once".utf8), maxima: [4, 1], injected: nil) { _, _ in
            calls += 1
            return Data()
        }
        require(calls == 1 && second.reused && second.branch.values == first.branch.values, "the same bytes reuse one roll")
    }

    @MainActor
    private static func testExclusiveBranchesStayApart() throws {
        let raw = Data(exclusive.utf8)
        let editing = try DocumentSession(data: raw, fileURL: URL(fileURLWithPath: "/song/chart.bms"))
        require(editing.hasConditionals, "the editing document still has conditionals")
        require(editing.chartSnapshot.events.isEmpty, "the editing chart stays empty before expansion")
        let before = try editing.currentBytes()
        var cache = PreviewBmsRandomCache()
        let maxima = try randomMaxima(before)
        require(maxima == [2], "one random maximum")
        let first = try cache.resolve(raw: before, maxima: maxima, injected: [1], expand: applyRandom)
        let second = try cache.resolve(raw: before, maxima: maxima, injected: [1], expand: applyRandom)
        require(second.reused && second.branch.expanded == first.branch.expanded, "replay uses the same expanded bytes")
        let branch = try opened(first.branch.expanded, fileURL: editing.fileURL)
        assertBranchA(branch, label: "choice 1")
        let afterExclusive = try editing.currentBytes()
        require(afterExclusive == before, "expanding does not change the editing bytes")
        require(!editing.dirty && editing.hasConditionals, "expanding does not dirty or clear the editing conditionals")
        require(editing.chartSnapshot.events.isEmpty, "the editing model is not replaced by the branch")
    }

    @MainActor
    private static func testReloadChangesBranchWithoutTouchingEdit() throws {
        let raw = Data(exclusive.utf8)
        let editing = try DocumentSession(data: raw)
        let before = try editing.currentBytes()
        var cache = PreviewBmsRandomCache()
        let maxima = try randomMaxima(before)
        let first = try cache.resolve(raw: before, maxima: maxima, injected: [1], expand: applyRandom)
        cache.reload()
        let second = try cache.resolve(raw: before, maxima: maxima, injected: [2], expand: applyRandom)
        require(!second.reused && second.branch.values == [2], "reload stores the new choice")
        require(second.branch.expanded != first.branch.expanded, "the other choice is a different branch")
        let branch = try opened(second.branch.expanded, fileURL: nil)
        assertBranchB(branch, label: "choice 2")
        let afterReload = try editing.currentBytes()
        require(afterReload == before && !editing.dirty, "reload leaves raw bytes and dirty alone")
    }

    @MainActor
    private static func testUnsavedCurrentBytesFeedTheBranch() throws {
        let unsaved = Data(("#COMMENT edited-in-memory\n" + exclusive).utf8)
        let editing = try DocumentSession(data: unsaved, fileURL: URL(fileURLWithPath: "/song/chart.bms"))
        require(!FileManager.default.fileExists(atPath: "/song/chart.bms"), "the chart path is not a file on disk")
        require(!editing.dirty, "loading the unsaved buffer does not mark it dirty")
        let raw = try editing.currentBytes()
        require(String(decoding: raw, as: UTF8.self).contains("edited-in-memory"), "current bytes include the unsaved comment")
        var cache = PreviewBmsRandomCache()
        let branch = try cache.resolve(
            raw: raw,
            maxima: try randomMaxima(raw),
            injected: [1],
            expand: applyRandom
        )
        let expanded = String(decoding: branch.branch.expanded, as: UTF8.self)
        require(expanded.contains("edited-in-memory"), "the branch is expanded from the unsaved current bytes")
        require(expanded.contains("#TITLE A") && !expanded.contains("#TITLE B"), "the unsaved buffer still selects one branch")
        let afterPreview = try editing.currentBytes()
        require(afterPreview == raw && !editing.dirty, "preview expansion does not save or dirty the editing document")
        require(editing.fileURL?.path == "/song/chart.bms", "the editing file location stays")
    }

    @MainActor
    private static func testCompactAliasAndNestedInactive() throws {
        let compact = """
        #RANDOM2
        #IF1
        #TITLE A
        #BPM 100
        #WAV01 kick.wav
        #00011:01
        #ENDIF
        #IF2
        #TITLE B
        #BPM 200
        #WAV01 snare.wav
        #00012:02
        #ENDIF
        """
        let compactRaw = Data(compact.utf8)
        let compactMaxima = try randomMaxima(compactRaw)
        require(compactMaxima == [2], "compact RANDOM2 is one maximum")
        var cache = PreviewBmsRandomCache()
        let kept = try cache.resolve(raw: compactRaw, maxima: compactMaxima, injected: [1], expand: applyRandom)
        let compactSession = try opened(kept.branch.expanded, fileURL: nil)
        require(PreviewBmsSource.metadata(from: kept.branch.expanded).title == "A", "compact choice 1 keeps title A")
        require(tokens(compactSession) == ["01"], "compact choice 1 keeps the kick note \(tokens(compactSession))")
        require(compactSession.timingSnapshot.initialBPMDecimal.contains("100"), "compact choice 1 keeps BPM 100")
        cache.reload()
        let other = try cache.resolve(raw: compactRaw, maxima: compactMaxima, injected: [2], expand: applyRandom)
        let otherSession = try opened(other.branch.expanded, fileURL: nil)
        require(PreviewBmsSource.metadata(from: other.branch.expanded).title == "B", "compact choice 2 keeps title B")
        require(tokens(otherSession) == ["02"], "compact choice 2 keeps the snare note \(tokens(otherSession))")

        let nested = """
        #TITLE Nested
        #WAV01 kick.wav
        #WAV02 snare.wav
        #RANDOM 2
        #IF 1
        #00011:01
        #ELSEIF 2
        #00012:02
        #IF 2
        #00112:02
        #ENDIF
        #ENDIF
        """
        let nestedRaw = Data(nested.utf8)
        cache.reload()
        let outerMiss = try cache.resolve(
            raw: nestedRaw,
            maxima: try randomMaxima(nestedRaw),
            injected: [1],
            expand: applyRandom
        )
        let missed = try opened(outerMiss.branch.expanded, fileURL: nil)
        require(tokens(missed) == ["01"], "outer choice 1 drops the nested snare \(tokens(missed))")
        cache.reload()
        let outerHit = try cache.resolve(
            raw: nestedRaw,
            maxima: try randomMaxima(nestedRaw),
            injected: [2],
            expand: applyRandom
        )
        let hit = try opened(outerHit.branch.expanded, fileURL: nil)
        require(tokens(hit) == ["02", "02"], "outer choice 2 keeps both nested snare notes \(tokens(hit))")
    }

    @MainActor
    private static func testRondamEndIfAndBytesBetweenRandomAndIf() throws {
        let alias = """
        #rondam 2
        #IF 1
        #00011:01
        #END IF
        #IF 2
        #00012:02
        #eNd If
        #00111:01
        #WAV01 kick.wav
        """
        let raw = Data(alias.utf8)
        var cache = PreviewBmsRandomCache()
        let maxima = try randomMaxima(raw)
        require(maxima == [2], "spaced RONDAM is a random maximum")
        let first = try cache.resolve(raw: raw, maxima: maxima, injected: [1], expand: applyRandom)
        let firstSession = try opened(first.branch.expanded, fileURL: nil)
        require(tokens(firstSession) == ["01", "01"], "RONDAM 1 keeps the IF 1 note and the note after END IF")
        cache.reload()
        let second = try cache.resolve(raw: raw, maxima: maxima, injected: [2], expand: applyRandom)
        let secondSession = try opened(second.branch.expanded, fileURL: nil)
        require(tokens(secondSession) == ["02", "01"], "END IF restores the later note on the other branch")

        let between = """
        #RANDOM 2
        #TITLE between
        #IF 1
        #00011:01
        #ENDIF
        #IF 2
        #00012:02
        #ENDIF
        """
        let betweenRaw = Data(between.utf8)
        cache.reload()
        let kept = try cache.resolve(
            raw: betweenRaw,
            maxima: try randomMaxima(betweenRaw),
            injected: [1],
            expand: applyRandom
        )
        let text = String(decoding: kept.branch.expanded, as: UTF8.self)
        require(text.contains("#TITLE between"), "default skip flag keeps the line between RANDOM and IF")
        let betweenSession = try opened(kept.branch.expanded, fileURL: nil)
        require(tokens(betweenSession) == ["01"], "that line stays on the selected branch")
    }

    @MainActor
    private static func testCp932BomSurvivesExpansion() throws {
        var raw = Data([0xEF, 0xBB, 0xBF])
        raw.append(Data("#TITLE ".utf8))
        raw.append(Data([0x82, 0xA0]))
        raw.append(Data("\n#RANDOM 2\n#IF 1\n#00011:01\n#WAV01 a.wav\n#ENDIF\n#IF 2\n#00012:02\n#WAV01 b.wav\n#ENDIF\n".utf8))
        var cache = PreviewBmsRandomCache()
        let branch = try cache.resolve(raw: raw, maxima: try randomMaxima(raw), injected: [1], expand: applyRandom)
        require(branch.branch.expanded.starts(with: [0xEF, 0xBB, 0xBF]), "UTF-8 BOM stays on the expanded bytes")
        require(branch.branch.expanded.contains(Data([0x82, 0xA0])), "CP932 title bytes stay")
        require(!branch.branch.expanded.contains(Data("#00012:02".utf8)), "the other branch is still dropped")
        let song = PreviewBmsSource.metadata(from: branch.branch.expanded, noteCount: 1)
        require(song.title == "あ", "decode reads the title and does not invent one")
        require(song.notes == 1, "note count comes from the caller")
        let prepared = PreviewBmsSource.previewDocumentData(data: branch.branch.expanded, chartDirectory: nil)
        require(prepared == branch.branch.expanded, "no path wav does not re-encode the CP932 bytes")
    }

    @MainActor
    private static func testPathWavComesFromTheSameBranch() throws {
        let chart = """
        #BMP01 keep.bmp
        #RANDOM 2
        #IF 1
        #PATH_WAV /branch-a
        #TITLE A
        #WAV01 kick.wav
        #00011:01
        #ENDIF
        #IF 2
        #PATH_WAV /branch-b
        #TITLE B
        #WAV01 snare.wav
        #00012:02
        #ENDIF
        """
        let raw = Data(chart.utf8)
        let directory = URL(fileURLWithPath: "/song", isDirectory: true)
        var cache = PreviewBmsRandomCache()
        let branch = try cache.resolve(raw: raw, maxima: try randomMaxima(raw), injected: [1], expand: applyRandom)
        let resources = PreviewBmsSource.resources(from: branch.branch.expanded, chartDirectory: directory)
        require(resources.pathWav == "/branch-a", "path wav comes from the selected branch")
        require(resources.wavFiles["01"] == "/branch-a/kick.wav", "wav joins that branch directory")
        require(resources.bmpFiles["01"] == "keep.bmp", "bmp is not sent to the branch wav directory")
        require(resources.bgaDirectory?.path == "/song", "bga stays beside the chart")
        let prepared = PreviewBmsSource.previewDocumentData(data: branch.branch.expanded, chartDirectory: directory)
        let text = String(decoding: prepared, as: UTF8.self)
        require(text.contains("#TITLE A") && !text.contains("#TITLE B"), "prepared audio data keeps the same title")
        require(text.contains("#WAV01 /branch-a/kick.wav"), "prepared wav line uses the same branch")
        require(text.contains("#BMP01 keep.bmp") && !text.contains("/branch-a/keep.bmp"), "prepared bmp is not rewritten")
        require(branch.branch.expanded == Data(branch.branch.expanded), "source expanded bytes stay put")
        let song = PreviewBmsSource.metadata(from: branch.branch.expanded, noteCount: 1)
        require(song.title == "A" && song.notes == 1, "metadata and the note count describe this branch")
    }

    @MainActor
    private static func testPlainEditPreviewReadsCurrentBytes() throws {
        let editing = try DocumentSession(data: Data("#TITLE Old\n#BPM 120\n#WAV01 kick.wav\n#00011:01\n".utf8))
        _ = try editing.replaceMetadata("Edited", for: "TITLE")
        require(editing.dirty, "the title edit is dirty")
        let raw = try editing.currentBytes()
        let maxima = try randomMaxima(raw)
        require(!PreviewBmsSource.shouldExpand(maxima: maxima, hasConditionals: editing.hasConditionals), "a plain chart is not expanded")
        require(PreviewBmsSource.metadata(from: raw).title == "Edited", "preview metadata reads the unsaved title")
        require(!String(decoding: raw, as: UTF8.self).contains("#TITLE Old"), "current bytes no longer have the old title")
        let afterRead = try editing.currentBytes()
        require(afterRead == raw && editing.dirty, "reading the preview source does not save")
        let session = try opened(raw, fileURL: nil)
        require(tokens(session) == ["01"], "the unsaved plain chart still has its note")
    }

    @MainActor
    private static func randomMaxima(_ data: Data) throws -> [Int] {
        try IBMSBmsonBridge.randomMaxima(fromBmsData: data).map(\.intValue)
    }

    @MainActor
    private static func applyRandom(_ data: Data, _ values: [Int]) throws -> Data {
        try IBMSBmsonBridge.applyRandom(
            to: data,
            values: values.map { NSNumber(value: $0) },
            skipBetweenRandomAndIf: false
        )
    }

    @MainActor
    private static func opened(_ data: Data, fileURL: URL?) throws -> DocumentSession {
        let session = try DocumentSession(data: data, fileURL: fileURL)
        require(!session.hasConditionals, "expanded bytes are no longer conditional")
        return session
    }

    @MainActor
    private static func tokens(_ session: DocumentSession) -> [String] {
        session.chartSnapshot.events.map(\.token)
    }

    @MainActor
    private static func assertBranchA(_ session: DocumentSession, label: String) {
        let song = PreviewBmsSource.metadata(from: try! session.currentBytes(), noteCount: tokens(session).count)
        require(song.title == "A" && song.artist == "Aart" && song.genre == "Rock", "\(label) metadata")
        require(song.playLevel == "3" && song.rank == "2" && song.notes == 1, "\(label) level and notes")
        require(tokens(session) == ["01"], "\(label) note token \(tokens(session))")
        require(session.timingSnapshot.initialBPMDecimal.contains("140"), "\(label) bpm \(session.timingSnapshot.initialBPMDecimal)")
        let wav = PreviewBmsSource.resources(from: try! session.currentBytes(), chartDirectory: nil).wavNames["01"]
        require(wav == "a only.wav", "\(label) wav \(wav ?? "")")
        require(song.title != "B", "\(label) does not take the other title")
    }

    @MainActor
    private static func assertBranchB(_ session: DocumentSession, label: String) {
        let bytes = try! session.currentBytes()
        let song = PreviewBmsSource.metadata(from: bytes, noteCount: tokens(session).count)
        require(song.title == "B" && song.artist == "Bart" && song.genre == "Jazz", "\(label) metadata")
        require(song.playLevel == "8" && song.rank == "1", "\(label) level")
        require(tokens(session) == ["02"], "\(label) note token \(tokens(session))")
        require(session.timingSnapshot.initialBPMDecimal.contains("180"), "\(label) bpm \(session.timingSnapshot.initialBPMDecimal)")
        require(PreviewBmsSource.resources(from: bytes, chartDirectory: nil).wavNames["01"] == "b only.wav", "\(label) wav")
    }

    private static let exclusive = """
    #RANDOM 2
    #IF 1
    #TITLE A
    #ARTIST Aart
    #GENRE Rock
    #PLAYLEVEL 3
    #RANK 2
    #BPM 140
    #WAV01 a only.wav
    #00011:01
    #ENDIF
    #IF 2
    #TITLE B
    #ARTIST Bart
    #GENRE Jazz
    #PLAYLEVEL 8
    #RANK 1
    #BPM 180
    #WAV01 b only.wav
    #00012:02
    #ENDIF
    """
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("\(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
