#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const IBMSBmsonBridgeErrorDomain;

typedef NS_ERROR_ENUM(IBMSBmsonBridgeErrorDomain, IBMSBmsonBridgeErrorCode) {
    IBMSBmsonBridgeErrorCodeParse = 1,
    IBMSBmsonBridgeErrorCodeSerialize = 2,
};

@interface IBMSBmsonInfoSnapshot : NSObject
@property(nonatomic, copy, readonly) NSString *title;
@property(nonatomic, copy, readonly) NSString *subtitle;
@property(nonatomic, copy, readonly) NSString *artist;
@property(nonatomic, copy, readonly) NSArray<NSString *> *subartists;
@property(nonatomic, copy, readonly) NSString *genre;
@property(nonatomic, copy, readonly) NSString *modeHint;
@property(nonatomic, copy, readonly) NSString *chartName;
@property(nonatomic, readonly) NSInteger level;
@property(nonatomic, readonly) double initBPM;
@property(nonatomic, readonly) double judgeRank;
@property(nonatomic, readonly) double total;
@property(nonatomic, readonly) NSInteger resolution;
@end

@interface IBMSBmsonInfoFields : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *subtitle;
@property(nonatomic, copy) NSString *artist;
@property(nonatomic, copy) NSArray<NSString *> *subartists;
@property(nonatomic, copy) NSString *genre;
@property(nonatomic, copy) NSString *modeHint;
@property(nonatomic, copy) NSString *chartName;
@property(nonatomic, assign) NSInteger level;
@property(nonatomic, assign) double initBPM;
@property(nonatomic, assign) double judgeRank;
@property(nonatomic, assign) double total;
@property(nonatomic, assign) NSInteger resolution;
- (instancetype)initWithSnapshot:(IBMSBmsonInfoSnapshot *)snapshot;
@end

@interface IBMSBmsonBarLineSnapshot : NSObject
@property(nonatomic, readonly) int64_t y;
@end

@interface IBMSBmsonBpmNoteSnapshot : NSObject
@property(nonatomic, readonly) int64_t y;
@property(nonatomic, readonly) double v;
@end

@interface IBMSBmsonStopNoteSnapshot : NSObject
@property(nonatomic, readonly) int64_t y;
@property(nonatomic, readonly) double v;
@end

@interface IBMSBmsonBgaHeaderSnapshot : NSObject
@property(nonatomic, readonly) int identifier;
@property(nonatomic, copy, readonly) NSString *name;
@end

@interface IBMSBmsonBgaEventSnapshot : NSObject
@property(nonatomic, readonly) int64_t y;
@property(nonatomic, readonly) int identifier;
@end

@interface IBMSBmsonBgaHeaderFields : NSObject
@property(nonatomic, assign) int identifier;
@property(nonatomic, copy) NSString *name;
@end

@interface IBMSBmsonBgaEventFields : NSObject
@property(nonatomic, assign) int64_t y;
@property(nonatomic, assign) int identifier;
@end

@interface IBMSBmsonNoteSnapshot : NSObject
@property(nonatomic, readonly) int64_t x;
@property(nonatomic, readonly) int64_t y;
@property(nonatomic, readonly) int64_t l;
@property(nonatomic, readonly) BOOL c;
@end

@interface IBMSBmsonSoundChannelSnapshot : NSObject
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSArray<IBMSBmsonNoteSnapshot *> *notes;
@end

@interface IBMSBmsonNoteFields : NSObject
@property(nonatomic, assign) int64_t x;
@property(nonatomic, assign) int64_t y;
@property(nonatomic, assign) int64_t l;
@property(nonatomic, assign) BOOL c;
@end

@interface IBMSBmsonSoundChannelFields : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSArray<IBMSBmsonNoteFields *> *notes;
@end

/// Contrasts `BmsonFromBmsOptions` plus `apply_bms_random` skip-between.
@interface IBMSBmsonFromBmsOptions : NSObject
@property(nonatomic, assign) BOOL trustPlayerCommand;
@property(nonatomic, assign) BOOL ignoreExtension;
@property(nonatomic, assign) BOOL preferExModes;
@property(nonatomic, assign) BOOL skipBetweenRandomAndIf;
/// `-1` means `GetMode`. `0...5` matches `BmsonBmsMode`.
@property(nonatomic, assign) NSInteger mode;
@end

