#import "IBMSDocumentBridge.h"

#include <ibms/bms_document.hpp>

#include <algorithm>
#include <cstdint>
#include <exception>
#include <limits>
#include <memory>
#include <optional>
#include <string>
#include <vector>

NSErrorDomain const IBMSDocumentBridgeErrorDomain = @"org.ibmsc.native.document-bridge";

NSUInteger IBMSNSStringEncodingEucKR(void) {
    return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingEUC_KR);
}

namespace {

NSError *makeError(IBMSDocumentBridgeErrorCode code, NSString *description) {
    return [NSError errorWithDomain:IBMSDocumentBridgeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

void assignError(NSError * _Nullable * _Nullable error,
                 IBMSDocumentBridgeErrorCode code,
                 NSString *description) {
    if (error != nullptr) {
        *error = makeError(code, description);
    }
}

std::optional<std::string> rawKey(NSString *key, NSError * _Nullable * _Nullable error) {
    NSData *keyData = [key dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO];
    if (keyData == nil || keyData.length == 0) {
        assignError(error, IBMSDocumentBridgeErrorCodeInvalidKey, @"Metadata keys must be nonempty ASCII text.");
        return std::nullopt;
    }
    return std::string(static_cast<const char *>(keyData.bytes), keyData.length);
}

std::string rawBytes(NSData *data) {
    if (data.length == 0) {
        return {};
    }
    return std::string(static_cast<const char *>(data.bytes), data.length);
}

std::optional<std::string> utf8String(NSString *value, NSError * _Nullable * _Nullable error, NSString *field) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
    if (data == nil) {
        assignError(error, IBMSDocumentBridgeErrorCodeInvalidKey, [field stringByAppendingString:@" must be valid UTF-8 text."]);
        return std::nullopt;
    }
    return rawBytes(data);
}

NSString *displayString(const std::string& value) {
    return [[NSString alloc] initWithBytes:value.data() length:value.size() encoding:NSUTF8StringEncoding] ?: @"<unreadable>";
}

double displayBeat(const ibms::BeatPosition& value) {
    return static_cast<double>(value.numerator()) / static_cast<double>(value.denominator());
}

std::string unsignedDecimal(unsigned __int128 value) {
    if (value == 0) {
        return "0";
    }
    std::string digits;
    while (value != 0) {
        digits.push_back(static_cast<char>('0' + value % 10));
        value /= 10;
    }
    std::reverse(digits.begin(), digits.end());
    return digits;
}

NSString *exactDecimal(const ibms::BeatPosition& value) {
    const bool negative = value.numerator() < 0;
    unsigned __int128 numerator = negative
        ? static_cast<unsigned __int128>(-(value.numerator() + 1)) + 1
        : static_cast<unsigned __int128>(value.numerator());
    std::uint64_t denominator = static_cast<std::uint64_t>(value.denominator());
    unsigned int twos = 0;
    unsigned int fives = 0;
    while (denominator % 2 == 0) {
        denominator /= 2;
        ++twos;
    }
    while (denominator % 5 == 0) {
        denominator /= 5;
        ++fives;
    }
    if (denominator != 1) {
        return [NSString stringWithFormat:@"%lld/%lld", value.numerator(), value.denominator()];
    }

    constexpr unsigned __int128 maximum = ~static_cast<unsigned __int128>(0);
    const unsigned int fractionalDigits = std::max(twos, fives);
    for (unsigned int count = twos; count < fractionalDigits; ++count) {
        if (numerator > maximum / 2) {
            return [NSString stringWithFormat:@"%lld/%lld", value.numerator(), value.denominator()];
        }
        numerator *= 2;
    }
    for (unsigned int count = fives; count < fractionalDigits; ++count) {
        if (numerator > maximum / 5) {
            return [NSString stringWithFormat:@"%lld/%lld", value.numerator(), value.denominator()];
        }
        numerator *= 5;
    }

    std::string text = unsignedDecimal(numerator);
    if (fractionalDigits != 0) {
        if (text.size() <= fractionalDigits) {
            text.insert(0, fractionalDigits + 1 - text.size(), '0');
        }
        text.insert(text.size() - fractionalDigits, 1, '.');
    }
    if (negative) {
        text.insert(text.begin(), '-');
    }
    return [[NSString alloc] initWithBytes:text.data() length:text.size() encoding:NSASCIIStringEncoding];
}

NSString *kindName(ibms::BmsEventKind kind) {
    switch (kind) {
        case ibms::BmsEventKind::normal_note: return @"normalNote";
        case ibms::BmsEventKind::hidden_note: return @"hiddenNote";
        case ibms::BmsEventKind::long_note: return @"longNote";
        case ibms::BmsEventKind::mine: return @"mine";
        case ibms::BmsEventKind::bgm: return @"bgm";
        case ibms::BmsEventKind::bga: return @"bga";
        case ibms::BmsEventKind::bpm: return @"bpm";
        case ibms::BmsEventKind::extended_bpm: return @"extendedBpm";
        case ibms::BmsEventKind::stop: return @"stop";
        case ibms::BmsEventKind::scroll: return @"scroll";
        case ibms::BmsEventKind::unknown: return @"unknown";
    }
}

std::optional<ibms::BeatPosition> gridFraction(
    const ibms::BmsChart& chart, NSInteger measure, NSInteger slot, NSInteger division,
    NSError * _Nullable * _Nullable error) {
    constexpr NSInteger validDivisions[] = {4, 8, 12, 16, 24, 32, 48, 64};
    const bool validDivision = std::find(
        std::begin(validDivisions), std::end(validDivisions), division) != std::end(validDivisions);
    const bool validMeasure = measure >= std::numeric_limits<int>::min()
        && measure <= std::numeric_limits<int>::max();
    const bool validSlot = slot >= 0
        && slot <= std::numeric_limits<ibms::BeatPosition::rep>::max() / 4;
    if (!validSlot || !validDivision || !validMeasure) {
        assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid, @"The selected grid position is invalid.");
        return std::nullopt;
    }
    const auto found = std::find_if(chart.measures.begin(), chart.measures.end(), [measure](const ibms::BmsMeasure& item) { return item.measure == measure; });
    if (found == chart.measures.end()) {
        assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid, @"The selected measure is unavailable.");
        return std::nullopt;
    }
    const ibms::BeatPosition offset(slot * 4, division);
    if (offset >= found->length) {
        assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid, @"The selected grid position is outside this measure.");
        return std::nullopt;
    }
    return offset / found->length;
}

