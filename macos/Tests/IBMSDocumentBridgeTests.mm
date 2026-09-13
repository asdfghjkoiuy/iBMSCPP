#import <Foundation/Foundation.h>

#import "IBMSDocumentBridge.h"

#include <cstdlib>
#include <cstring>
#include <iostream>

namespace {

void require(bool condition, const char *message) {
    if (!condition) {
        std::cerr << message << '\n';
        std::exit(EXIT_FAILURE);
    }
}

}  // namespace

int main() {
    @autoreleasepool {
        NSError *error = nil;
        IBMSDocumentBridge *empty = [[IBMSDocumentBridge alloc] initWithData:[NSData data] error:&error];
        require(empty != nil && error == nil && empty.lineCount == 0, "Empty document loading failed.");
        NSData *missing = [empty headerDataForKey:@"TITLE" error:&error];
        require(missing != nil && missing.length == 0 && error == nil, "Missing headers must return empty data.");
        NSData *invalidKey = [empty headerDataForKey:@"TÍTLE" error:&error];
        require(invalidKey != nil && invalidKey.length == 0 && error != nil, "Non-ASCII keys must report an error.");

        const unsigned char sourceBytes[] = "#TITLE \x82\xa0\n#ARTIST Artist\n";
        NSData *source = [NSData dataWithBytes:sourceBytes length:sizeof(sourceBytes) - 1];
        error = nil;
        IBMSDocumentBridge *document = [[IBMSDocumentBridge alloc] initWithData:source error:&error];
        require(document != nil && error == nil, "Document loading failed.");
        require(!document.isDirty, "A loaded document must begin clean.");

        NSData *title = [document headerDataForKey:@"TITLE" error:&error];
        require(title != nil && title.length == 2 && std::memcmp(title.bytes, "\x82\xa0", 2) == 0,
                "Header bytes were not preserved.");

        NSData *replacement = [NSData dataWithBytes:"\x82\xa2" length:2];
        require([document setHeaderData:replacement forKey:@"TITLE" error:&error] && error == nil,
                "Metadata editing failed.");
        require(document.isDirty && document.canUndo, "Edit state was not recorded for undo.");
        NSData *invalidValue = [NSData dataWithBytes:"bad\nvalue" length:9];
        error = nil;
        require(![document setHeaderData:invalidValue forKey:@"TITLE" error:&error] && error != nil,
                "Invalid metadata must report an error.");
        error = nil;
        require([document undoWithError:&error] && error == nil && !document.isDirty && document.canRedo,
                "Undo after a failed edit did not restore the clean state.");
        require([document redoWithError:&error] && error == nil && document.isDirty,
                "Redo did not restore the edit.");

        NSData *serialized = [document serializedDataWithError:&error];
        require(serialized != nil && error == nil, "Serialization failed.");
        [document markSaved];
        require(!document.isDirty, "markSaved did not clear dirty state after serialization.");

        NSData *chartSource = [@"#00016:0001\n#00102:.5\n" dataUsingEncoding:NSASCIIStringEncoding];
        error = nil;
        IBMSDocumentBridge *chartDocument = [[IBMSDocumentBridge alloc] initWithData:chartSource error:&error];
        IBMSChartSnapshot *chart = [chartDocument chartSnapshotWithError:&error];
        require(chart != nil && error == nil && chart.events.count == 1 && chart.measures.count == 1000,
                "Core chart data did not reach the native bridge.");
        IBMSChartEvent *sourceEvent = chart.events.firstObject;
        require([sourceEvent.channel isEqualToString:@"16"] && [sourceEvent.token isEqualToString:@"01"]
                    && sourceEvent.fractionNumerator == 1 && sourceEvent.fractionDenominator == 2,
                "The bridge changed the raw normal-note coordinate.");
        require([chartDocument insertNoteAtMeasure:1 channel:@"16" gridSlot:7 gridDivision:16 token:@"0A" error:&error] && error == nil,
                "Bridge grid insertion failed.");
        chart = [chartDocument chartSnapshotWithError:&error];
        require(chart.events.count == 2 && chartDocument.isDirty && chartDocument.canUndo,
                "Inserted note did not refresh core chart state and history.");
        require([chartDocument undoWithError:&error] && error == nil,
                "Undo after bridge chart insertion failed.");
        chart = [chartDocument chartSnapshotWithError:&error];
        require(chart.events.count == 1 && chartDocument.canRedo,
                "Undo did not refresh the bridge chart snapshot.");

        NSData *longNoteSource = [@"#00051:000001000001\n#00102:1.5\n" dataUsingEncoding:NSASCIIStringEncoding];
        error = nil;
        IBMSDocumentBridge *longNoteDocument = [[IBMSDocumentBridge alloc] initWithData:longNoteSource error:&error];
        IBMSLongNoteSnapshot *longNotes = [longNoteDocument longNoteSnapshotWithError:&error];
        require(longNotes != nil && error == nil && longNotes.notes.count == 1 && longNotes.isEditable,
                "Core long-note pairs did not reach the native bridge.");
        IBMSLongNote *longNote = longNotes.notes.firstObject;
        require([longNote.channel isEqualToString:@"51"]
                    && longNote.start.fractionNumerator == 1 && longNote.start.fractionDenominator == 3
                    && longNote.end.fractionNumerator == 5 && longNote.end.fractionDenominator == 6,
                "The bridge changed a paired long note's raw endpoints.");
        require([longNoteDocument moveLongNoteOnChannel:@"51"
                                           startMeasure:0
                                       startNumerator:1
                                     startDenominator:3
                                    destinationChannel:@"51"
                                destinationStartMeasure:1
                               destinationStartGridSlot:4
                           destinationStartGridDivision:16
                                                  error:&error] && error == nil,
                "The bridge could not move a long note.");
        longNotes = [longNoteDocument longNoteSnapshotWithError:&error];
        longNote = longNotes.notes.firstObject;
        require(longNote.start.measure == 1 && longNote.start.fractionNumerator == 1 && longNote.start.fractionDenominator == 6
                    && longNote.end.measure == 1 && longNote.end.fractionNumerator == 1 && longNote.end.fractionDenominator == 2,
                "A long-note body move quantized its exact duration across a ratio measure.");
        require([longNoteDocument moveLongNoteStartOnChannel:@"51"
                                                startMeasure:1
                                            startNumerator:1
                                          startDenominator:6
                                     destinationStartMeasure:1
                                    destinationStartGridSlot:5
                                destinationStartGridDivision:16
                                                       error:&error] && error == nil,
                "The bridge could not move the start cap.");
        longNotes = [longNoteDocument longNoteSnapshotWithError:&error];
        longNote = longNotes.notes.firstObject;
        require(longNote.start.fractionNumerator == 5 && longNote.start.fractionDenominator == 24
                    && longNote.end.fractionNumerator == 1 && longNote.end.fractionDenominator == 2,
                "Moving the start cap changed the exact tail coordinate.");
        require([longNoteDocument resizeLongNoteOnChannel:@"51"
                                             startMeasure:1
                                           startNumerator:5
                                         startDenominator:24
                                               endMeasure:1
                                          endGridSlot:12
                                      endGridDivision:16
                                                    error:&error] && error == nil,
                "The bridge could not resize a long-note end cap.");
        require([longNoteDocument eraseLongNoteOnChannel:@"51"
                                             startMeasure:1
                                           startNumerator:5
                                         startDenominator:24
                                                    error:&error] && error == nil
                    && longNoteDocument.isDirty && longNoteDocument.canUndo,
                "Long-note deletion did not share dirty state and undo history.");
        require([longNoteDocument undoWithError:&error] && error == nil,
                "Undo after a long-note deletion failed.");
        longNotes = [longNoteDocument longNoteSnapshotWithError:&error];
        require(longNotes.notes.count == 1,
                "Shared undo did not restore the resized long note.");

        NSData *lnobjSource = [@"#LNOBJ AA\n" dataUsingEncoding:NSASCIIStringEncoding];
        error = nil;
        IBMSDocumentBridge *lnobjDocument = [[IBMSDocumentBridge alloc] initWithData:lnobjSource error:&error];
        require([lnobjDocument insertLongNoteOnChannel:@"11"
                                          startMeasure:0
                                         startGridSlot:0
                                     startGridDivision:16
                                            endMeasure:0
                                           endGridSlot:4
                                       endGridDivision:16
                                         startToken:@"01"
                                           endToken:@""
                                               error:&error] && error == nil,
                "LNOBJ insertion on a normal playable channel failed.");
        longNotes = [lnobjDocument longNoteSnapshotWithError:&error];
        longNote = longNotes.notes.firstObject;
        require(longNotes != nil && [longNotes.lnobjToken isEqualToString:@"AA"]
                    && [longNote.channel isEqualToString:@"11"] && [longNote.encoding isEqualToString:@"lnobj"]
                    && [longNote.start.token isEqualToString:@"01"] && [longNote.end.token isEqualToString:@"AA"],
                "LNOBJ insertion did not preserve normal-channel and marker endpoint encoding.");

        NSData *offGridSource = [@"#00051:010100\n#00102:1.5\n" dataUsingEncoding:NSASCIIStringEncoding];
        error = nil;
        IBMSDocumentBridge *offGridDocument = [[IBMSDocumentBridge alloc] initWithData:offGridSource error:&error];
        require([offGridDocument moveLongNoteOnChannel:@"51"
                                          startMeasure:0
                                      startNumerator:0
                                    startDenominator:1
                                   destinationChannel:@"52"
                               destinationStartMeasure:1
                              destinationStartGridSlot:4
                          destinationStartGridDivision:16
                                                 error:&error] && error == nil,
                "An off-grid long-note body could not move to another long channel.");
        longNotes = [offGridDocument longNoteSnapshotWithError:&error];
        longNote = longNotes.notes.firstObject;
        require([longNote.channel isEqualToString:@"52"]
                    && longNote.start.measure == 1 && longNote.start.fractionNumerator == 1 && longNote.start.fractionDenominator == 6
                    && longNote.end.measure == 1 && longNote.end.fractionNumerator == 7 && longNote.end.fractionDenominator == 18,
                "Moving a 0-to-1/3 long note on a 16 grid quantized its off-grid tail or lost its channel.");

        NSData *timingSource = [@"#BPM 120.1\n#BPM01 127.125\n#BPM02 0.000000000000000001\n#STOP01 0.01\n#STOP02 0.000000000000000001\n#00008:0102\n#00109:0102\n#00202:0.1\n"
            dataUsingEncoding:NSASCIIStringEncoding];
        error = nil;
        IBMSDocumentBridge *timingDocument = [[IBMSDocumentBridge alloc] initWithData:timingSource error:&error];
        IBMSTimingSnapshot *timing = [timingDocument timingSnapshotWithError:&error];
        require(timing != nil && error == nil && timing.isAvailable,
                "Core timing data did not reach the native bridge.");
        require([timing.initialBPMDecimal isEqualToString:@"120.1"]
                    && timing.measures.count == 1000
                    && [timing.measures[2].ratioDecimal isEqualToString:@"0.1"],
                "The bridge changed exact initial BPM or measure-ratio decimals.");
        require(timing.events.count == 4,
                "The bridge did not expose all BPM and STOP events.");
        IBMSTimingEvent *firstTimingEvent = timing.events[0];
        require(firstTimingEvent.measure == 0
                    && [firstTimingEvent.channel isEqualToString:@"08"]
                    && firstTimingEvent.fractionNumerator == 0
                    && firstTimingEvent.fractionDenominator == 1
                    && [firstTimingEvent.valueDecimal isEqualToString:@"127.125"],
                "The bridge changed an exact timing event coordinate or decimal value.");
        IBMSTimingEvent *tinyBPM = timing.events[1];
        require([tinyBPM.valueDecimal isEqualToString:@"0.000000000000000001"],
                "The bridge rounded an exact 1e-18-scale BPM value.");
        IBMSTimingEvent *stopEvent = timing.events[2];
        require([stopEvent.kind isEqualToString:@"stop"]
                    && [stopEvent.valueDecimal isEqualToString:@"0.01"]
                    && stopEvent.hasTime
                    && stopEvent.secondsAfterStop > stopEvent.secondsBeforeStop,
                "The bridge did not preserve STOP values or core-provided times.");
        IBMSTimingEvent *tinyStop = timing.events[3];
        require([tinyStop.valueDecimal isEqualToString:@"0.000000000000000001"],
                "The bridge rounded an exact 1e-18-scale STOP value.");

        error = nil;
        require([timingDocument setInitialBPM:@"121.25" error:&error] && error == nil,
                "The bridge could not edit the initial BPM.");
        require([timingDocument setMeasureRatio:2 decimal:@"0.25" error:&error] && error == nil,
                "The bridge could not scale a measure ratio.");
        require([timingDocument insertTimingEventAtMeasure:3
                                                   channel:@"08"
                                         fractionNumerator:1
                                       fractionDenominator:3
                                                   decimal:@"222.5"
                                                     error:&error] && error == nil,
                "The bridge could not add an exact decimal BPM event.");
        timing = [timingDocument timingSnapshotWithError:&error];
        require(timing != nil && [timing.initialBPMDecimal isEqualToString:@"121.25"]
                    && [timing.measures[2].ratioDecimal isEqualToString:@"0.25"],
                "Timing edits did not refresh the bridge snapshot.");
        IBMSTimingEvent *added = timing.events.lastObject;
        require(added.measure == 3 && [added.channel isEqualToString:@"08"]
                    && added.fractionNumerator == 1 && added.fractionDenominator == 3
                    && [added.valueDecimal isEqualToString:@"222.5"],
                "The bridge changed an inserted timing event's exact coordinate or value.");
        require([timingDocument replaceTimingEventAtMeasure:added.measure
                                                    channel:added.channel
                                          fractionNumerator:added.fractionNumerator
                                        fractionDenominator:added.fractionDenominator
                                                    decimal:@"223.125"
                                                      error:&error] && error == nil,
                "The bridge could not replace a selected timing event.");
        timing = [timingDocument timingSnapshotWithError:&error];
        added = timing.events.lastObject;
        require([added.valueDecimal isEqualToString:@"223.125"],
                "Replacing a timing event did not preserve its exact decimal value.");
        require([timingDocument eraseTimingEventAtMeasure:added.measure
                                                   channel:added.channel
                                         fractionNumerator:added.fractionNumerator
                                       fractionDenominator:added.fractionDenominator
                                                     error:&error] && error == nil,
                "The bridge could not delete a selected timing event.");
        timing = [timingDocument timingSnapshotWithError:&error];
        require(timing.events.count == 4 && timingDocument.isDirty && timingDocument.canUndo,
                "Timing deletion did not share document dirty state and undo history.");
        require([timingDocument undoWithError:&error] && error == nil,
                "Undo after a timing deletion failed.");
        timing = [timingDocument timingSnapshotWithError:&error];
        require(timing.events.count == 5 && [timing.events.lastObject.valueDecimal isEqualToString:@"223.125"],
                "Shared undo did not restore the deleted exact timing event.");
    }
    return EXIT_SUCCESS;
}
