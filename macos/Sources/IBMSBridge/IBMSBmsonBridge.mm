#import "IBMSBmsonBridge.h"

#include <ibms/bms_document.hpp>
#include <ibms/bms_import_random.hpp>
#include <ibms/bmson.hpp>
#include <ibms/bmson_from_bms.hpp>

#include <exception>
#include <memory>
#include <string>
#include <vector>

NSErrorDomain const IBMSBmsonBridgeErrorDomain = @"org.ibmsc.native.bmson-bridge";

namespace {

NSError *makeError(IBMSBmsonBridgeErrorCode code, NSString *description) {
    return [NSError errorWithDomain:IBMSBmsonBridgeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

void assignError(NSError * _Nullable * _Nullable error,
                 IBMSBmsonBridgeErrorCode code,
                 NSString *description) {
    if (error != nullptr) {
        *error = makeError(code, description);
    }
}

NSString *nsString(const std::string& value) {
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding] ?: @"";
}

NSString *exceptionText(const char *what, NSString *fallback) {
    if (what == nullptr || what[0] == '\0') {
        return fallback;
    }
    return [NSString stringWithUTF8String:what] ?: fallback;
}

std::string cppString(NSString *value) {
    if (value == nil) {
        return {};
    }
    const char *utf8 = value.UTF8String;
    if (utf8 == nullptr) {
        return {};
    }
    const NSUInteger length = [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    return std::string(utf8, static_cast<std::size_t>(length));
}

ibms::BmsonBgaLane cppBgaLane(NSInteger lane) {
    if (lane == 1) {
        return ibms::BmsonBgaLane::layer;
    }
    if (lane == 2) {
        return ibms::BmsonBgaLane::poor;
    }
    return ibms::BmsonBgaLane::bga;
}

std::vector<ibms::BmsonBgaEvent> cppBgaEvents(NSArray<IBMSBmsonBgaEventFields *> *notes) {
    std::vector<ibms::BmsonBgaEvent> next;
    if (notes == nil) {
        return next;
    }
    next.reserve(static_cast<std::size_t>(notes.count));
    for (IBMSBmsonBgaEventFields *note in notes) {
        ibms::BmsonBgaEvent item;
        item.y = note.y;
        item.id = note.identifier;
        next.push_back(item);
    }
    return next;
}

ibms::BmsonFromBmsOptions cppFromBmsOptions(NSString *path, IBMSBmsonFromBmsOptions *options) {
    ibms::BmsonFromBmsOptions out;
    if (path.length > 0) {
        out.path = path.UTF8String;
    }
    if (options != nil) {
        out.trust_player_command = options.trustPlayerCommand;
        out.ignore_extension = options.ignoreExtension;
        out.prefer_ex_modes = options.preferExModes;
        if (options.mode >= 0 && options.mode <= 5) {
            out.mode = static_cast<ibms::BmsonBmsMode>(options.mode);
        }
    }
    return out;
}

}  // namespace

@implementation IBMSBmsonFromBmsOptions
- (instancetype)init {
    self = [super init];
    if (self) {
        _trustPlayerCommand = NO;
        _ignoreExtension = NO;
        _preferExModes = NO;
        _skipBetweenRandomAndIf = NO;
        _mode = -1;
    }
    return self;
}
@end

@implementation IBMSBmsonInfoFields
- (instancetype)init {
    self = [super init];
    if (self) {
        _title = @"";
        _subtitle = @"";
        _artist = @"";
        _subartists = @[];
        _genre = @"";
        _modeHint = @"beat-7k";
        _chartName = @"";
        _level = 1;
        _initBPM = 120.0;
        _judgeRank = 100.0;
        _total = 100.0;
        _resolution = 240;
    }
    return self;
}

- (instancetype)initWithSnapshot:(IBMSBmsonInfoSnapshot *)snapshot {
    self = [self init];
    if (self && snapshot != nil) {
        _title = [snapshot.title copy] ?: @"";
        _subtitle = [snapshot.subtitle copy] ?: @"";
        _artist = [snapshot.artist copy] ?: @"";
        _subartists = [snapshot.subartists copy] ?: @[];
        _genre = [snapshot.genre copy] ?: @"";
        _modeHint = [snapshot.modeHint copy] ?: @"beat-7k";
        _chartName = [snapshot.chartName copy] ?: @"";
        _level = snapshot.level;
        _initBPM = snapshot.initBPM;
        _judgeRank = snapshot.judgeRank;
        _total = snapshot.total;
        _resolution = snapshot.resolution;
    }
    return self;
}
@end

@implementation IBMSBmsonInfoSnapshot {
@public
    NSString *_title;
    NSString *_subtitle;
    NSString *_artist;
    NSArray<NSString *> *_subartists;
    NSString *_genre;
    NSString *_modeHint;
    NSString *_chartName;
    NSInteger _level;
    double _initBPM;
    double _judgeRank;
    double _total;
    NSInteger _resolution;
}
- (NSString *)title { return _title; }
- (NSString *)subtitle { return _subtitle; }
- (NSString *)artist { return _artist; }
- (NSArray<NSString *> *)subartists { return _subartists; }
- (NSString *)genre { return _genre; }
- (NSString *)modeHint { return _modeHint; }
- (NSString *)chartName { return _chartName; }
- (NSInteger)level { return _level; }
- (double)initBPM { return _initBPM; }
- (double)judgeRank { return _judgeRank; }
- (double)total { return _total; }
- (NSInteger)resolution { return _resolution; }
@end

@implementation IBMSBmsonBarLineSnapshot {
@public
    int64_t _y;
}
- (int64_t)y { return _y; }
@end

@implementation IBMSBmsonBpmNoteSnapshot {
@public
    int64_t _y;
    double _v;
}
- (int64_t)y { return _y; }
- (double)v { return _v; }
@end

@implementation IBMSBmsonStopNoteSnapshot {
@public
    int64_t _y;
    double _v;
}
- (int64_t)y { return _y; }
- (double)v { return _v; }
@end

@implementation IBMSBmsonBgaHeaderSnapshot {
@public
    int _identifier;
    NSString *_name;
}
- (int)identifier { return _identifier; }
- (NSString *)name { return _name; }
@end

@implementation IBMSBmsonBgaEventSnapshot {
@public
    int64_t _y;
    int _identifier;
}
- (int64_t)y { return _y; }
- (int)identifier { return _identifier; }
@end

@implementation IBMSBmsonBgaHeaderFields
- (instancetype)init {
    self = [super init];
    if (self) {
        _name = @"";
    }
    return self;
}
@end

@implementation IBMSBmsonBgaEventFields
@end

namespace {

IBMSBmsonInfoSnapshot *emptyInfoSnapshot() {
    IBMSBmsonInfoSnapshot *snapshot = [IBMSBmsonInfoSnapshot new];
    snapshot->_title = @"";
    snapshot->_subtitle = @"";
    snapshot->_artist = @"";
    snapshot->_subartists = @[];
    snapshot->_genre = @"";
    snapshot->_modeHint = @"";
    snapshot->_chartName = @"";
    snapshot->_level = 0;
    snapshot->_initBPM = 0;
    snapshot->_judgeRank = 0;
    snapshot->_total = 0;
    snapshot->_resolution = 0;
    return snapshot;
}

NSArray<IBMSBmsonBgaEventSnapshot *> *bgaEventSnapshots(const std::vector<ibms::BmsonBgaEvent>& source) {
    NSMutableArray<IBMSBmsonBgaEventSnapshot *> *notes =
        [NSMutableArray arrayWithCapacity:source.size()];
    for (const ibms::BmsonBgaEvent& event : source) {
        IBMSBmsonBgaEventSnapshot *item = [IBMSBmsonBgaEventSnapshot new];
        item->_y = event.y;
        item->_identifier = event.id;
        [notes addObject:item];
    }
    return [notes copy];
}

}  // namespace

@implementation IBMSBmsonNoteSnapshot {
@public
    int64_t _x;
    int64_t _y;
    int64_t _l;
    BOOL _c;
}
- (int64_t)x { return _x; }
- (int64_t)y { return _y; }
- (int64_t)l { return _l; }
- (BOOL)c { return _c; }
@end

@implementation IBMSBmsonSoundChannelSnapshot {
@public
    NSString *_name;
    NSArray<IBMSBmsonNoteSnapshot *> *_notes;
}
- (NSString *)name { return _name; }
- (NSArray<IBMSBmsonNoteSnapshot *> *)notes { return _notes; }
@end

@implementation IBMSBmsonNoteFields
@end

@implementation IBMSBmsonSoundChannelFields
- (instancetype)init {
    self = [super init];
    if (self) {
        _name = @"";
        _notes = @[];
    }
    return self;
}
@end

@implementation IBMSBmsonTimingFields
@end

@implementation IBMSBmsonBridge {
    std::unique_ptr<ibms::BmsonDocument> _document;
}

+ (instancetype)emptyDocument {
    IBMSBmsonBridge *bridge = [[IBMSBmsonBridge alloc] init];
    bridge->_document = std::make_unique<ibms::BmsonDocument>(ibms::BmsonDocument::empty());
    return bridge;
}

+ (nullable instancetype)documentFromBMSData:(NSData *)data
                                       error:(NSError * _Nullable * _Nullable)error {
    return [self documentFromBMSData:data path:nil error:error];
}

+ (nullable instancetype)documentFromBMSData:(NSData *)data
                                        path:(nullable NSString *)path
                                       error:(NSError * _Nullable * _Nullable)error {
    return [self documentFromBMSData:data path:path mode:-1 error:error];
}

+ (nullable instancetype)documentFromBMSData:(NSData *)data
                                        path:(nullable NSString *)path
                                        mode:(NSInteger)mode
                                       error:(NSError * _Nullable * _Nullable)error {
    IBMSBmsonFromBmsOptions *options = [[IBMSBmsonFromBmsOptions alloc] init];
    options.mode = mode;
    return [self documentFromBMSData:data path:path options:options error:error];
}

+ (nullable instancetype)documentFromBMSData:(NSData *)data
                                        path:(nullable NSString *)path
                                     options:(IBMSBmsonFromBmsOptions *)options
                                       error:(NSError * _Nullable * _Nullable)error {
    IBMSBmsonBridge *bridge = [[IBMSBmsonBridge alloc] init];
    try {
        const char *bytes = data.length == 0 ? "" : static_cast<const char *>(data.bytes);
        std::string source(bytes, data.length);
        const ibms::BmsDocument bms = ibms::BmsDocument::from_bytes(std::move(source));
        bridge->_document = std::make_unique<ibms::BmsonDocument>(
            ibms::bmson_from_bms(bms, cppFromBmsOptions(path, options)));
        return bridge;
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMS file could not be imported."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMS file could not be imported.");
    }
    return nil;
}

+ (nullable NSNumber *)detectedModeFromBMSData:(NSData *)data
                                          path:(nullable NSString *)path
                                         error:(NSError * _Nullable * _Nullable)error {
    IBMSBmsonFromBmsOptions *options = [[IBMSBmsonFromBmsOptions alloc] init];
    return [self detectedModeFromBMSData:data path:path options:options error:error];
}

+ (nullable NSNumber *)detectedModeFromBMSData:(NSData *)data
                                          path:(nullable NSString *)path
                                       options:(IBMSBmsonFromBmsOptions *)options
                                         error:(NSError * _Nullable * _Nullable)error {
    try {
        const char *bytes = data.length == 0 ? "" : static_cast<const char *>(data.bytes);
        std::string source(bytes, data.length);
        const ibms::BmsDocument bms = ibms::BmsDocument::from_bytes(std::move(source));
        return @(static_cast<NSInteger>(
            ibms::detect_bmson_bms_mode(bms, cppFromBmsOptions(path, options))));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMS file could not be imported."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMS file could not be imported.");
    }
    return nil;
}

