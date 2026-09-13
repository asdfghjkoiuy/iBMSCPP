#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const IBMSAudioBridgeErrorDomain;

/// C++ `ibms::decode_audio_*` for preview / export. Not a BMS document.
@interface IBMSAudioBridge : NSObject

+ (nullable NSData *)pcmWavFromAudioFile:(NSString *)path
                                   error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(pcmWav(fromFile:));

@end

NS_ASSUME_NONNULL_END