std::optional<ibms::BeatPosition> timingFraction(
    NSInteger measure, int64_t numerator, int64_t denominator,
    NSError * _Nullable * _Nullable error) {
    if (measure < 0 || measure > 999 || denominator <= 0 || numerator < 0 || numerator >= denominator) {
        assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid,
                    @"The selected timing position is outside the available measure.");
        return std::nullopt;
    }
    try {
        return ibms::BeatPosition(numerator, denominator);
    } catch (const std::exception&) {
        assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid, @"The selected timing fraction is invalid.");
        return std::nullopt;
    }
}

std::optional<ibms::BmsLongNotePosition> longNotePosition(
    NSInteger measure, int64_t numerator, int64_t denominator,
    NSError * _Nullable * _Nullable error) {
    if (measure < std::numeric_limits<int>::min() || measure > std::numeric_limits<int>::max()
        || denominator <= 0 || numerator < 0 || numerator >= denominator) {
        assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid,
                    @"The selected long-note position is invalid.");
        return std::nullopt;
    }
    try {
        return ibms::BmsLongNotePosition{
            static_cast<int>(measure), ibms::BeatPosition(numerator, denominator)};
    } catch (const std::exception&) {
        assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid,
                    @"The selected long-note fraction is invalid.");
        return std::nullopt;
    }
}

std::optional<ibms::BmsLongNotePosition> longNoteGridPosition(
    const ibms::BmsChart& chart, NSInteger measure, NSInteger slot, NSInteger division,
    NSError * _Nullable * _Nullable error) {
    const auto fraction = gridFraction(chart, measure, slot, division, error);
    if (!fraction) {
        return std::nullopt;
    }
    return ibms::BmsLongNotePosition{static_cast<int>(measure), *fraction};
}

const ibms::BmsLongNote *findLongNote(
    const ibms::BmsLongNotes& notes, const std::string& channel,
    const ibms::BmsLongNotePosition& start) {
    const auto found = std::find_if(notes.notes.begin(), notes.notes.end(),
        [&channel, &start](const ibms::BmsLongNote& note) {
            return note.channel == channel && note.start.position.measure == start.measure
                && note.start.position.fraction == start.fraction;
        });
    return found == notes.notes.end() ? nullptr : &*found;
}

std::optional<ibms::BeatPosition> absoluteBeat(
    const ibms::BmsChart& chart, const ibms::BmsLongNotePosition& position,
    NSError * _Nullable * _Nullable error) {
    const auto measure = std::find_if(chart.measures.begin(), chart.measures.end(),
        [&position](const ibms::BmsMeasure& item) { return item.measure == position.measure; });
    if (measure == chart.measures.end()) {
        assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid,
                    @"The selected measure is unavailable.");
        return std::nullopt;
    }
    return measure->start + measure->length * position.fraction;
}

std::optional<ibms::BmsLongNotePosition> positionForBeat(
    const ibms::BmsChart& chart, const ibms::BeatPosition& beat,
    NSError * _Nullable * _Nullable error) {
    const auto measure = std::find_if(chart.measures.begin(), chart.measures.end(),
        [&beat](const ibms::BmsMeasure& item) {
            return beat >= item.start && beat < item.start + item.length;
        });
    if (measure == chart.measures.end()) {
        assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid,
                    @"Moving this long note would place its end outside the available measures.");
        return std::nullopt;
    }
    return ibms::BmsLongNotePosition{measure->measure, (beat - measure->start) / measure->length};
}

}  // namespace

@implementation IBMSChartEvent {
@public
    NSInteger _measure;
    NSString *_channel;
    NSString *_token;
    int64_t _fractionNumerator;
    int64_t _fractionDenominator;
    double _beat;
    NSString *_kind;
    NSUInteger _sourceLine;
    NSInteger _bgmLane;
}
- (NSInteger)measure { return _measure; }
- (NSString *)channel { return _channel; }
- (NSString *)token { return _token; }
- (int64_t)fractionNumerator { return _fractionNumerator; }
- (int64_t)fractionDenominator { return _fractionDenominator; }
- (double)beat { return _beat; }
- (NSString *)kind { return _kind; }
- (NSUInteger)sourceLine { return _sourceLine; }
- (NSInteger)bgmLane { return _bgmLane; }
@end

@implementation IBMSChartMeasure {
@public
    NSInteger _measure;
    double _start;
    double _length;
}
- (NSInteger)measure { return _measure; }
- (double)start { return _start; }
- (double)length { return _length; }
@end

@implementation IBMSChartSnapshot {
@public
    NSArray<IBMSChartEvent *> *_events;
    NSArray<IBMSChartMeasure *> *_measures;
    NSArray<IBMSChartDiagnostic *> *_diagnostics;
    BOOL _editable;
    NSString *_editingReason;
}
- (NSArray<IBMSChartEvent *> *)events { return _events; }
- (NSArray<IBMSChartMeasure *> *)measures { return _measures; }
- (NSArray<IBMSChartDiagnostic *> *)diagnostics { return _diagnostics; }
- (BOOL)isEditable { return _editable; }
- (NSString *)editingReason { return _editingReason; }
@end