+ (nullable NSArray<NSNumber *> *)errorOffsetsFromBMSData:(NSData *)data
                                                    path:(nullable NSString *)path
                                                    mode:(NSInteger)mode
                                                   error:(NSError * _Nullable * _Nullable)error {
    try {
        const char *bytes = data.length == 0 ? "" : static_cast<const char *>(data.bytes);
        std::string source(bytes, data.length);
        const ibms::BmsDocument bms = ibms::BmsDocument::from_bytes(std::move(source));
        const auto offsets = ibms::bmson_mode_error_offsets(bms, static_cast<ibms::BmsonBmsMode>(mode));
        NSMutableArray<NSNumber *> *values = [NSMutableArray arrayWithCapacity:offsets.size()];
        for (int offset : offsets) {
            [values addObject:@(offset)];
        }
        return values;
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMS file could not be imported."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMS file could not be imported.");
    }
    return nil;
}

+ (nullable NSArray<NSNumber *> *)randomMaximaFromBMSData:(NSData *)data
                                                   error:(NSError * _Nullable * _Nullable)error {
    try {
        const char *bytes = data.length == 0 ? "" : static_cast<const char *>(data.bytes);
        const std::string source(bytes, data.length);
        const auto maxima = ibms::collect_bms_random_maxima(source);
        NSMutableArray<NSNumber *> *values = [NSMutableArray arrayWithCapacity:maxima.size()];
        for (int value : maxima) {
            [values addObject:@(value)];
        }
        return values;
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMS file could not be imported."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMS file could not be imported.");
    }
    return nil;
}