@interface IBMSBmsonTimingFields : NSObject
@property(nonatomic, assign) int64_t y;
@property(nonatomic, assign) double v;
@end

/// ObjC++ bridge over `ibms::BmsonDocument`. Not `IBMSDocumentBridge` / BMS.
@interface IBMSBmsonBridge : NSObject

+ (instancetype)emptyDocument;
+ (nullable instancetype)documentFromBMSData:(NSData *)data
                                       error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(fromBmsData(_:));
+ (nullable instancetype)documentFromBMSData:(NSData *)data
                                        path:(nullable NSString *)path
                                       error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(fromBmsData(_:path:));
+ (nullable instancetype)documentFromBMSData:(NSData *)data
                                        path:(nullable NSString *)path
                                        mode:(NSInteger)mode
                                       error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(fromBmsData(_:path:mode:));
+ (nullable instancetype)documentFromBMSData:(NSData *)data
                                        path:(nullable NSString *)path
                                     options:(IBMSBmsonFromBmsOptions *)options
                                       error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(fromBmsData(_:path:options:));
+ (nullable NSNumber *)detectedModeFromBMSData:(NSData *)data
                                          path:(nullable NSString *)path
                                         error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(detectedMode(fromBmsData:path:));
+ (nullable NSNumber *)detectedModeFromBMSData:(NSData *)data
                                          path:(nullable NSString *)path
                                       options:(IBMSBmsonFromBmsOptions *)options
                                         error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(detectedMode(fromBmsData:path:options:));
+ (nullable NSArray<NSNumber *> *)errorOffsetsFromBMSData:(NSData *)data
                                                    path:(nullable NSString *)path
                                                    mode:(NSInteger)mode
                                                   error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(errorOffsets(fromBmsData:path:mode:));
+ (nullable NSArray<NSNumber *> *)randomMaximaFromBMSData:(NSData *)data
                                                   error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(randomMaxima(fromBmsData:));
+ (nullable NSData *)applyRandomToBMSData:(NSData *)data
                                   values:(NSArray<NSNumber *> *)values
                                    error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(applyRandom(to:values:));
+ (nullable NSData *)applyRandomToBMSData:(NSData *)data
                                   values:(NSArray<NSNumber *> *)values
                skipBetweenRandomAndIf:(BOOL)skipBetweenRandomAndIf
                                    error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(applyRandom(to:values:skipBetweenRandomAndIf:));
- (nullable instancetype)initWithJSONString:(NSString *)text
                                      error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(init(jsonString:));
- (nullable NSString *)JSONStringWithError:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(jsonString());

@property(nonatomic, copy, readonly) NSString *version;
@property(nonatomic, strong, readonly) IBMSBmsonInfoSnapshot *info;
@property(nonatomic, copy, readonly) NSArray<IBMSBmsonBarLineSnapshot *> *lines;
@property(nonatomic, copy, readonly) NSArray<IBMSBmsonBpmNoteSnapshot *> *bpmNotes;
@property(nonatomic, copy, readonly) NSArray<IBMSBmsonStopNoteSnapshot *> *stopNotes;
@property(nonatomic, copy, readonly) NSArray<IBMSBmsonSoundChannelSnapshot *> *soundChannels;
@property(nonatomic, copy, readonly) NSArray<IBMSBmsonBgaHeaderSnapshot *> *bgaHeaders;
@property(nonatomic, copy, readonly) NSArray<IBMSBmsonBgaEventSnapshot *> *bgaEvents;
@property(nonatomic, copy, readonly) NSArray<IBMSBmsonBgaEventSnapshot *> *layerEvents;
@property(nonatomic, copy, readonly) NSArray<IBMSBmsonBgaEventSnapshot *> *poorEvents;

- (BOOL)insertSoundNoteOnChannel:(NSUInteger)channelIndex
                               x:(int64_t)x
                               y:(int64_t)y
                               l:(int64_t)l
                               c:(BOOL)c
                           error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(insertSoundNote(onChannel:x:y:l:c:));
