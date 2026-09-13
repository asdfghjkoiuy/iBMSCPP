import Foundation

@main
struct LegacyBeatTests {
    static func main() {
        require(LegacyBeat.add3Zeros(0) == "000" && LegacyBeat.add3Zeros(12) == "012", "Add3Zeros")
        require(LegacyBeat.defaultItems().count == 1000, "LBeat fills 0...999")
        require(LegacyBeat.defaultItems()[0] == "000: 1 ( 4 / 4 )", "Form_Load default row")
        require(LegacyBeat.defaultItems()[999] == "999: 1 ( 4 / 4 )", "last default row")
        require(LegacyBeat.fractionRatio(numerator: 4, denominator: 4) == 1, "4/4 is 1")
        require(LegacyBeat.fractionDisplay(numerator: 3, denominator: 4) == "0.75 ( 3 / 4 ) ",
                "BBeatApply uses N/D in the list text")
        require(LegacyBeat.fractionRatio(numerator: 0, denominator: 4) == nil, "nBeatN minimum is 1")
        require(LegacyBeat.parseValue("1.5") == 1.5 && LegacyBeat.parseValue("0") == nil
                    && LegacyBeat.parseValue("1000") == nil && LegacyBeat.parseValue("x") == nil,
                "tBeatValue allows (0, 1000)")
        require(LegacyBeat.denominator(of: 1) == 1, "GetDenominator(1) is 1")
        require(LegacyBeat.denominator(of: 1.5) == 2, "GetDenominator(1.5) is 2")
        require(LegacyBeat.valueDisplay(1.5) == "1.5 ( 3 / 2 ) ", "BBeatApplyV 1.5")
        require(LegacyBeat.loadedItem(measure: 0, ratio: 2) == "000: 2 ( 2 / 1 ) ",
                "ChartIO load uses GetDenominator")
        require(LegacyBeat.Mode.preserve.rawValue == 0 && LegacyBeat.Mode.scale.rawValue == 3,
                "CBeatPreserve is 0, CBeatScale is 3")
        print("LegacyBeatTests passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