+ (nullable NSData *)applyRandomToBMSData:(NSData *)data
                                   values:(NSArray<NSNumber *> *)values
                                    error:(NSError * _Nullable * _Nullable)error {
    return [self applyRandomToBMSData:data values:values skipBetweenRandomAndIf:NO error:error];
}

+ (nullable NSData *)applyRandomToBMSData:(NSData *)data
                                   values:(NSArray<NSNumber *> *)values
                skipBetweenRandomAndIf:(BOOL)skipBetweenRandomAndIf
                                    error:(NSError * _Nullable * _Nullable)error {
    try {
        const char *bytes = data.length == 0 ? "" : static_cast<const char *>(data.bytes);
        const std::string source(bytes, data.length);
        std::vector<int> chosen;
        chosen.reserve(values.count);
        for (NSNumber *value in values) {
            chosen.push_back(value.intValue);
        }
        const std::string filtered = ibms::apply_bms_random(source, chosen, skipBetweenRandomAndIf);
        return [NSData dataWithBytes:filtered.data() length:filtered.size()];
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMS file could not be imported."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMS file could not be imported.");
    }
    return nil;
}

- (nullable instancetype)initWithJSONString:(NSString *)text
                                      error:(NSError * _Nullable * _Nullable)error {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    try {
        const char *utf8 = text.UTF8String ?: "";
        _document = std::make_unique<ibms::BmsonDocument>(ibms::BmsonDocument::from_json(utf8));
        return self;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON document could not be parsed."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON document could not be parsed."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON document could not be parsed.");
    }
    return nil;
}