@implementation IBMSChartDiagnostic {
@public
    NSUInteger _sourceLine;
    NSString *_message;
}
- (NSUInteger)sourceLine { return _sourceLine; }
- (NSString *)message { return _message; }
@end

@implementation IBMSLongNoteEndpoint {
@public
    NSInteger _measure;
    int64_t _fractionNumerator;
    int64_t _fractionDenominator;
    double _beat;
    NSString *_token;
    NSUInteger _sourceLine;
}
- (NSInteger)measure { return _measure; }
- (int64_t)fractionNumerator { return _fractionNumerator; }
- (int64_t)fractionDenominator { return _fractionDenominator; }
- (double)beat { return _beat; }
- (NSString *)token { return _token; }
- (NSUInteger)sourceLine { return _sourceLine; }
@end

@implementation IBMSLongNote {
@public
    NSString *_channel;
    IBMSLongNoteEndpoint *_start;
    IBMSLongNoteEndpoint *_end;
    NSString *_encoding;
}
- (NSString *)channel { return _channel; }
- (IBMSLongNoteEndpoint *)start { return _start; }
- (IBMSLongNoteEndpoint *)end { return _end; }
- (NSString *)encoding { return _encoding; }
@end

@implementation IBMSLongNoteDiagnostic {
@public
    NSUInteger _sourceLine;
    NSString *_message;
}
- (NSUInteger)sourceLine { return _sourceLine; }
- (NSString *)message { return _message; }
@end

@implementation IBMSLongNoteSnapshot {
@public
    NSArray<IBMSLongNote *> *_notes;
    NSArray<IBMSLongNoteDiagnostic *> *_diagnostics;
    NSString *_lnobjToken;
    BOOL _editable;
    NSString *_editingReason;
}
- (NSArray<IBMSLongNote *> *)notes { return _notes; }
- (NSArray<IBMSLongNoteDiagnostic *> *)diagnostics { return _diagnostics; }
- (NSString *)lnobjToken { return _lnobjToken; }
- (BOOL)isEditable { return _editable; }
- (NSString *)editingReason { return _editingReason; }
@end

@implementation IBMSTimingEvent {
@public
    NSInteger _measure;
    int64_t _fractionNumerator;
    int64_t _fractionDenominator;
    int64_t _beatNumerator;
    int64_t _beatDenominator;
    NSString *_valueDecimal;
    NSString *_kind;
    NSString *_channel;
    NSString *_token;
    NSUInteger _sourceLine;
    BOOL _hasTime;
    double _secondsBeforeStop;
    double _secondsAfterStop;
}
- (NSInteger)measure { return _measure; }
- (int64_t)fractionNumerator { return _fractionNumerator; }
- (int64_t)fractionDenominator { return _fractionDenominator; }
- (int64_t)beatNumerator { return _beatNumerator; }
- (int64_t)beatDenominator { return _beatDenominator; }
- (NSString *)valueDecimal { return _valueDecimal; }
- (NSString *)kind { return _kind; }
- (NSString *)channel { return _channel; }
- (NSString *)token { return _token; }
- (NSUInteger)sourceLine { return _sourceLine; }
- (BOOL)hasTime { return _hasTime; }
- (double)secondsBeforeStop { return _secondsBeforeStop; }
- (double)secondsAfterStop { return _secondsAfterStop; }
@end

@implementation IBMSTimingMeasure {
@public
    NSInteger _measure;
    NSString *_ratioDecimal;
}
- (NSInteger)measure { return _measure; }
- (NSString *)ratioDecimal { return _ratioDecimal; }
@end

@implementation IBMSTimingDiagnostic {
@public
    NSUInteger _sourceLine;
    NSString *_message;
}
- (NSUInteger)sourceLine { return _sourceLine; }
- (NSString *)message { return _message; }
@end

@implementation IBMSTimingSnapshot {
@public
    NSString *_initialBPMDecimal;
    NSArray<IBMSTimingEvent *> *_events;
    NSArray<IBMSTimingMeasure *> *_measures;
    NSArray<IBMSTimingDiagnostic *> *_diagnostics;
    BOOL _available;
    NSString *_unavailableReason;
}
- (NSString *)initialBPMDecimal { return _initialBPMDecimal; }
- (NSArray<IBMSTimingEvent *> *)events { return _events; }
- (NSArray<IBMSTimingMeasure *> *)measures { return _measures; }
- (NSArray<IBMSTimingDiagnostic *> *)diagnostics { return _diagnostics; }
- (BOOL)isAvailable { return _available; }
- (NSString *)unavailableReason { return _unavailableReason; }
@end

@implementation IBMSSaveBmsReport {
@public
    NSData *_data;
    BOOL _overlapping;
    NSInteger _bpmCount;
    NSInteger _stopCount;
    NSInteger _scrollCount;
}
- (NSData *)data { return _data; }
- (BOOL)overlapping { return _overlapping; }
- (NSInteger)bpmCount { return _bpmCount; }
- (NSInteger)stopCount { return _stopCount; }
- (NSInteger)scrollCount { return _scrollCount; }
@end

@implementation IBMSDocumentBridge {
    std::unique_ptr<ibms::BmsDocument> _document;
}

+ (void)setIndexedTimingRadixBpm:(BOOL)bpmX1296 stop:(BOOL)stopX1296 {
    ibms::IndexedTimingRadix::set(static_cast<bool>(bpmX1296), static_cast<bool>(stopX1296));
}

- (nullable instancetype)initWithData:(NSData *)data error:(NSError * _Nullable * _Nullable)error {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    try {
        std::string bytes = rawBytes(data);
        _document = std::make_unique<ibms::BmsDocument>(ibms::BmsDocument::from_bytes(std::move(bytes)));
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The BMS document could not be loaded.");
        return nil;
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The BMS document could not be loaded.");
        return nil;
    }
    return self;
}