- (BOOL)eraseSoundNoteOnChannel:(NSUInteger)channelIndex
                              y:(int64_t)y
                          error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(eraseSoundNote(onChannel:y:));
- (BOOL)replaceSoundNoteOnChannel:(NSUInteger)channelIndex
                             oldY:(int64_t)oldY
                                x:(int64_t)x
                                y:(int64_t)y
                                l:(int64_t)l
                                c:(BOOL)c
                            error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(replaceSoundNote(onChannel:oldY:x:y:l:c:));
- (nullable NSString *)noteExtraJSONOnChannel:(NSUInteger)channelIndex
                                            y:(int64_t)y
                                        error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(noteExtraJSON(onChannel:y:));
- (BOOL)replaceNoteExtraJSONOnChannel:(NSUInteger)channelIndex
                                    y:(int64_t)y
                                 json:(NSString *)json
                                error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(replaceNoteExtraJSON(onChannel:y:json:));
- (BOOL)upsertBpmNoteAtY:(int64_t)y
                       v:(double)v
                   error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(upsertBpmNote(y:v:));
- (BOOL)eraseBpmNoteAtY:(int64_t)y
                  error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(eraseBpmNote(y:));
- (BOOL)upsertStopNoteAtY:(int64_t)y
                       v:(double)v
                   error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(upsertStopNote(y:v:));
- (BOOL)eraseStopNoteAtY:(int64_t)y
                   error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(eraseStopNote(y:));
- (BOOL)replaceInfo:(IBMSBmsonInfoFields *)fields
              error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(replaceInfo(_:));
- (NSString *)infoExtraStringForKey:(NSString *)key
    NS_SWIFT_NAME(infoExtraString(forKey:));
- (BOOL)setInfoExtraString:(NSString *)value
                    forKey:(NSString *)key
                     error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(setInfoExtraString(_:forKey:));
- (NSString *)infoExtraObjectJSON
    NS_SWIFT_NAME(infoExtraObjectJSON());
- (BOOL)replaceInfoExtraObjectJSON:(NSString *)json
                             error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(replaceInfoExtraObjectJSON(_:));
- (BOOL)replaceSoundChannels:(NSArray<IBMSBmsonSoundChannelFields *> *)channels
                       error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(replaceSoundChannels(_:));
- (BOOL)replaceLines:(NSArray<NSNumber *> *)pulses
               error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(replaceLines(_:));
- (BOOL)replaceBpmNotes:(NSArray<IBMSBmsonTimingFields *> *)notes
                  error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(replaceBpmNotes(_:));
- (BOOL)replaceStopNotes:(NSArray<IBMSBmsonTimingFields *> *)notes
                   error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(replaceStopNotes(_:));
- (BOOL)replaceBgaHeaders:(NSArray<IBMSBmsonBgaHeaderFields *> *)headers
               bgaEvents:(NSArray<IBMSBmsonBgaEventFields *> *)bgaEvents
            layerEvents:(NSArray<IBMSBmsonBgaEventFields *> *)layerEvents
             poorEvents:(NSArray<IBMSBmsonBgaEventFields *> *)poorEvents
                   error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(replaceBga(headers:bgaEvents:layerEvents:poorEvents:));
- (BOOL)upsertBgaHeaderIdentifier:(int)identifier
                             name:(NSString *)name
                            error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(upsertBgaHeader(identifier:name:));
- (BOOL)upsertBgaEventOnLane:(NSInteger)lane
                           y:(int64_t)y
                  identifier:(int)identifier
                       error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(upsertBgaEvent(onLane:y:identifier:));
- (BOOL)eraseBgaEventOnLane:(NSInteger)lane
                          y:(int64_t)y
                      error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(eraseBgaEvent(onLane:y:));
- (BOOL)convertResolution:(NSInteger)newResolution
                    error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(convertResolution(_:));
- (BOOL)resolutionConversionLosesInformation:(NSInteger)newResolution
    NS_SWIFT_NAME(resolutionConversionLosesInformation(_:));
- (NSInteger)acceptableResolutionDivider;

@end

NS_ASSUME_NONNULL_END