- (nullable NSString *)JSONStringWithError:(NSError * _Nullable * _Nullable)error {
    try {
        const std::string json = _document->to_json();
        return nsString(json);
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeSerialize,
                    exceptionText(exception.what(), @"The BMSON document could not be written."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeSerialize,
                    exceptionText(exception.what(), @"The BMSON document could not be written."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeSerialize, @"The BMSON document could not be written.");
    }
    return nil;
}

- (NSString *)version {
    try {
        return nsString(_document->version());
    } catch (...) {
        return @"";
    }
}

- (IBMSBmsonInfoSnapshot *)info {
    try {
        const ibms::BmsonInfo& source = _document->info();
        IBMSBmsonInfoSnapshot *snapshot = [IBMSBmsonInfoSnapshot new];
        snapshot->_title = nsString(source.title);
        snapshot->_subtitle = nsString(source.subtitle);
        snapshot->_artist = nsString(source.artist);
        NSMutableArray<NSString *> *subartists = [NSMutableArray arrayWithCapacity:source.subartists.size()];
        for (const std::string& name : source.subartists) {
            [subartists addObject:nsString(name)];
        }
        snapshot->_subartists = [subartists copy];
        snapshot->_genre = nsString(source.genre);
        snapshot->_modeHint = nsString(source.mode_hint);
        snapshot->_chartName = nsString(source.chart_name);
        snapshot->_level = source.level;
        snapshot->_initBPM = source.init_bpm;
        snapshot->_judgeRank = source.judge_rank;
        snapshot->_total = source.total;
        snapshot->_resolution = source.resolution;
        return snapshot;
    } catch (...) {
        return emptyInfoSnapshot();
    }
}

- (NSArray<IBMSBmsonBarLineSnapshot *> *)lines {
    try {
        const auto& source = _document->lines();
        NSMutableArray<IBMSBmsonBarLineSnapshot *> *lines =
            [NSMutableArray arrayWithCapacity:source.size()];
        for (const ibms::BmsonBarLine& line : source) {
            IBMSBmsonBarLineSnapshot *item = [IBMSBmsonBarLineSnapshot new];
            item->_y = line.y;
            [lines addObject:item];
        }
        return [lines copy];
    } catch (...) {
        return @[];
    }
}

- (NSArray<IBMSBmsonBpmNoteSnapshot *> *)bpmNotes {
    try {
        const auto& source = _document->bpm_notes();
        NSMutableArray<IBMSBmsonBpmNoteSnapshot *> *notes =
            [NSMutableArray arrayWithCapacity:source.size()];
        for (const ibms::BmsonBpmNote& note : source) {
            IBMSBmsonBpmNoteSnapshot *item = [IBMSBmsonBpmNoteSnapshot new];
            item->_y = note.y;
            item->_v = note.v;
            [notes addObject:item];
        }
        return [notes copy];
    } catch (...) {
        return @[];
    }
}

- (NSArray<IBMSBmsonStopNoteSnapshot *> *)stopNotes {
    try {
        const auto& source = _document->stop_notes();
        NSMutableArray<IBMSBmsonStopNoteSnapshot *> *notes =
            [NSMutableArray arrayWithCapacity:source.size()];
        for (const ibms::BmsonStopNote& note : source) {
            IBMSBmsonStopNoteSnapshot *item = [IBMSBmsonStopNoteSnapshot new];
            item->_y = note.y;
            item->_v = note.v;
            [notes addObject:item];
        }
        return [notes copy];
    } catch (...) {
        return @[];
    }
}

- (NSArray<IBMSBmsonBgaHeaderSnapshot *> *)bgaHeaders {
    try {
        const auto& source = _document->bga_headers();
        NSMutableArray<IBMSBmsonBgaHeaderSnapshot *> *headers =
            [NSMutableArray arrayWithCapacity:source.size()];
        for (const ibms::BmsonBgaHeader& header : source) {
            IBMSBmsonBgaHeaderSnapshot *item = [IBMSBmsonBgaHeaderSnapshot new];
            item->_identifier = header.id;
            item->_name = nsString(header.name);
            [headers addObject:item];
        }
        return [headers copy];
    } catch (...) {
        return @[];
    }
}

- (NSArray<IBMSBmsonBgaEventSnapshot *> *)bgaEvents {
    try {
        return bgaEventSnapshots(_document->bga_events());
    } catch (...) {
        return @[];
    }
}

- (NSArray<IBMSBmsonBgaEventSnapshot *> *)layerEvents {
    try {
        return bgaEventSnapshots(_document->layer_events());
    } catch (...) {
        return @[];
    }
}

- (NSArray<IBMSBmsonBgaEventSnapshot *> *)poorEvents {
    try {
        return bgaEventSnapshots(_document->poor_events());
    } catch (...) {
        return @[];
    }
}

- (NSArray<IBMSBmsonSoundChannelSnapshot *> *)soundChannels {
    try {
        const auto& source = _document->sound_channels();
        NSMutableArray<IBMSBmsonSoundChannelSnapshot *> *channels =
            [NSMutableArray arrayWithCapacity:source.size()];
        for (const ibms::BmsonSoundChannel& channel : source) {
            NSMutableArray<IBMSBmsonNoteSnapshot *> *notes =
                [NSMutableArray arrayWithCapacity:channel.notes.size()];
            for (const ibms::BmsonNote& note : channel.notes) {
                IBMSBmsonNoteSnapshot *item = [IBMSBmsonNoteSnapshot new];
                item->_x = note.x;
                item->_y = note.y;
                item->_l = note.l;
                item->_c = note.c ? YES : NO;
                [notes addObject:item];
            }
            IBMSBmsonSoundChannelSnapshot *item = [IBMSBmsonSoundChannelSnapshot new];
            item->_name = nsString(channel.name);
            item->_notes = [notes copy];
            [channels addObject:item];
        }
        return [channels copy];
    } catch (...) {
        return @[];
    }
}

- (BOOL)insertSoundNoteOnChannel:(NSUInteger)channelIndex
                               x:(int64_t)x
                               y:(int64_t)y
                               l:(int64_t)l
                               c:(BOOL)c
                           error:(NSError * _Nullable * _Nullable)error {
    try {
        ibms::BmsonNote note;
        note.x = x;
        note.y = y;
        note.l = l;
        note.c = c ? true : false;
        _document->insert_sound_note(static_cast<std::size_t>(channelIndex), note);
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON note could not be inserted."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON note could not be inserted."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON note could not be inserted.");
    }
    return NO;
}

- (BOOL)eraseSoundNoteOnChannel:(NSUInteger)channelIndex
                              y:(int64_t)y
                          error:(NSError * _Nullable * _Nullable)error {
    try {
        if (!_document->erase_sound_note(static_cast<std::size_t>(channelIndex), y)) {
            assignError(error, IBMSBmsonBridgeErrorCodeParse,
                        @"no sound note at the requested pulse");
            return NO;
        }
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON note could not be erased."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON note could not be erased."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON note could not be erased.");
    }
    return NO;
}

- (BOOL)replaceSoundNoteOnChannel:(NSUInteger)channelIndex
                             oldY:(int64_t)oldY
                                x:(int64_t)x
                                y:(int64_t)y
                                l:(int64_t)l
                                c:(BOOL)c
                            error:(NSError * _Nullable * _Nullable)error {
    try {
        ibms::BmsonNote note;
        note.x = x;
        note.y = y;
        note.l = l;
        note.c = c ? true : false;
        _document->replace_sound_note(static_cast<std::size_t>(channelIndex), oldY, note);
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON note could not be replaced."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON note could not be replaced."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON note could not be replaced.");
    }
    return NO;
}

- (nullable NSString *)noteExtraJSONOnChannel:(NSUInteger)channelIndex
                                            y:(int64_t)y
                                        error:(NSError * _Nullable * _Nullable)error {
    try {
        const std::string json =
            _document->note_extra_object_json(static_cast<std::size_t>(channelIndex), y);
        return nsString(json);
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON note extra fields could not be read."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON note extra fields could not be read."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON note extra fields could not be read.");
    }
    return nil;
}

- (BOOL)replaceNoteExtraJSONOnChannel:(NSUInteger)channelIndex
                                    y:(int64_t)y
                                 json:(NSString *)json
                                error:(NSError * _Nullable * _Nullable)error {
    try {
        _document->replace_note_extra_object_json(
            static_cast<std::size_t>(channelIndex), y, cppString(json));
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON note extra fields could not be written."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON note extra fields could not be written."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON note extra fields could not be written.");
    }
    return NO;
}

- (BOOL)upsertBpmNoteAtY:(int64_t)y
                       v:(double)v
                   error:(NSError * _Nullable * _Nullable)error {
    try {
        ibms::BmsonBpmNote note;
        note.y = y;
        note.v = v;
        _document->upsert_bpm_note(note);
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON BPM note could not be written."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON BPM note could not be written."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON BPM note could not be written.");
    }
    return NO;
}

- (BOOL)eraseBpmNoteAtY:(int64_t)y
                  error:(NSError * _Nullable * _Nullable)error {
    try {
        if (!_document->erase_bpm_note(y)) {
            assignError(error, IBMSBmsonBridgeErrorCodeParse, @"no BPM note at the requested pulse");
            return NO;
        }
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON BPM note could not be erased."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON BPM note could not be erased."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON BPM note could not be erased.");
    }
    return NO;
}

- (BOOL)upsertStopNoteAtY:(int64_t)y
                       v:(double)v
                   error:(NSError * _Nullable * _Nullable)error {
    try {
        ibms::BmsonStopNote note;
        note.y = y;
        note.v = v;
        _document->upsert_stop_note(note);
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON STOP note could not be written."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON STOP note could not be written."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON STOP note could not be written.");
    }
    return NO;
}

- (BOOL)eraseStopNoteAtY:(int64_t)y
                   error:(NSError * _Nullable * _Nullable)error {
    try {
        if (!_document->erase_stop_note(y)) {
            assignError(error, IBMSBmsonBridgeErrorCodeParse, @"no STOP note at the requested pulse");
            return NO;
        }
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON STOP note could not be erased."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON STOP note could not be erased."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON STOP note could not be erased.");
    }
    return NO;
}

- (BOOL)replaceInfo:(IBMSBmsonInfoFields *)fields
              error:(NSError * _Nullable * _Nullable)error {
    if (fields == nil) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"BMSON info is missing.");
        return NO;
    }
    try {
        ibms::BmsonInfo info;
        info.title = cppString(fields.title);
        info.subtitle = cppString(fields.subtitle);
        info.artist = cppString(fields.artist);
        info.genre = cppString(fields.genre);
        info.mode_hint = cppString(fields.modeHint);
        info.chart_name = cppString(fields.chartName);
        info.level = static_cast<int>(fields.level);
        info.init_bpm = fields.initBPM;
        info.judge_rank = fields.judgeRank;
        info.total = fields.total;
        info.resolution = static_cast<int>(fields.resolution);
        for (NSString *name in fields.subartists) {
            info.subartists.push_back(cppString(name));
        }
        _document->replace_info(std::move(info));
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON info could not be written."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON info could not be written."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON info could not be written.");
    }
    return NO;
}