- (nullable NSData *)serializedDataWithError:(NSError * _Nullable * _Nullable)error {
    try {
        const std::string bytes = _document->serialize();
        return [NSData dataWithBytes:bytes.data() length:bytes.size()];
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The BMS document could not be saved.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The BMS document could not be saved.");
    }
    return nil;
}

- (nullable NSData *)saveBmsDataWithNTInput:(BOOL)ntInput
                                      error:(NSError * _Nullable * _Nullable)error {
    return [self saveBmsReportWithNTInput:ntInput gridLimit:1.0 error:error].data;
}

- (nullable IBMSSaveBmsReport *)saveBmsReportWithNTInput:(BOOL)ntInput
                                              gridLimit:(double)gridLimit
                                                  error:(NSError * _Nullable * _Nullable)error {
    try {
        const ibms::BmsSaveReport report = _document->save_bms_report(static_cast<bool>(ntInput), gridLimit);
        IBMSSaveBmsReport *result = [IBMSSaveBmsReport new];
        result->_data = [NSData dataWithBytes:report.text.data() length:report.text.size()];
        result->_overlapping = report.overlapping ? YES : NO;
        result->_bpmCount = static_cast<NSInteger>(report.bpm_count);
        result->_stopCount = static_cast<NSInteger>(report.stop_count);
        result->_scrollCount = static_cast<NSInteger>(report.scroll_count);
        return result;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The BMS document could not be saved.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The BMS document could not be saved.");
    }
    return nil;
}

- (NSData *)headerDataForKey:(NSString *)key error:(NSError * _Nullable * _Nullable)error {
    try {
        const std::optional<std::string> raw = rawKey(key, error);
        if (!raw.has_value()) {
            return [NSData data];
        }
        const std::optional<std::string> value = _document->header(*raw);
        if (!value.has_value()) {
            return [NSData data];
        }
        return [NSData dataWithBytes:value->data() length:value->size()];
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The metadata could not be read.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The metadata could not be read.");
    }
    return [NSData data];
}

- (BOOL)setHeaderData:(NSData *)data forKey:(NSString *)key error:(NSError * _Nullable * _Nullable)error {
    try {
        const std::optional<std::string> raw = rawKey(key, error);
        if (!raw.has_value()) {
            return NO;
        }
        const std::string value = rawBytes(data);
        _document->set_header(*raw, value);
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The metadata could not be changed.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The metadata could not be changed.");
    }
    return NO;
}

- (nullable NSData *)expansionDataWithError:(NSError * _Nullable * _Nullable)error {
    try {
        const std::string text = _document->expansion();
        return [NSData dataWithBytes:text.data() length:text.size()];
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The expansion field could not be read.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The expansion field could not be read.");
    }
    return nil;
}

- (BOOL)setExpansionData:(NSData *)data error:(NSError * _Nullable * _Nullable)error {
    try {
        _document->set_expansion(rawBytes(data));
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The expansion field could not be changed.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The expansion field could not be changed.");
    }
    return NO;
}

- (nullable IBMSChartSnapshot *)chartSnapshotWithError:(NSError * _Nullable * _Nullable)error {
    try {
        const ibms::BmsChart& chart = _document->chart();
        IBMSChartSnapshot *snapshot = [IBMSChartSnapshot new];
        NSMutableArray<IBMSChartEvent *> *events = [NSMutableArray arrayWithCapacity:chart.events.size()];
        for (const ibms::BmsEvent& source : chart.events) {
            IBMSChartEvent *event = [IBMSChartEvent new];
            event->_measure = source.measure;
            event->_channel = displayString(source.channel);
            event->_token = displayString(source.token);
            event->_fractionNumerator = source.fraction.numerator();
            event->_fractionDenominator = source.fraction.denominator();
            event->_beat = displayBeat(source.beat);
            event->_kind = kindName(source.kind);
            event->_sourceLine = source.source_line;
            event->_bgmLane = source.bgm_lane;
            [events addObject:event];
        }
        NSMutableArray<IBMSChartMeasure *> *measures = [NSMutableArray arrayWithCapacity:chart.measures.size()];
        for (const ibms::BmsMeasure& source : chart.measures) {
            IBMSChartMeasure *measure = [IBMSChartMeasure new];
            measure->_measure = source.measure;
            measure->_start = displayBeat(source.start);
            measure->_length = displayBeat(source.length);
            [measures addObject:measure];
        }
        NSMutableArray<IBMSChartDiagnostic *> *diagnostics = [NSMutableArray arrayWithCapacity:chart.diagnostics.size()];
        for (const ibms::BmsDiagnostic& diagnostic : chart.diagnostics) {
            IBMSChartDiagnostic *item = [IBMSChartDiagnostic new];
            item->_sourceLine = diagnostic.source_line;
            item->_message = displayString(diagnostic.message);
            [diagnostics addObject:item];
        }
        snapshot->_events = [events copy];
        snapshot->_measures = [measures copy];
        snapshot->_diagnostics = [diagnostics copy];
        snapshot->_editable = chart.editable;
        snapshot->_editingReason = displayString(chart.editing_reason);
        return snapshot;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, [NSString stringWithUTF8String:exception.what()] ?: @"The chart could not be read.");
    } catch (...) { assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The chart could not be read."); }
    return nil;
}

