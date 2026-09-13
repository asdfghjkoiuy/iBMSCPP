#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const IBMSDocumentBridgeErrorDomain;
FOUNDATION_EXPORT NSUInteger IBMSNSStringEncodingEucKR(void);

typedef NS_ERROR_ENUM(IBMSDocumentBridgeErrorDomain, IBMSDocumentBridgeErrorCode) {
    IBMSDocumentBridgeErrorCodeInvalidKey = 1,
    IBMSDocumentBridgeErrorCodeCoreException = 2,
    IBMSDocumentBridgeErrorCodeInvalidGrid = 3,
};

@interface IBMSChartEvent : NSObject
@property(nonatomic, readonly) NSInteger measure;
@property(nonatomic, copy, readonly) NSString *channel;
@property(nonatomic, copy, readonly) NSString *token;
@property(nonatomic, readonly) int64_t fractionNumerator;
@property(nonatomic, readonly) int64_t fractionDenominator;
@property(nonatomic, readonly) double beat;
@property(nonatomic, copy, readonly) NSString *kind;
@property(nonatomic, readonly) NSUInteger sourceLine;
@property(nonatomic, readonly) NSInteger bgmLane;
@end

@interface IBMSChartMeasure : NSObject
@property(nonatomic, readonly) NSInteger measure;
@property(nonatomic, readonly) double start;
@property(nonatomic, readonly) double length;
@end

@interface IBMSChartDiagnostic : NSObject
/// This is the core's zero-based physical source-line value. A zero value can
/// also represent a chart-wide diagnostic; callers must not present it as an
/// unqualified user-facing line number.
@property(nonatomic, readonly) NSUInteger sourceLine;
@property(nonatomic, copy, readonly) NSString *message;
@end

@interface IBMSChartSnapshot : NSObject
@property(nonatomic, copy, readonly) NSArray<IBMSChartEvent *> *events;
@property(nonatomic, copy, readonly) NSArray<IBMSChartMeasure *> *measures;
@property(nonatomic, copy, readonly) NSArray<IBMSChartDiagnostic *> *diagnostics;
@property(nonatomic, readonly, getter=isEditable) BOOL editable;
@property(nonatomic, copy, readonly) NSString *editingReason;
@end

@interface IBMSLongNoteEndpoint : NSObject
@property(nonatomic, readonly) NSInteger measure;
@property(nonatomic, readonly) int64_t fractionNumerator;
@property(nonatomic, readonly) int64_t fractionDenominator;
@property(nonatomic, readonly) double beat;
@property(nonatomic, copy, readonly) NSString *token;
@property(nonatomic, readonly) NSUInteger sourceLine;
@end

@interface IBMSLongNote : NSObject
@property(nonatomic, copy, readonly) NSString *channel;
@property(nonatomic, readonly) IBMSLongNoteEndpoint *start;
@property(nonatomic, readonly) IBMSLongNoteEndpoint *end;
@property(nonatomic, copy, readonly) NSString *encoding;
@end

@interface IBMSLongNoteDiagnostic : NSObject
@property(nonatomic, readonly) NSUInteger sourceLine;
@property(nonatomic, copy, readonly) NSString *message;
@end

@interface IBMSLongNoteSnapshot : NSObject
@property(nonatomic, copy, readonly) NSArray<IBMSLongNote *> *notes;
@property(nonatomic, copy, readonly) NSArray<IBMSLongNoteDiagnostic *> *diagnostics;
@property(nonatomic, copy, readonly) NSString *lnobjToken;
@property(nonatomic, readonly, getter=isEditable) BOOL editable;
@property(nonatomic, copy, readonly) NSString *editingReason;
@end

@interface IBMSTimingEvent : NSObject
@property(nonatomic, readonly) NSInteger measure;
@property(nonatomic, readonly) int64_t fractionNumerator;
@property(nonatomic, readonly) int64_t fractionDenominator;
@property(nonatomic, readonly) int64_t beatNumerator;
@property(nonatomic, readonly) int64_t beatDenominator;
@property(nonatomic, copy, readonly) NSString *valueDecimal;
@property(nonatomic, copy, readonly) NSString *kind;
@property(nonatomic, copy, readonly) NSString *channel;
@property(nonatomic, copy, readonly) NSString *token;
@property(nonatomic, readonly) NSUInteger sourceLine;
@property(nonatomic, readonly) BOOL hasTime;
@property(nonatomic, readonly) double secondsBeforeStop;
@property(nonatomic, readonly) double secondsAfterStop;
@end

@interface IBMSTimingMeasure : NSObject
@property(nonatomic, readonly) NSInteger measure;
@property(nonatomic, copy, readonly) NSString *ratioDecimal;
@end

@interface IBMSTimingDiagnostic : NSObject
/// This is the core's zero-based physical source-line value. A zero value can
/// also represent a timing-wide diagnostic.
@property(nonatomic, readonly) NSUInteger sourceLine;
@property(nonatomic, copy, readonly) NSString *message;
@end

