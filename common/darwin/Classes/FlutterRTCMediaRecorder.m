#import <WebRTC/WebRTC.h>
#import "FlutterRTCMediaRecorder.h"
#import "FlutterRTCAudioSink.h"
#import "FlutterRTCFrameCapturer.h"
#import "FlutterWebRTCPlugin.h"
#import "AudioManager.h"

// Simple renderer to receive processed PCM from AudioProcessingAdapter
@interface _FlutterRTCAudioPCMRenderer : NSObject <RTCAudioRenderer>
@property(nonatomic, copy) void (^onPCM)(AVAudioPCMBuffer* buffer);
@end

@implementation _FlutterRTCAudioPCMRenderer
- (void)renderPCMBuffer:(AVAudioPCMBuffer *)audioBuffer {
    if (self.onPCM) {
        self.onPCM(audioBuffer);
    }
}
@end

@import AVFoundation;

@implementation FlutterRTCMediaRecorder {
    int framesCount;
    bool isInitialized;
    CGSize _renderSize;
    FlutterRTCAudioSink* _audioSink;
    AVAssetWriterInput* _audioWriter;
    int64_t _startTime;
    id<RTCAudioRenderer> _pcmRenderer;
    AVAudioEngine* _engine;
    BOOL _engineRunning;
}

- (instancetype)initWithVideoTrack:(RTCVideoTrack *)video audioTrack:(RTCAudioTrack *)audio outputFile:(NSURL *)out recorderId:(NSNumber *)recorderId {
    self = [super init];
    isInitialized = false;
    self.videoTrack = video;
    self.output = out;
    self.recorderId = recorderId;
    [video addRenderer:self];
    framesCount = 0;
    if (audio != nil) {
        NSLog(@"[Recorder:%@] attaching audio track id=%@", recorderId, audio.trackId);
        _audioSink = [[FlutterRTCAudioSink alloc] initWithAudioTrack:audio];
        __weak typeof(self) weakSelf = self;
        // Set early PCM callback so events are emitted even before writer initialization
        _audioSink.bufferCallback = ^(CMSampleBufferRef buffer){
            if ([FlutterWebRTCPlugin sharedSingleton].eventSink != nil) {
                CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(buffer);
                size_t length = 0;
                char* dataPointer = NULL;
                if (CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &length, &dataPointer) == kCMBlockBufferNoErr && length > 0) {
                    NSLog(@"[Recorder:%@] early PCM len=%zu", weakSelf.recorderId, length);
                    NSData* pcm = [NSData dataWithBytes:dataPointer length:length];
                    CMAudioFormatDescriptionRef fmtDesc = (CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(buffer);
                    const AudioStreamBasicDescription* asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc);
                    NSNumber* sampleRate = asbd ? @((int)asbd->mSampleRate) : @44100;
                    NSNumber* channels = asbd ? @((int)asbd->mChannelsPerFrame) : @1;
                    NSNumber* bits = asbd ? @((int)asbd->mBitsPerChannel) : @16;
                    postEvent([FlutterWebRTCPlugin sharedSingleton].eventSink, @{
                            @"event": @"onAudioPcmData",
                            @"recorderId": weakSelf.recorderId ?: @(-1),
                            @"sampleRate": sampleRate,
                            @"numOfChannels": channels,
                            @"bitsPerSample": bits,
                            @"data": [FlutterStandardTypedData typedDataWithBytes:pcm]
                    });
                }
            }
        };
    } else
        NSLog(@"Audio track is nil");
    _startTime = -1;
    return self;
}

- (void)attachAudioTrack:(RTCAudioTrack* _Nonnull)audioTrack {
    if (_audioSink != nil) {
        [_audioSink close];
    }
    NSLog(@"[Recorder:%@] re-attaching audio track id=%@", self.recorderId, audioTrack.trackId);
    _audioSink = [[FlutterRTCAudioSink alloc] initWithAudioTrack:audioTrack];
    __weak typeof(self) weakSelf = self;
    _audioSink.bufferCallback = ^(CMSampleBufferRef buffer){
        if ([FlutterWebRTCPlugin sharedSingleton].eventSink != nil) {
            CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(buffer);
            size_t length = 0;
            char* dataPointer = NULL;
            if (CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &length, &dataPointer) == kCMBlockBufferNoErr && length > 0) {
                NSData* pcm = [NSData dataWithBytes:dataPointer length:length];
                CMAudioFormatDescriptionRef fmtDesc = (CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(buffer);
                const AudioStreamBasicDescription* asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc);
                NSNumber* sampleRate = asbd ? @((int)asbd->mSampleRate) : @44100;
                NSNumber* channels = asbd ? @((int)asbd->mChannelsPerFrame) : @1;
                NSNumber* bits = asbd ? @((int)asbd->mBitsPerChannel) : @16;
                postEvent([FlutterWebRTCPlugin sharedSingleton].eventSink, @{
                        @"event": @"onAudioPcmData",
                        @"recorderId": weakSelf.recorderId ?: @(-1),
                        @"sampleRate": sampleRate,
                        @"numOfChannels": channels,
                        @"bitsPerSample": bits,
                        @"data": [FlutterStandardTypedData typedDataWithBytes:pcm]
                });
            }
        }
    };
}