- (NSString *)infoExtraStringForKey:(NSString *)key {
    try {
        return nsString(_document->info_extra_string(cppString(key)));
    } catch (...) {
        return @"";
    }
}

- (BOOL)setInfoExtraString:(NSString *)value
                    forKey:(NSString *)key
                     error:(NSError * _Nullable * _Nullable)error {
    try {
        _document->set_info_extra_string(cppString(key), cppString(value));
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON info extra field could not be written."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON info extra field could not be written."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON info extra field could not be written.");
    }
    return NO;
}

- (NSString *)infoExtraObjectJSON {
    try {
        return nsString(_document->info_extra_object_json());
    } catch (...) {
        return @"{}";
    }
}

- (BOOL)replaceInfoExtraObjectJSON:(NSString *)json
                             error:(NSError * _Nullable * _Nullable)error {
    try {
        _document->replace_info_extra_object_json(cppString(json));
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON info extra fields could not be written."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON info extra fields could not be written."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON info extra fields could not be written.");
    }
    return NO;
}

- (BOOL)replaceSoundChannels:(NSArray<IBMSBmsonSoundChannelFields *> *)channels
                       error:(NSError * _Nullable * _Nullable)error {
    if (channels == nil) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"BMSON soundChannels is missing.");
        return NO;
    }
    try {
        std::vector<ibms::BmsonSoundChannel> next;
        next.reserve(static_cast<std::size_t>(channels.count));
        for (IBMSBmsonSoundChannelFields *channel in channels) {
            ibms::BmsonSoundChannel item;
            item.name = cppString(channel.name);
            for (IBMSBmsonNoteFields *note in channel.notes) {
                ibms::BmsonNote written;
                written.x = note.x;
                written.y = note.y;
                written.l = note.l;
                written.c = note.c ? true : false;
                item.notes.push_back(written);
            }
            next.push_back(std::move(item));
        }
        _document->replace_sound_channels(std::move(next));
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON sound channels could not be written."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON sound channels could not be written."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON sound channels could not be written.");
    }
    return NO;
}