@interface IBMSTimingSnapshot : NSObject
@property(nonatomic, copy, readonly) NSString *initialBPMDecimal;
@property(nonatomic, copy, readonly) NSArray<IBMSTimingEvent *> *events;
@property(nonatomic, copy, readonly) NSArray<IBMSTimingMeasure *> *measures;
@property(nonatomic, copy, readonly) NSArray<IBMSTimingDiagnostic *> *diagnostics;
@property(nonatomic, readonly, getter=isAvailable) BOOL available;
@property(nonatomic, copy, readonly) NSString *unavailableReason;
@end

@interface IBMSSaveBmsReport : NSObject
@property(nonatomic, copy, readonly) NSData *data;
@property(nonatomic, readonly) BOOL overlapping;
@property(nonatomic, readonly) NSInteger bpmCount;
@property(nonatomic, readonly) NSInteger stopCount;
@property(nonatomic, readonly) NSInteger scrollCount;
@end

@interface IBMSDocumentBridge : NSObject

/// iBMSC `BPMx1296` / `STOPx1296`. Off writes and reads hex `01`–`FF`.
+ (void)setIndexedTimingRadixBpm:(BOOL)bpmX1296
                            stop:(BOOL)stopX1296
    NS_SWIFT_NAME(setIndexedTimingRadix(bpm:stop:));

- (nullable instancetype)initWithData:(NSData *)data error:(NSError * _Nullable * _Nullable)error;
- (nullable NSData *)serializedDataWithError:(NSError * _Nullable * _Nullable)error;
/// `ChartIO.SaveBMS`. Conditional files still return `serialize()` bytes.
- (nullable NSData *)saveBmsDataWithNTInput:(BOOL)ntInput
                                      error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(saveBmsData(ntInput:));
- (nullable IBMSSaveBmsReport *)saveBmsReportWithNTInput:(BOOL)ntInput
                                              gridLimit:(double)gridLimit
                                                  error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(saveBmsReport(ntInput:gridLimit:));
// A missing header is represented by empty data. This avoids ambiguity in Swift's NSError import.
- (NSData *)headerDataForKey:(NSString *)key error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setHeaderData:(NSData *)data forKey:(NSString *)key error:(NSError * _Nullable * _Nullable)error;
- (nullable NSData *)expansionDataWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)setExpansionData:(NSData *)data error:(NSError * _Nullable * _Nullable)error;

// Returns a copied display snapshot. Exact fractions remain available for edits.
- (nullable IBMSChartSnapshot *)chartSnapshotWithError:(NSError * _Nullable * _Nullable)error;
// Returns core-paired long notes. Swift never infers endpoint pairing from
// chart events, and retains the exact source-row fractions for all mutations.
- (nullable IBMSLongNoteSnapshot *)longNoteSnapshotWithError:(NSError * _Nullable * _Nullable)error;
// Returns a copied timing snapshot. Decimal values and coordinates are exact;
// doubles are reserved for the core-provided display times.
- (nullable IBMSTimingSnapshot *)timingSnapshotWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)setInitialBPM:(NSString *)decimal error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setMeasureRatio:(NSInteger)measure decimal:(NSString *)decimal error:(NSError * _Nullable * _Nullable)error;
- (BOOL)applyBeatToMeasures:(NSArray<NSNumber *> *)measures
                     decimal:(NSString *)decimal
                        mode:(NSInteger)mode
                       error:(NSError * _Nullable * _Nullable)error;
- (BOOL)insertTimingEventAtMeasure:(NSInteger)measure
                            channel:(NSString *)channel
                  fractionNumerator:(int64_t)numerator
                fractionDenominator:(int64_t)denominator
                            decimal:(NSString *)decimal
                              error:(NSError * _Nullable * _Nullable)error;
- (BOOL)insertTimingEventAtMeasure:(NSInteger)measure
                            channel:(NSString *)channel
                           gridSlot:(NSInteger)gridSlot
                       gridDivision:(NSInteger)gridDivision
                            decimal:(NSString *)decimal
                              error:(NSError * _Nullable * _Nullable)error;
- (BOOL)replaceTimingEventAtMeasure:(NSInteger)measure
                             channel:(NSString *)channel
                   fractionNumerator:(int64_t)numerator
                 fractionDenominator:(int64_t)denominator
                             decimal:(NSString *)decimal
                               error:(NSError * _Nullable * _Nullable)error;
- (BOOL)eraseTimingEventAtMeasure:(NSInteger)measure
                           channel:(NSString *)channel
                 fractionNumerator:(int64_t)numerator
               fractionDenominator:(int64_t)denominator
                             error:(NSError * _Nullable * _Nullable)error;
- (BOOL)insertNoteAtMeasure:(NSInteger)measure
                    channel:(NSString *)channel
                   gridSlot:(NSInteger)gridSlot
               gridDivision:(NSInteger)gridDivision
                      token:(NSString *)token
                      error:(NSError * _Nullable * _Nullable)error;