- (nullable IBMSLongNoteSnapshot *)longNoteSnapshotWithError:(NSError * _Nullable * _Nullable)error {
    try {
        const ibms::BmsLongNotes& longNotes = _document->long_notes();
        IBMSLongNoteSnapshot *snapshot = [IBMSLongNoteSnapshot new];
        NSMutableArray<IBMSLongNote *> *notes = [NSMutableArray arrayWithCapacity:longNotes.notes.size()];
        for (const ibms::BmsLongNote& source : longNotes.notes) {
            auto makeEndpoint = [](const ibms::BmsLongNoteEndpoint& endpoint) {
                IBMSLongNoteEndpoint *item = [IBMSLongNoteEndpoint new];
                item->_measure = endpoint.position.measure;
                item->_fractionNumerator = endpoint.position.fraction.numerator();
                item->_fractionDenominator = endpoint.position.fraction.denominator();
                item->_beat = displayBeat(endpoint.beat);
                item->_token = displayString(endpoint.token);
                item->_sourceLine = endpoint.source_line;
                return item;
            };
            IBMSLongNote *item = [IBMSLongNote new];
            item->_channel = displayString(source.channel);
            item->_start = makeEndpoint(source.start);
            item->_end = makeEndpoint(source.end);
            item->_encoding = source.encoding == ibms::BmsLongNoteEncoding::lnobj
                ? @"lnobj" : @"longChannel";
            [notes addObject:item];
        }
        NSMutableArray<IBMSLongNoteDiagnostic *> *diagnostics =
            [NSMutableArray arrayWithCapacity:longNotes.diagnostics.size()];
        for (const ibms::BmsLongNoteDiagnostic& source : longNotes.diagnostics) {
            IBMSLongNoteDiagnostic *item = [IBMSLongNoteDiagnostic new];
            item->_sourceLine = source.source_line;
            item->_message = displayString(source.message);
            [diagnostics addObject:item];
        }
        snapshot->_notes = [notes copy];
        snapshot->_diagnostics = [diagnostics copy];
        snapshot->_lnobjToken = displayString(longNotes.lnobj_token);
        snapshot->_editable = longNotes.editable;
        snapshot->_editingReason = displayString(longNotes.editing_reason);
        return snapshot;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"Long notes could not be read.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"Long notes could not be read.");
    }
    return nil;
}

- (nullable IBMSTimingSnapshot *)timingSnapshotWithError:(NSError * _Nullable * _Nullable)error {
    try {
        const ibms::BmsTiming& timing = _document->timing();
        const ibms::BmsChart& chart = _document->chart();
        IBMSTimingSnapshot *snapshot = [IBMSTimingSnapshot new];
        snapshot->_initialBPMDecimal = exactDecimal(timing.initial_bpm);

        NSMutableArray<IBMSTimingMeasure *> *measures = [NSMutableArray arrayWithCapacity:chart.measures.size()];
        for (const ibms::BmsMeasure& measure : chart.measures) {
            IBMSTimingMeasure *item = [IBMSTimingMeasure new];
            item->_measure = measure.measure;
            item->_ratioDecimal = exactDecimal(measure.length / ibms::BeatPosition{4});
            [measures addObject:item];
        }

        NSMutableArray<IBMSTimingEvent *> *events = [NSMutableArray arrayWithCapacity:timing.events.size()];
        for (const ibms::BmsTimingEvent& source : timing.events) {
            IBMSTimingEvent *item = [IBMSTimingEvent new];
            item->_measure = source.measure;
            item->_fractionNumerator = source.fraction.numerator();
            item->_fractionDenominator = source.fraction.denominator();
            item->_beatNumerator = source.beat.numerator();
            item->_beatDenominator = source.beat.denominator();
            item->_valueDecimal = exactDecimal(source.value);
            item->_kind = source.kind == ibms::BmsTimingEventKind::stop ? @"stop" : @"bpm";
            item->_channel = displayString(source.channel);
            item->_token = displayString(source.token);
            item->_sourceLine = source.source_line;

            const auto point = std::lower_bound(
                timing.points.begin(), timing.points.end(), source.beat,
                [](const ibms::BmsTimingPoint& candidate, const ibms::BeatPosition& beat) {
                    return candidate.beat < beat;
                });
            if (timing.available && point != timing.points.end() && point->beat == source.beat) {
                item->_hasTime = YES;
                item->_secondsBeforeStop = point->seconds_before_stop;
                item->_secondsAfterStop = point->seconds_after_stop;
            }
            [events addObject:item];
        }

        NSMutableArray<IBMSTimingDiagnostic *> *diagnostics = [NSMutableArray arrayWithCapacity:timing.diagnostics.size()];
        for (const ibms::BmsTimingDiagnostic& diagnostic : timing.diagnostics) {
            IBMSTimingDiagnostic *item = [IBMSTimingDiagnostic new];
            item->_sourceLine = diagnostic.source_line;
            item->_message = displayString(diagnostic.message);
            [diagnostics addObject:item];
        }

        snapshot->_events = [events copy];
        snapshot->_measures = [measures copy];
        snapshot->_diagnostics = [diagnostics copy];
        snapshot->_available = timing.available;
        snapshot->_unavailableReason = displayString(timing.unavailable_reason);
        return snapshot;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The timing data could not be read.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The timing data could not be read.");
    }
    return nil;
}

- (BOOL)setInitialBPM:(NSString *)decimal error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawDecimal = utf8String(decimal, error, @"Initial BPM");
        if (!rawDecimal) {
            return NO;
        }
        _document->set_initial_bpm(*rawDecimal);
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The initial BPM could not be changed.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The initial BPM could not be changed.");
    }
    return NO;
}

- (BOOL)setMeasureRatio:(NSInteger)measure decimal:(NSString *)decimal error:(NSError * _Nullable * _Nullable)error {
    try {
        if (measure < std::numeric_limits<int>::min() || measure > std::numeric_limits<int>::max()) {
            assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid, @"The selected measure is invalid.");
            return NO;
        }
        const auto rawDecimal = utf8String(decimal, error, @"Measure ratio");
        if (!rawDecimal) {
            return NO;
        }
        _document->set_measure_ratio(static_cast<int>(measure), *rawDecimal);
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The measure ratio could not be changed.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The measure ratio could not be changed.");
    }
    return NO;
}