- (BOOL)replaceLines:(NSArray<NSNumber *> *)pulses
               error:(NSError * _Nullable * _Nullable)error {
    if (pulses == nil) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"BMSON lines is missing.");
        return NO;
    }
    try {
        std::vector<ibms::BmsonBarLine> next;
        next.reserve(static_cast<std::size_t>(pulses.count));
        for (NSNumber *pulse in pulses) {
            ibms::BmsonBarLine line;
            line.y = pulse.longLongValue;
            next.push_back(line);
        }
        _document->replace_lines(std::move(next));
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON bar lines could not be written."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON bar lines could not be written."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON bar lines could not be written.");
    }
    return NO;
}

- (BOOL)replaceBpmNotes:(NSArray<IBMSBmsonTimingFields *> *)notes
                  error:(NSError * _Nullable * _Nullable)error {
    if (notes == nil) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"BMSON bpmNotes is missing.");
        return NO;
    }
    try {
        std::vector<ibms::BmsonBpmNote> next;
        next.reserve(static_cast<std::size_t>(notes.count));
        for (IBMSBmsonTimingFields *note in notes) {
            ibms::BmsonBpmNote item;
            item.y = note.y;
            item.v = note.v;
            next.push_back(item);
        }
        _document->replace_bpm_notes(std::move(next));
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON BPM notes could not be written."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON BPM notes could not be written."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON BPM notes could not be written.");
    }
    return NO;
}

