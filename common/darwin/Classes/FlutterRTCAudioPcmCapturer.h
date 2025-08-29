#if TARGET_OS_IPHONE
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <WebRTC/WebRTC.h>

@interface FlutterRTCAudioPcmCapturer : NSObject

@property(nonatomic, strong) NSNumber* recorderId;
@property(nonatomic, strong) RTCAudioTrack* audioTrack;
@property(nonatomic, strong) AVAudioEngine* audioEngine;
@property(nonatomic, strong) AVAudioInputNode* inputNode;
@property(nonatomic, assign) BOOL isCapturing;

- (instancetype)initWithRecorderId:(NSNumber*)recorderId 
                         audioTrack:(RTCAudioTrack*)audioTrack;

- (void)startCapturing;
- (void)stopCapturing;
- (void)attachAudioTrack:(RTCAudioTrack*)audioTrack;

@end

#endif