- (BOOL)applyBeatToMeasures:(NSArray<NSNumber *> *)measures
                     decimal:(NSString *)decimal
                        mode:(NSInteger)mode
                       error:(NSError * _Nullable * _Nullable)error {
    try {
        if (mode < 0 || mode > 3) {
            assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid, @"The beat change mode is invalid.");
            return NO;
        }
        const auto rawDecimal = utf8String(decimal, error, @"Measure ratio");
        if (!rawDecimal) {
            return NO;
        }
        std::vector<int> ids;
        ids.reserve(static_cast<std::size_t>(measures.count));
        for (NSNumber *number in measures) {
            const long value = number.longValue;
            if (value < 0 || value > 999) {
                assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid, @"The selected measure is invalid.");
                return NO;
            }
            ids.push_back(static_cast<int>(value));
        }
        _document->apply_beat(ids, *rawDecimal, static_cast<ibms::BmsBeatChangeMode>(mode));
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The beat could not be changed.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The beat could not be changed.");
    }
    return NO;
}

- (BOOL)insertTimingEventAtMeasure:(NSInteger)measure
                            channel:(NSString *)channel
                  fractionNumerator:(int64_t)numerator
                fractionDenominator:(int64_t)denominator
                            decimal:(NSString *)decimal
                              error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawChannel = utf8String(channel, error, @"Channel");
        const auto rawDecimal = utf8String(decimal, error, @"Timing value");
        const auto fraction = timingFraction(measure, numerator, denominator, error);
        if (!rawChannel || !rawDecimal || !fraction) {
            return NO;
        }
        _document->insert_timing_event(static_cast<int>(measure), *rawChannel, *fraction, *rawDecimal);
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The timing event could not be added.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The timing event could not be added.");
    }
    return NO;
}

- (BOOL)insertTimingEventAtMeasure:(NSInteger)measure
                            channel:(NSString *)channel
                           gridSlot:(NSInteger)gridSlot
                       gridDivision:(NSInteger)gridDivision
                            decimal:(NSString *)decimal
                              error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawChannel = utf8String(channel, error, @"Channel");
        const auto rawDecimal = utf8String(decimal, error, @"Timing value");
        const auto fraction = gridFraction(_document->chart(), measure, gridSlot, gridDivision, error);
        if (!rawChannel || !rawDecimal || !fraction) {
            return NO;
        }
        _document->insert_timing_event(static_cast<int>(measure), *rawChannel, *fraction, *rawDecimal);
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The timing event could not be added.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The timing event could not be added.");
    }
    return NO;
}

- (BOOL)replaceTimingEventAtMeasure:(NSInteger)measure
                             channel:(NSString *)channel
                   fractionNumerator:(int64_t)numerator
                 fractionDenominator:(int64_t)denominator
                             decimal:(NSString *)decimal
                               error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawChannel = utf8String(channel, error, @"Channel");
        const auto rawDecimal = utf8String(decimal, error, @"Timing value");
        const auto fraction = timingFraction(measure, numerator, denominator, error);
        if (!rawChannel || !rawDecimal || !fraction) {
            return NO;
        }
        _document->replace_timing_event(static_cast<int>(measure), *rawChannel, *fraction, *rawDecimal);
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The timing event could not be changed.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The timing event could not be changed.");
    }
    return NO;
}

- (BOOL)eraseTimingEventAtMeasure:(NSInteger)measure
                           channel:(NSString *)channel
                 fractionNumerator:(int64_t)numerator
               fractionDenominator:(int64_t)denominator
                             error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawChannel = utf8String(channel, error, @"Channel");
        const auto fraction = timingFraction(measure, numerator, denominator, error);
        if (!rawChannel || !fraction) {
            return NO;
        }
        _document->erase_timing_event(static_cast<int>(measure), *rawChannel, *fraction);
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The timing event could not be removed.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The timing event could not be removed.");
    }
    return NO;
}

- (BOOL)insertNoteAtMeasure:(NSInteger)measure
                    channel:(NSString *)channel
                   gridSlot:(NSInteger)gridSlot
               gridDivision:(NSInteger)gridDivision
                      token:(NSString *)token
                      error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawChannel = utf8String(channel, error, @"Channel");
        const auto rawToken = utf8String(token, error, @"Token");
        const auto fraction = gridFraction(_document->chart(), measure, gridSlot, gridDivision, error);
        if (!rawChannel || !rawToken || !fraction) { return NO; }
        _document->insert_note(static_cast<int>(measure), *rawChannel, *fraction, *rawToken);
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The note could not be inserted.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The note could not be inserted.");
    }
    return NO;
}

- (BOOL)insertNoteAtMeasure:(NSInteger)measure
                    channel:(NSString *)channel
          fractionNumerator:(int64_t)numerator
        fractionDenominator:(int64_t)denominator
                      token:(NSString *)token
                      error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawChannel = utf8String(channel, error, @"Channel");
        const auto rawToken = utf8String(token, error, @"Token");
        const auto fraction = timingFraction(measure, numerator, denominator, error);
        if (!rawChannel || !rawToken || !fraction) { return NO; }
        _document->insert_note(static_cast<int>(measure), *rawChannel, *fraction, *rawToken);
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The note could not be inserted.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The note could not be inserted.");
    }
    return NO;
}

- (BOOL)eraseNoteAtMeasure:(NSInteger)measure
                   channel:(NSString *)channel
         fractionNumerator:(int64_t)numerator
       fractionDenominator:(int64_t)denominator
                     error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawChannel = utf8String(channel, error, @"Channel");
        if (!rawChannel) { return NO; }
        if (measure < std::numeric_limits<int>::min() || measure > std::numeric_limits<int>::max()) {
            assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid, @"The selected source measure is invalid.");
            return NO;
        }
        _document->erase_note(static_cast<int>(measure), *rawChannel, ibms::BeatPosition(numerator, denominator));
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The note could not be removed.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The note could not be removed.");
    }
    return NO;
}