- (void)initialize:(CGSize)size {
    _renderSize = size;
    NSDictionary *videoSettings = @{
            AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(6*1024*1024)},
            AVVideoCodecKey: AVVideoCodecTypeH264,
            AVVideoHeightKey: @(size.height),
            AVVideoWidthKey: @(size.width),
    };
    self.writerInput = [[AVAssetWriterInput alloc]
            initWithMediaType:AVMediaTypeVideo
               outputSettings:videoSettings];
    self.writerInput.expectsMediaDataInRealTime = true;
    self.writerInput.mediaTimeScale = 30;

    if (_audioSink != nil) {
        AudioChannelLayout acl;
        bzero(&acl, sizeof(acl));
        acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
        NSDictionary* audioSettings = @{
                AVFormatIDKey: [NSNumber numberWithInt: kAudioFormatMPEG4AAC],
                AVNumberOfChannelsKey: @1,
                AVSampleRateKey: @44100.0,
                AVChannelLayoutKey: [NSData dataWithBytes:&acl length:sizeof(AudioChannelLayout)],
                AVEncoderBitRateKey: @64000,
        };
        _audioWriter = [[AVAssetWriterInput alloc]
                initWithMediaType:AVMediaTypeAudio
                   outputSettings:audioSettings
                 sourceFormatHint:_audioSink.format];
        _audioWriter.expectsMediaDataInRealTime = true;
    }

    NSError *error;
    self.assetWriter = [[AVAssetWriter alloc]
            initWithURL:self.output
               fileType:AVFileTypeMPEG4
                  error:&error];
    if (error != nil)
        NSLog(@"%@",[error localizedDescription]);
    self.assetWriter.shouldOptimizeForNetworkUse = true;
    [self.assetWriter addInput:self.writerInput];
    if (_audioWriter != nil) {
        [self.assetWriter addInput:_audioWriter];
        _audioSink.bufferCallback = ^(CMSampleBufferRef buffer){

            // Always push PCM via event channel for real-time use
            if ([FlutterWebRTCPlugin sharedSingleton].eventSink != nil) {
                CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(buffer);
                size_t length = 0;
                char* dataPointer = NULL;

                if (CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &length, &dataPointer) == kCMBlockBufferNoErr && length > 0) {
                    NSLog(@"[Recorder:%@] PCM len=%zu", self.recorderId, length);
                    NSData* pcm = [NSData dataWithBytes:dataPointer length:length];
                    CMAudioFormatDescriptionRef fmtDesc = (CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(buffer);
                    const AudioStreamBasicDescription* asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc);
                    NSNumber* sampleRate = asbd ? @((int)asbd->mSampleRate) : @44100;
                    NSNumber* channels = asbd ? @((int)asbd->mChannelsPerFrame) : @1;
                    NSNumber* bits = asbd ? @((int)asbd->mBitsPerChannel) : @16;
                    postEvent([FlutterWebRTCPlugin sharedSingleton].eventSink, @{
                            @"event": @"onAudioPcmData",
                            @"recorderId": self.recorderId ?: @(-1),
                            @"sampleRate": sampleRate,
                            @"numOfChannels": channels,
                            @"bitsPerSample": bits,
                            @"data": [FlutterStandardTypedData typedDataWithBytes:pcm]
                    });
                }
            }

            // Try append to writer if ready
            if (self->_audioWriter.readyForMoreMediaData) {
                if (![self->_audioWriter appendSampleBuffer:buffer]) {
                    NSLog(@"Audioframe not appended %@", self.assetWriter.error);
                }
            }
        };
    }
    [self.assetWriter startWriting];
    [self.assetWriter startSessionAtSourceTime:kCMTimeZero];

    // Attach a PCM renderer to capture processed frames from AudioProcessingAdapter as a fallback
    _FlutterRTCAudioPCMRenderer* renderer = [[_FlutterRTCAudioPCMRenderer alloc] init];
    __weak typeof(self) weakSelf = self;
    renderer.onPCM = ^(AVAudioPCMBuffer *buffer) {
        if ([FlutterWebRTCPlugin sharedSingleton].eventSink != nil && buffer) {
            AVAudioFrameCount frames = buffer.frameLength;
            AVAudioChannelCount channels = buffer.format.channelCount;
            int sampleRate = (int)buffer.format.sampleRate;
            size_t length = frames * channels * sizeof(int16_t);
            NSMutableData* data = [NSMutableData dataWithLength:length];
            AVAudioCommonFormat fmt = buffer.format.commonFormat;
            for (int ch = 0; ch < channels; ch++) {
                int16_t* dst = (int16_t*)data.mutableBytes + ch;
                if (fmt == AVAudioPCMFormatInt16 && buffer.int16ChannelData != NULL) {
                    int16_t* src = (int16_t*)buffer.int16ChannelData[ch];
                    for (int i = 0; i < frames; i++) {
                        dst[i*channels] = src[i];
                    }
                } else if (fmt == AVAudioPCMFormatFloat32 && buffer.floatChannelData != NULL) {
                    float* src = buffer.floatChannelData[ch];
                    for (int i = 0; i < frames; i++) {
                        float sample = src[i];
                        if (sample > 1.0f) sample = 1.0f;
                        if (sample < -1.0f) sample = -1.0f;
                        int16_t s = (int16_t)lrintf(sample * 32767.0f);
                        dst[i*channels] = s;
                    }
                } else if (fmt == AVAudioPCMFormatInt32 && buffer.int32ChannelData != NULL) {
                    int32_t* src = buffer.int32ChannelData[ch];
                    for (int i = 0; i < frames; i++) {
                        int32_t v = src[i] >> 16; // downscale 32->16
                        if (v > INT16_MAX) v = INT16_MAX;
                        if (v < INT16_MIN) v = INT16_MIN;
                        dst[i*channels] = (int16_t)v;
                    }
                }
            }
            postEvent([FlutterWebRTCPlugin sharedSingleton].eventSink, @{
                    @"event": @"onAudioPcmData",
                    @"recorderId": weakSelf.recorderId ?: @(-1),
                    @"sampleRate": @(sampleRate),
                    @"numOfChannels": @(channels),
                    @"bitsPerSample": @16,
                    @"data": [FlutterStandardTypedData typedDataWithBytes:data]
            });
        }
    };
    _pcmRenderer = renderer;
    [AudioManager.sharedInstance addLocalAudioRenderer:_pcmRenderer];
    // Fallback 2: Use AVAudioEngine tap to capture mic PCM if WebRTC sink path doesn't deliver
    @try {
        _engine = [[AVAudioEngine alloc] init];
        AVAudioInputNode* input = _engine.inputNode;
        if (input) {
            AVAudioFormat* format = [input outputFormatForBus:0];
            __weak typeof(self) weakSelf2 = self;
            [input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
                if ([FlutterWebRTCPlugin sharedSingleton].eventSink != nil && buffer) {
                    AVAudioFrameCount frames = buffer.frameLength;
                    AVAudioChannelCount channels = buffer.format.channelCount;
                    int sampleRate = (int)buffer.format.sampleRate;
                    size_t length = frames * channels * sizeof(int16_t);
                    NSMutableData* data = [NSMutableData dataWithLength:length];
                    AVAudioCommonFormat fmt = buffer.format.commonFormat;
                    for (int ch = 0; ch < channels; ch++) {
                        int16_t* dst = (int16_t*)data.mutableBytes + ch;
                        if (fmt == AVAudioPCMFormatInt16 && buffer.int16ChannelData != NULL) {
                            int16_t* src = (int16_t*)buffer.int16ChannelData[ch];
                            for (int i = 0; i < frames; i++) {
                                dst[i*channels] = src[i];
                            }
                        } else if (fmt == AVAudioPCMFormatFloat32 && buffer.floatChannelData != NULL) {
                            float* src = buffer.floatChannelData[ch];
                            for (int i = 0; i < frames; i++) {
                                float sample = src[i];
                                if (sample > 1.0f) sample = 1.0f;
                                if (sample < -1.0f) sample = -1.0f;
                                int16_t s = (int16_t)lrintf(sample * 32767.0f);
                                dst[i*channels] = s;
                            }
                        } else if (fmt == AVAudioPCMFormatInt32 && buffer.int32ChannelData != NULL) {
                            int32_t* src = buffer.int32ChannelData[ch];
                            for (int i = 0; i < frames; i++) {
                                int32_t v = src[i] >> 16; // downscale 32->16
                                if (v > INT16_MAX) v = INT16_MAX;
                                if (v < INT16_MIN) v = INT16_MIN;
                                dst[i*channels] = (int16_t)v;
                            }
                        }
                    }
                    postEvent([FlutterWebRTCPlugin sharedSingleton].eventSink, @{
                            @"event": @"onAudioPcmData",
                            @"recorderId": weakSelf2.recorderId ?: @(-1),
                            @"sampleRate": @(sampleRate),
                            @"numOfChannels": @(channels),
                            @"bitsPerSample": @16,
                            @"data": [FlutterStandardTypedData typedDataWithBytes:data]
                    });
                }
            }];
            [_engine prepare];
            NSError* err = nil;
            [_engine startAndReturnError:&err];
            if (err) {
                NSLog(@"[Recorder:%@] AVAudioEngine start error: %@", self.recorderId, err);
            } else {
                _engineRunning = YES;
                NSLog(@"[Recorder:%@] AVAudioEngine started", self.recorderId);
            }
        } else {
            NSLog(@"[Recorder:%@] AVAudioEngine input node is nil", self.recorderId);
        }
    } @catch (NSException* e) {
        NSLog(@"[Recorder:%@] AVAudioEngine exception: %@", self.recorderId, e);
    }

    isInitialized = true;
}

