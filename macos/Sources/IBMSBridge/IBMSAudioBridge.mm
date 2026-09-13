#import "IBMSAudioBridge.h"

#include <ibms/audio_decode.hpp>

#include <exception>
#include <string>

NSErrorDomain const IBMSAudioBridgeErrorDomain = @"org.ibmsc.native.audio-bridge";

namespace {

NSError *makeError(NSString *description) {
    return [NSError errorWithDomain:IBMSAudioBridgeErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

}  // namespace

@implementation IBMSAudioBridge

+ (NSData *)pcmWavFromAudioFile:(NSString *)path error:(NSError * _Nullable * _Nullable)error {
    try {
        const auto decoded = ibms::decode_audio_file(std::string(path.UTF8String ?: ""));
        if (!decoded.has_value()) {
            if (error != nullptr) {
                *error = makeError(@"The audio file could not be decoded.");
            }
            return nil;
        }
        const auto wav = ibms::encode_pcm16_wav(*decoded);
        return [NSData dataWithBytes:wav.data() length:wav.size()];
    } catch (const std::exception& exception) {
        if (error != nullptr) {
            NSString *text = exception.what()[0] != '\0'
                ? [NSString stringWithUTF8String:exception.what()]
                : @"The audio file could not be decoded.";
            *error = makeError(text);
        }
        return nil;
    } catch (...) {
        if (error != nullptr) {
            *error = makeError(@"The audio file could not be decoded.");
        }
        return nil;
    }
}

@end