- (BOOL)insertNoteAtMeasure:(NSInteger)measure
                    channel:(NSString *)channel
          fractionNumerator:(int64_t)numerator
        fractionDenominator:(int64_t)denominator
                      token:(NSString *)token
                      error:(NSError * _Nullable * _Nullable)error;
- (BOOL)eraseNoteAtMeasure:(NSInteger)measure
                   channel:(NSString *)channel
         fractionNumerator:(int64_t)numerator
       fractionDenominator:(int64_t)denominator
                     error:(NSError * _Nullable * _Nullable)error;
- (BOOL)moveNoteAtMeasure:(NSInteger)sourceMeasure
                  channel:(NSString *)sourceChannel
        fractionNumerator:(int64_t)sourceNumerator
      fractionDenominator:(int64_t)sourceDenominator
                toMeasure:(NSInteger)destinationMeasure
                  channel:(NSString *)destinationChannel
                 gridSlot:(NSInteger)gridSlot
             gridDivision:(NSInteger)gridDivision
                    error:(NSError * _Nullable * _Nullable)error;
- (BOOL)moveNoteAtMeasure:(NSInteger)sourceMeasure
                  channel:(NSString *)sourceChannel
        fractionNumerator:(int64_t)sourceNumerator
      fractionDenominator:(int64_t)sourceDenominator
                toMeasure:(NSInteger)destinationMeasure
                  channel:(NSString *)destinationChannel
        fractionNumerator:(int64_t)destinationNumerator
      fractionDenominator:(int64_t)destinationDenominator
                    error:(NSError * _Nullable * _Nullable)error;
- (BOOL)insertLongNoteOnChannel:(NSString *)channel
                    startMeasure:(NSInteger)startMeasure
                   startGridSlot:(NSInteger)startGridSlot
               startGridDivision:(NSInteger)startGridDivision
                      endMeasure:(NSInteger)endMeasure
                 endGridSlot:(NSInteger)endGridSlot
             endGridDivision:(NSInteger)endGridDivision
                   startToken:(NSString *)startToken
                     endToken:(NSString *)endToken
                         error:(NSError * _Nullable * _Nullable)error;
- (BOOL)insertLongNoteOnChannel:(NSString *)channel
                    startMeasure:(NSInteger)startMeasure
               startNumerator:(int64_t)startNumerator
             startDenominator:(int64_t)startDenominator
                      endMeasure:(NSInteger)endMeasure
                 endNumerator:(int64_t)endNumerator
               endDenominator:(int64_t)endDenominator
                   startToken:(NSString *)startToken
                     endToken:(NSString *)endToken
                         error:(NSError * _Nullable * _Nullable)error;
- (BOOL)moveLongNoteOnChannel:(NSString *)sourceChannel
                  startMeasure:(NSInteger)sourceMeasure
              startNumerator:(int64_t)sourceNumerator
            startDenominator:(int64_t)sourceDenominator
           destinationChannel:(NSString *)destinationChannel
       destinationStartMeasure:(NSInteger)startMeasure
      destinationStartGridSlot:(NSInteger)startGridSlot
  destinationStartGridDivision:(NSInteger)startGridDivision
                         error:(NSError * _Nullable * _Nullable)error;
- (BOOL)moveLongNoteStartOnChannel:(NSString *)channel
                       startMeasure:(NSInteger)sourceMeasure
                   startNumerator:(int64_t)sourceNumerator
                 startDenominator:(int64_t)sourceDenominator
            destinationStartMeasure:(NSInteger)startMeasure
           destinationStartGridSlot:(NSInteger)startGridSlot
       destinationStartGridDivision:(NSInteger)startGridDivision
                              error:(NSError * _Nullable * _Nullable)error;
- (BOOL)resizeLongNoteOnChannel:(NSString *)channel
                    startMeasure:(NSInteger)startMeasure
                  startNumerator:(int64_t)startNumerator
                startDenominator:(int64_t)startDenominator
                      endMeasure:(NSInteger)endMeasure
                 endGridSlot:(NSInteger)endGridSlot
             endGridDivision:(NSInteger)endGridDivision
                           error:(NSError * _Nullable * _Nullable)error;
- (BOOL)eraseLongNoteOnChannel:(NSString *)channel
                   startMeasure:(NSInteger)startMeasure
                 startNumerator:(int64_t)startNumerator
               startDenominator:(int64_t)startDenominator
                           error:(NSError * _Nullable * _Nullable)error;

- (BOOL)undoWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)redoWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)canUndo;
- (BOOL)canRedo;
- (BOOL)isDirty;
- (nullable NSNumber *)conditionalStateWithError:(NSError * _Nullable * _Nullable)error;
- (void)markSaved;
- (void)discardHistory;
- (BOOL)beginCompoundWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)endCompoundWithError:(NSError * _Nullable * _Nullable)error;
- (void)abortCompound;
- (NSUInteger)lineCount;

@end

NS_ASSUME_NONNULL_END
