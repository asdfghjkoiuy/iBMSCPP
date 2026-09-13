import Foundation

@main
struct LegacyRecentTests {
    static func main() {
        testInsertNewPathShiftsAndDropsFifth()
        testInsertExistingMovesToFront()
        testFileNameUsesLastSlash()
        testEmptySlotTitleAndMissingMessage()
        testOpenKinds()
        testPersistencePadsFiveSlots()
        print("LegacyRecentTests passed")
    }

    /// `NewRecent`：新路径整表后移，丢掉原来的第 5 个。
    private static func testInsertNewPathShiftsAndDropsFifth() {
        let first = LegacyRecent.insert("/a.bms", into: LegacyRecent.emptySlots())
        require(first == ["/a.bms", "", "", "", ""], "first path occupies slot 0")

        let second = LegacyRecent.insert("/b.bme", into: first)
        require(second == ["/b.bme", "/a.bms", "", "", ""], "new path shifts the table")

        let full = LegacyRecent.insert(
            "/f.pms",
            into: ["/a.bms", "/b.bms", "/c.bms", "/d.bms", "/e.bms"]
        )
        require(full == ["/f.pms", "/a.bms", "/b.bms", "/c.bms", "/d.bms"], "slot 4 is dropped")
    }

    /// `NewRecent`：已有路径从该下标往前挪，放到 `[0]`。
    private static func testInsertExistingMovesToFront() {
        let moved = LegacyRecent.insert(
            "/a.bms",
            into: ["/c.bms", "/b.bms", "/a.bms", "/d.bms", ""]
        )
        require(moved == ["/a.bms", "/c.bms", "/b.bms", "/d.bms", ""], "existing path moves to front")

        let alreadyFirst = LegacyRecent.insert(
            "/a.bms",
            into: ["/a.bms", "/b.bms", "", "", ""]
        )
        require(alreadyFirst == ["/a.bms", "/b.bms", "", "", ""], "slot 0 stays put")
    }

    /// `GetFileName`：取最后一个 `/` 或 `\` 后面的字。
    private static func testFileNameUsesLastSlash() {
        require(LegacyRecent.fileName("/Users/me/song.bms") == "song.bms", "posix basename")
        require(LegacyRecent.fileName("C:\\charts\\song.bme") == "song.bme", "windows basename")
        require(LegacyRecent.fileName("foo/bar\\baz.ibmsc") == "baz.ibmsc", "later backslash wins")
        require(LegacyRecent.fileName("song.bms") == "song.bms", "no separator keeps the string")
    }

    /// `SetRecent` 空槽是 `"<" & Strings.None & ">"`；缺文件文案来自 `Strings.Messages.CannotFind`。
    private static func testEmptySlotTitleAndMissingMessage() {
        require(LegacyRecent.menuTitle("") == "<None>", "empty slot title")
        require(LegacyRecent.menuTitle("   ") == "<None>", "whitespace-only slot title")
        require(!LegacyRecent.isEnabled(""), "empty slot is disabled")
        require(LegacyRecent.isEnabled(" /tmp/a.bms "), "non-empty slot is enabled")
        require(LegacyRecent.menuTitle(" /tmp/a.bms ") == "a.bms", "title uses trimmed basename")
        require(LegacyRecent.tooltip(" /tmp/a.bms ") == "/tmp/a.bms", "tooltip is trimmed path")
        require(
            LegacyRecent.missingFileMessage("gone.bms") == "Cannot find file gone.bms.",
            "missing-file message keeps the stored path"
        )
    }

    /// `OpenRecent` 的 `UCase(Path.GetExtension)`。`.bmson` 走同一主窗。
    private static func testOpenKinds() {
        require(LegacyRecent.kind(path: "/x.bms") == .bms, "bms")
        require(LegacyRecent.kind(path: "/x.BME") == .bms, "bme")
        require(LegacyRecent.kind(path: "/x.bml") == .bms, "bml")
        require(LegacyRecent.kind(path: "/x.pms") == .bms, "pms")
        require(LegacyRecent.kind(path: "/x.txt") == .bms, "txt")
        require(LegacyRecent.kind(path: "/x.ibmsc") == .ibmsc, "ibmsc")
        require(LegacyRecent.kind(path: "/x.BMSON") == .bmson, "bmson")
        require(LegacyRecent.kind(path: "/x.sm") == .unsupported, "sm is not opened")
        require(LegacyRecent.kind(path: "/x.ogg") == .unsupported, "other extensions are ignored")
    }

    /// 对照 `EditorPersistent` `Recent0`–`Recent4`：永远五槽。
    private static func testPersistencePadsFiveSlots() {
        let suite = "IBMSNative.Recent.Tests"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fputs("could not create UserDefaults suite\n", stderr)
            exit(EXIT_FAILURE)
        }
        defaults.removePersistentDomain(forName: suite)
        LegacyRecent.save(["/one.bms", "/two.bms"], to: defaults)
        let loaded = LegacyRecent.load(from: defaults)
        require(loaded == ["/one.bms", "/two.bms", "", "", ""], "saved list is padded to five")
        defaults.removePersistentDomain(forName: suite)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