- (BOOL)moveNoteAtMeasure:(NSInteger)sourceMeasure channel:(NSString *)sourceChannel fractionNumerator:(int64_t)sourceNumerator fractionDenominator:(int64_t)sourceDenominator toMeasure:(NSInteger)destinationMeasure channel:(NSString *)destinationChannel gridSlot:(NSInteger)gridSlot gridDivision:(NSInteger)gridDivision error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawSource = utf8String(sourceChannel, error, @"Channel");
        const auto rawDestination = utf8String(destinationChannel, error, @"Channel");
        const auto fraction = gridFraction(_document->chart(), destinationMeasure, gridSlot, gridDivision, error);
        if (!rawSource || !rawDestination || !fraction) { return NO; }
        if (sourceMeasure < std::numeric_limits<int>::min() || sourceMeasure > std::numeric_limits<int>::max()) {
            assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid, @"The selected source measure is invalid.");
            return NO;
        }
        _document->move_note(static_cast<int>(sourceMeasure), *rawSource, ibms::BeatPosition(sourceNumerator, sourceDenominator), static_cast<int>(destinationMeasure), *rawDestination, *fraction);
        return YES;
    } catch (const std::exception &exception) { assignError(error, IBMSDocumentBridgeErrorCodeCoreException, [NSString stringWithUTF8String:exception.what()] ?: @"The note could not be moved."); }
    catch (...) { assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The note could not be moved."); }
    return NO;
}

- (BOOL)moveNoteAtMeasure:(NSInteger)sourceMeasure
                  channel:(NSString *)sourceChannel
        fractionNumerator:(int64_t)sourceNumerator
      fractionDenominator:(int64_t)sourceDenominator
                toMeasure:(NSInteger)destinationMeasure
                  channel:(NSString *)destinationChannel
        fractionNumerator:(int64_t)destinationNumerator
      fractionDenominator:(int64_t)destinationDenominator
                    error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawSource = utf8String(sourceChannel, error, @"Channel");
        const auto rawDestination = utf8String(destinationChannel, error, @"Channel");
        if (!rawSource || !rawDestination) { return NO; }
        if (sourceMeasure < std::numeric_limits<int>::min() || sourceMeasure > std::numeric_limits<int>::max()
            || destinationMeasure < std::numeric_limits<int>::min() || destinationMeasure > std::numeric_limits<int>::max()) {
            assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid, @"The selected source measure is invalid.");
            return NO;
        }
        _document->move_note(
            static_cast<int>(sourceMeasure), *rawSource, ibms::BeatPosition(sourceNumerator, sourceDenominator),
            static_cast<int>(destinationMeasure), *rawDestination,
            ibms::BeatPosition(destinationNumerator, destinationDenominator));
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The note could not be moved.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The note could not be moved.");
    }
    return NO;
}

- (BOOL)insertLongNoteOnChannel:(NSString *)channel
                    startMeasure:(NSInteger)startMeasure
                   startGridSlot:(NSInteger)startGridSlot
               startGridDivision:(NSInteger)startGridDivision
                      endMeasure:(NSInteger)endMeasure
                 endGridSlot:(NSInteger)endGridSlot
             endGridDivision:(NSInteger)endGridDivision
                   startToken:(NSString *)startToken
                     endToken:(NSString *)endToken
                         error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawChannel = utf8String(channel, error, @"Long-note channel");
        const auto rawStartToken = utf8String(startToken, error, @"Long-note token");
        const auto rawEndToken = utf8String(endToken, error, @"Long-note token");
        const ibms::BmsChart& chart = _document->chart();
        const auto start = longNoteGridPosition(chart, startMeasure, startGridSlot, startGridDivision, error);
        const auto end = longNoteGridPosition(chart, endMeasure, endGridSlot, endGridDivision, error);
        if (!rawChannel || !rawStartToken || !rawEndToken || !start || !end) {
            return NO;
        }
        _document->insert_long_note(*rawChannel, *start, *end, *rawStartToken, *rawEndToken);
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The long note could not be inserted.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The long note could not be inserted.");
    }
    return NO;
}

- (BOOL)insertLongNoteOnChannel:(NSString *)channel
                    startMeasure:(NSInteger)startMeasure
               startNumerator:(int64_t)startNumerator
             startDenominator:(int64_t)startDenominator
                      endMeasure:(NSInteger)endMeasure
                 endNumerator:(int64_t)endNumerator
               endDenominator:(int64_t)endDenominator
                   startToken:(NSString *)startToken
                     endToken:(NSString *)endToken
                         error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawChannel = utf8String(channel, error, @"Long-note channel");
        const auto rawStartToken = utf8String(startToken, error, @"Long-note token");
        const auto rawEndToken = utf8String(endToken, error, @"Long-note token");
        const auto start = longNotePosition(startMeasure, startNumerator, startDenominator, error);
        const auto end = longNotePosition(endMeasure, endNumerator, endDenominator, error);
        if (!rawChannel || !rawStartToken || !rawEndToken || !start || !end) {
            return NO;
        }
        _document->insert_long_note(*rawChannel, *start, *end, *rawStartToken, *rawEndToken);
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The long note could not be inserted.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The long note could not be inserted.");
    }
    return NO;
}

