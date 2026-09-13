import CoreGraphics
import Foundation

/// BmsONE `NoteEditView` copy and Selected Objects field rules.
/// Length and Extra fields only. There is no Continue control here.
enum BmsONESelectedObjectsLayout {
    /// `NoteEditView` size hint. Working value, not a screenshot.
    static let sizeHint = CGSize(width: 200, height: 180)
    static let dockTitle = BmsONEMainWindowLayout.selectedObjectsDockTitle
    static let lengthLabel = "Length"
    static let extraFieldsTitle = "Extra fields"
    static let oneNote = "1 selected note"
    static let multipleValuesPlaceholder = "multiple values"
    static let multipleValuesText = "(multiple values)"
    static let showExtraFieldsKey = "NoteEditView/ShowExtraFields"

    static func notesCount(_ count: Int) -> String {
        "\(count) selected notes"
    }
}

/// Display and parse rules for BmsONE Selected Objects. Not a BMS inspector.
enum BmsonSelectedObjects {
    struct Note: Equatable {
        var length: Int64
        var extraObjectJSON: String
    }

    struct Display: Equatable {
        var message: String
        var lengthEnabled: Bool
        var lengthText: String
        var lengthPlaceholder: String
        var extraText: String
    }

    static func display(notes: [Note]) -> Display {
        if notes.isEmpty {
            return Display(
                message: "",
                lengthEnabled: false,
                lengthText: "",
                lengthPlaceholder: "",
                extraText: ""
            )
        }
        let message = notes.count == 1
            ? BmsONESelectedObjectsLayout.oneNote
            : BmsONESelectedObjectsLayout.notesCount(notes.count)
        let lengths = Set(notes.map(\.length))
        let extras = Set(notes.map { formatExtraFields(objectJSON: $0.extraObjectJSON) })
        let lengthUniform = lengths.count == 1
        let extraUniform = extras.count == 1
        return Display(
            message: message,
            lengthEnabled: true,
            lengthText: lengthUniform ? "\(lengths.first!)" : "",
            lengthPlaceholder: lengthUniform ? "" : BmsONESelectedObjectsLayout.multipleValuesPlaceholder,
            extraText: extraUniform
                ? (extras.first ?? "")
                : BmsONESelectedObjectsLayout.multipleValuesText
        )
    }

    /// `QString::toInt` then `value >= 0`. Overflow and leftover text fail.
    static func parseLength(_ text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasPrefix("+") ? String(trimmed.dropFirst()) : trimmed
        guard let value = Int32(normalized), value >= 0 else { return nil }
        return Int64(value)
    }

    static func isUnchangedMultipleValues(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            == BmsONESelectedObjectsLayout.multipleValuesText
    }

    /// Trim, drop one trailing comma, wrap `{}`. Nil if the result is not a JSON object.
    static func preparedExtraObjectJSON(_ text: String) -> String? {
        if isUnchangedMultipleValues(text) {
            return nil
        }
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasSuffix(",") {
            json.removeLast()
            json = json.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let wrapped = "{\(json)}"
        guard let data = wrapped.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any]
        else {
            return nil
        }
        return wrapped
    }

    static func formatExtraFields(objectJSON: String) -> String {
        guard let data = objectJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ""
        }
        return object.keys.sorted().map { key in
            "\(jsonString(key)): \(compactJSON(object[key] ?? NSNull()))"
        }.joined(separator: ",\n")
    }

    static func loadShowExtraFields(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: BmsONESelectedObjectsLayout.showExtraFieldsKey) as? Bool ?? false
    }

    static func storeShowExtraFields(_ value: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: BmsONESelectedObjectsLayout.showExtraFieldsKey)
    }

    private static func jsonString(_ text: String) -> String {
        compactJSON(text)
    }

    private static func compactJSON(_ value: Any) -> String {
        if value is NSNull {
            return "null"
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if let text = value as? String {
            let data = try? JSONSerialization.data(
                withJSONObject: [text],
                options: [.withoutEscapingSlashes]
            )
            let wrapped = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
            if wrapped.count >= 2 {
                return String(wrapped.dropFirst().dropLast())
            }
            return "\"\""
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(
               withJSONObject: value,
               options: [.sortedKeys, .withoutEscapingSlashes]
           ),
           let text = String(data: data, encoding: .utf8)
        {
            return text
        }
        return "null"
    }
}