- (BOOL)replaceBgaHeaders:(NSArray<IBMSBmsonBgaHeaderFields *> *)headers
               bgaEvents:(NSArray<IBMSBmsonBgaEventFields *> *)bgaEvents
            layerEvents:(NSArray<IBMSBmsonBgaEventFields *> *)layerEvents
             poorEvents:(NSArray<IBMSBmsonBgaEventFields *> *)poorEvents
                   error:(NSError * _Nullable * _Nullable)error {
    if (headers == nil || bgaEvents == nil || layerEvents == nil || poorEvents == nil) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"BMSON bga is missing.");
        return NO;
    }
    try {
        std::vector<ibms::BmsonBgaHeader> nextHeaders;
        nextHeaders.reserve(static_cast<std::size_t>(headers.count));
        for (IBMSBmsonBgaHeaderFields *header in headers) {
            ibms::BmsonBgaHeader item;
            item.id = header.identifier;
            item.name = cppString(header.name);
            nextHeaders.push_back(std::move(item));
        }
        _document->replace_bga(
            std::move(nextHeaders),
            cppBgaEvents(bgaEvents),
            cppBgaEvents(layerEvents),
            cppBgaEvents(poorEvents));
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON BGA could not be written."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON BGA could not be written."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON BGA could not be written.");
    }
    return NO;
}