- (void)setSize:(CGSize)size {
}

- (void)renderFrame:(nullable RTCVideoFrame *)frame {
    if (frame == nil) {
        return;
    }
    if (!isInitialized) {
        [self initialize:CGSizeMake((CGFloat) frame.width, (CGFloat) frame.height)];
    }
    if (!self.writerInput.readyForMoreMediaData) {
        NSLog(@"Drop frame, not ready");
        return;
    }
    id <RTCVideoFrameBuffer> buffer = frame.buffer;
    CVPixelBufferRef pixelBufferRef;
    BOOL shouldRelease = false;
    if ([buffer isKindOfClass:[RTCCVPixelBuffer class]]) {
        pixelBufferRef = ((RTCCVPixelBuffer *) buffer).pixelBuffer;
    } else {
        pixelBufferRef = [FlutterRTCFrameCapturer convertToCVPixelBuffer:frame];
        shouldRelease = true;
    }
    CMVideoFormatDescriptionRef formatDescription;
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBufferRef, &formatDescription);

    CMSampleTimingInfo timingInfo;

    timingInfo.decodeTimeStamp = kCMTimeInvalid;
    if (_startTime == -1) {
        _startTime = frame.timeStampNs / 1000;
    }
    int64_t frameTime = (frame.timeStampNs / 1000) - _startTime;
    timingInfo.presentationTimeStamp = CMTimeMake(frameTime, 1000000);
    framesCount++;

    CMSampleBufferRef outBuffer;

    status = CMSampleBufferCreateReadyWithImageBuffer(
            kCFAllocatorDefault,
            pixelBufferRef,
            formatDescription,
            &timingInfo,
            &outBuffer
    );

    if (![self.writerInput appendSampleBuffer:outBuffer]) {
        NSLog(@"Frame not appended %@", self.assetWriter.error);
    }
#if TARGET_OS_IPHONE
    if (shouldRelease) {
        CVPixelBufferRelease(pixelBufferRef);
    }
#endif
}

- (void)stop:(FlutterResult _Nonnull) result {
    if (_audioSink != nil) {
        _audioSink.bufferCallback = nil;
        [_audioSink close];
    }
    if (_pcmRenderer != nil) {
        [AudioManager.sharedInstance removeLocalAudioRenderer:_pcmRenderer];
        _pcmRenderer = nil;
    }
    if (_engineRunning && _engine != nil) {
        AVAudioInputNode* input = _engine.inputNode;
        @try {
            [input removeTapOnBus:0];
        } @catch (NSException* e) {
        }
        [_engine stop];
        _engineRunning = NO;
        _engine = nil;
    }
    [self.videoTrack removeRenderer:self];
    [self.writerInput markAsFinished];
    [_audioWriter markAsFinished];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.assetWriter finishWritingWithCompletionHandler:^{
            NSError* error = self.assetWriter.error;
            if (error == nil) {
                result(nil);
            } else {
                result([FlutterError errorWithCode:@"Failed to save recording"
                                           message:[error localizedDescription]
                                           details:nil]);
            }
        }];
    });
}

@end
