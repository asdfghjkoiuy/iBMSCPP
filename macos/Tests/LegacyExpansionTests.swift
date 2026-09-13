import Foundation

@main
struct LegacyExpansionTests {
    static func main() {
        require(LegacyExpansion.boxHeight == 245, "TExpansion Designer height")
        require(LegacyExpansion.fieldBanner == "*---------------------- EXPANSION FIELD",
                "SaveBMS expansion banner")
        require(LegacyExpansion.displayText(from: "#FOO\r\n#BAR\r") == "#FOO\n#BAR\n",
                "TExpansion display uses LF")
        require(LegacyExpansion.sameLines("#FOO\r\n#BAR\r\n", "#FOO\n#BAR"),
                "commit compares lines, not newline bytes")
        require(LegacyExpansion.lines(of: "") == [], "empty TExpansion")
        print("LegacyExpansionTests passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