- (BOOL)upsertBgaHeaderIdentifier:(int)identifier
                             name:(NSString *)name
                            error:(NSError * _Nullable * _Nullable)error {
    try {
        ibms::BmsonBgaHeader header;
        header.id = identifier;
        header.name = cppString(name);
        _document->upsert_bga_header(std::move(header));
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON BGA header could not be written."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON BGA header could not be written."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON BGA header could not be written.");
    }
    return NO;
}

- (BOOL)upsertBgaEventOnLane:(NSInteger)lane
                           y:(int64_t)y
                  identifier:(int)identifier
                       error:(NSError * _Nullable * _Nullable)error {
    try {
        ibms::BmsonBgaEvent event;
        event.y = y;
        event.id = identifier;
        _document->upsert_bga_event(cppBgaLane(lane), event);
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON BGA event could not be written."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON BGA event could not be written."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON BGA event could not be written.");
    }
    return NO;
}

- (BOOL)eraseBgaEventOnLane:(NSInteger)lane
                          y:(int64_t)y
                      error:(NSError * _Nullable * _Nullable)error {
    try {
        if (!_document->erase_bga_event(cppBgaLane(lane), y)) {
            assignError(error, IBMSBmsonBridgeErrorCodeParse, @"no BGA event at the requested pulse");
            return NO;
        }
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON BGA event could not be erased."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON BGA event could not be erased."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON BGA event could not be erased.");
    }
    return NO;
}

- (BOOL)replaceStopNotes:(NSArray<IBMSBmsonTimingFields *> *)notes
                   error:(NSError * _Nullable * _Nullable)error {
    if (notes == nil) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"BMSON stopNotes is missing.");
        return NO;
    }
    try {
        std::vector<ibms::BmsonStopNote> next;
        next.reserve(static_cast<std::size_t>(notes.count));
        for (IBMSBmsonTimingFields *note in notes) {
            ibms::BmsonStopNote item;
            item.y = note.y;
            item.v = note.v;
            next.push_back(item);
        }
        _document->replace_stop_notes(std::move(next));
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON STOP notes could not be written."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON STOP notes could not be written."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON STOP notes could not be written.");
    }
    return NO;
}

- (BOOL)convertResolution:(NSInteger)newResolution
                    error:(NSError * _Nullable * _Nullable)error {
    try {
        _document->convert_resolution(static_cast<int>(newResolution));
        return YES;
    } catch (const ibms::BmsonParseError& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON resolution could not be converted."));
    } catch (const std::exception& exception) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse,
                    exceptionText(exception.what(), @"The BMSON resolution could not be converted."));
    } catch (...) {
        assignError(error, IBMSBmsonBridgeErrorCodeParse, @"The BMSON resolution could not be converted.");
    }
    return NO;
}

- (BOOL)resolutionConversionLosesInformation:(NSInteger)newResolution {
    try {
        return _document->resolution_conversion_loses_information(static_cast<int>(newResolution)) ? YES : NO;
    } catch (...) {
        return YES;
    }
}

- (NSInteger)acceptableResolutionDivider {
    try {
        return _document->acceptable_resolution_divider();
    } catch (...) {
        return 1;
    }
}

@end