- (BOOL)moveLongNoteOnChannel:(NSString *)sourceChannel
                  startMeasure:(NSInteger)sourceMeasure
              startNumerator:(int64_t)sourceNumerator
            startDenominator:(int64_t)sourceDenominator
           destinationChannel:(NSString *)destinationChannel
       destinationStartMeasure:(NSInteger)startMeasure
      destinationStartGridSlot:(NSInteger)startGridSlot
  destinationStartGridDivision:(NSInteger)startGridDivision
                         error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawSourceChannel = utf8String(sourceChannel, error, @"Long-note channel");
        const auto rawDestinationChannel = utf8String(destinationChannel, error, @"Long-note channel");
        const auto source = longNotePosition(sourceMeasure, sourceNumerator, sourceDenominator, error);
        const ibms::BmsChart& chart = _document->chart();
        const auto start = longNoteGridPosition(chart, startMeasure, startGridSlot, startGridDivision, error);
        if (!rawSourceChannel || !rawDestinationChannel || !source || !start) {
            return NO;
        }
        const ibms::BmsLongNote *note = findLongNote(_document->long_notes(), *rawSourceChannel, *source);
        if (note == nullptr) {
            assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid, @"The selected long note no longer exists.");
            return NO;
        }
        const auto destinationStartBeat = absoluteBeat(chart, *start, error);
        if (!destinationStartBeat) {
            return NO;
        }
        const auto destinationEnd = positionForBeat(
            chart, *destinationStartBeat + (note->end.beat - note->start.beat), error);
        if (!destinationEnd) {
            return NO;
        }
        _document->move_long_note(*rawSourceChannel, *source, *rawDestinationChannel, *start, *destinationEnd);
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The long note could not be moved.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The long note could not be moved.");
    }
    return NO;
}

- (BOOL)moveLongNoteStartOnChannel:(NSString *)channel
                       startMeasure:(NSInteger)sourceMeasure
                   startNumerator:(int64_t)sourceNumerator
                 startDenominator:(int64_t)sourceDenominator
            destinationStartMeasure:(NSInteger)startMeasure
           destinationStartGridSlot:(NSInteger)startGridSlot
       destinationStartGridDivision:(NSInteger)startGridDivision
                              error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawChannel = utf8String(channel, error, @"Long-note channel");
        const auto source = longNotePosition(sourceMeasure, sourceNumerator, sourceDenominator, error);
        const auto destinationStart = longNoteGridPosition(
            _document->chart(), startMeasure, startGridSlot, startGridDivision, error);
        if (!rawChannel || !source || !destinationStart) {
            return NO;
        }
        const ibms::BmsLongNote *note = findLongNote(_document->long_notes(), *rawChannel, *source);
        if (note == nullptr) {
            assignError(error, IBMSDocumentBridgeErrorCodeInvalidGrid, @"The selected long note no longer exists.");
            return NO;
        }
        _document->move_long_note(
            *rawChannel, *source, *rawChannel, *destinationStart, note->end.position);
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The long-note start could not be moved.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The long-note start could not be moved.");
    }
    return NO;
}

- (BOOL)resizeLongNoteOnChannel:(NSString *)channel
                    startMeasure:(NSInteger)startMeasure
                  startNumerator:(int64_t)startNumerator
                startDenominator:(int64_t)startDenominator
                      endMeasure:(NSInteger)endMeasure
                 endGridSlot:(NSInteger)endGridSlot
             endGridDivision:(NSInteger)endGridDivision
                           error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawChannel = utf8String(channel, error, @"Long-note channel");
        const auto start = longNotePosition(startMeasure, startNumerator, startDenominator, error);
        const auto end = longNoteGridPosition(_document->chart(), endMeasure, endGridSlot, endGridDivision, error);
        if (!rawChannel || !start || !end) {
            return NO;
        }
        _document->resize_long_note(*rawChannel, *start, *end);
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The long note could not be resized.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The long note could not be resized.");
    }
    return NO;
}

- (BOOL)eraseLongNoteOnChannel:(NSString *)channel
                   startMeasure:(NSInteger)startMeasure
                 startNumerator:(int64_t)startNumerator
               startDenominator:(int64_t)startDenominator
                           error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto rawChannel = utf8String(channel, error, @"Long-note channel");
        const auto start = longNotePosition(startMeasure, startNumerator, startDenominator, error);
        if (!rawChannel || !start) {
            return NO;
        }
        _document->erase_long_note(*rawChannel, *start);
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"The long note could not be removed.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"The long note could not be removed.");
    }
    return NO;
}

- (BOOL)undoWithError:(NSError * _Nullable * _Nullable)error {
    try {
        return _document->undo();
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"Undo failed.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"Undo failed.");
    }
    return NO;
}

- (BOOL)redoWithError:(NSError * _Nullable * _Nullable)error {
    try {
        return _document->redo();
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"Redo failed.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"Redo failed.");
    }
    return NO;
}
- (BOOL)canUndo { return _document->can_undo(); }
- (BOOL)canRedo { return _document->can_redo(); }
- (BOOL)isDirty { return _document->dirty(); }
- (nullable NSNumber *)conditionalStateWithError:(NSError * _Nullable * _Nullable)error {
    try {
        return @(_document->has_conditionals());
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"Conditional directives could not be checked.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"Conditional directives could not be checked.");
    }
    return nil;
}
- (void)markSaved { _document->mark_saved(); }
- (void)discardHistory { _document->discard_history(); }
- (BOOL)beginCompoundWithError:(NSError * _Nullable * _Nullable)error {
    try {
        _document->begin_compound();
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"Compound edit could not start.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"Compound edit could not start.");
    }
    return NO;
}
- (BOOL)endCompoundWithError:(NSError * _Nullable * _Nullable)error {
    try {
        _document->end_compound();
        return YES;
    } catch (const std::exception &exception) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException,
                    [NSString stringWithUTF8String:exception.what()] ?: @"Compound edit could not finish.");
    } catch (...) {
        assignError(error, IBMSDocumentBridgeErrorCodeCoreException, @"Compound edit could not finish.");
    }
    return NO;
}
- (void)abortCompound { _document->abort_compound(); }
- (NSUInteger)lineCount { return _document->line_count(); }

@end
