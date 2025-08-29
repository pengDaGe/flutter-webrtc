#if TARGET_OS_IPHONE
#import "FlutterRTCAudioPcmCapturer.h"
#import "FlutterWebRTCPlugin.h"

@implementation FlutterRTCAudioPcmCapturer

- (instancetype)initWithRecorderId:(NSNumber*)recorderId 
                         audioTrack:(RTCAudioTrack*)audioTrack {
    self = [super init];
    if (self) {
        _recorderId = recorderId;
        _audioTrack = audioTrack;
        _isCapturing = NO;
        
        _audioEngine = [[AVAudioEngine alloc] init];
        _inputNode = _audioEngine.inputNode;
        
        NSLog(@"[AudioPcmCapturer:%@] 初始化完成", recorderId);
    }
    return self;
}

- (void)startCapturing {
    if (_isCapturing) {
        NSLog(@"[AudioPcmCapturer:%@] 已经在采集状态", _recorderId);
        return;
    }
    
    @try {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        NSError* error = nil;
        
        if (![session setCategory:AVAudioSessionCategoryPlayAndRecord
                     withOptions:AVAudioSessionCategoryOptionAllowBluetooth |
                                 AVAudioSessionCategoryOptionAllowBluetoothA2DP |
                                 AVAudioSessionCategoryOptionAllowAirPlay
                           error:&error]) {
            NSLog(@"[AudioPcmCapturer:%@] 设置音频会话类别失败: %@", _recorderId, error);
            return;
        }
        
        if (![session setActive:YES error:&error]) {
            NSLog(@"[AudioPcmCapturer:%@] 激活音频会话失败: %@", _recorderId, error);
            return;
        }
        
        AVAudioFormat* inputFormat = [_inputNode outputFormatForBus:0];
        NSLog(@"[AudioPcmCapturer:%@] 输入格式: 采样率=%.0f, 声道数=%lu, 格式=%@", 
              _recorderId, inputFormat.sampleRate, (unsigned long)inputFormat.channelCount, 
              [self stringForAudioFormat:inputFormat.commonFormat]);
        
        __weak typeof(self) weakSelf = self;
        [_inputNode installTapOnBus:0 
                         bufferSize:1024 
                             format:inputFormat 
                              block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
            [weakSelf processAudioBuffer:buffer];
        }];
        
        [_audioEngine prepare];
        if (![_audioEngine startAndReturnError:&error]) {
            NSLog(@"[AudioPcmCapturer:%@] 启动音频引擎失败: %@", _recorderId, error);
            return;
        }
        
        _isCapturing = YES;
        NSLog(@"[AudioPcmCapturer:%@] 开始音频采集", _recorderId);
        
    } @catch (NSException* exception) {
        NSLog(@"[AudioPcmCapturer:%@] 启动采集异常: %@", _recorderId, exception);
    }
}

- (void)stopCapturing {
    if (!_isCapturing) {
        return;
    }
    
    @try {
        [_inputNode removeTapOnBus:0];
        [_audioEngine stop];
        AVAudioSession* session = [AVAudioSession sharedInstance];
        [session setActive:NO error:nil];
        _isCapturing = NO;
        NSLog(@"[AudioPcmCapturer:%@] 停止音频采集", _recorderId);
    } @catch (NSException* exception) {
        NSLog(@"[AudioPcmCapturer:%@] 停止采集异常: %@", _recorderId, exception);
    }
}

- (void)attachAudioTrack:(RTCAudioTrack*)audioTrack {
    _audioTrack = audioTrack;
    NSLog(@"[AudioPcmCapturer:%@] 附加音频轨: %@", _recorderId, audioTrack.trackId);
}

- (void)processAudioBuffer:(AVAudioPCMBuffer*)buffer {
    if (!_isCapturing || !buffer) {
        return;
    }
    
    AVAudioFrameCount frames = buffer.frameLength;
    AVAudioChannelCount channels = buffer.format.channelCount;
    int sampleRate = (int)buffer.format.sampleRate;
    AVAudioCommonFormat format = buffer.format.commonFormat;
    
    NSMutableData* pcmData = [NSMutableData dataWithLength:frames * channels * 2];
    int16_t* dst = (int16_t*)pcmData.mutableBytes;
    
    if (format == AVAudioPCMFormatInt16 && buffer.int16ChannelData != NULL) {
        for (int ch = 0; ch < channels; ch++) {
            int16_t* src = buffer.int16ChannelData[ch];
            for (int i = 0; i < frames; i++) {
                dst[i * channels + ch] = src[i];
            }
        }
    } else if (format == AVAudioPCMFormatFloat32 && buffer.floatChannelData != NULL) {
        for (int ch = 0; ch < channels; ch++) {
            float* src = buffer.floatChannelData[ch];
            for (int i = 0; i < frames; i++) {
                float sample = src[i];
                if (sample > 1.0f) sample = 1.0f;
                if (sample < -1.0f) sample = -1.0f;
                int16_t s = (int16_t)lrintf(sample * 32767.0f);
                dst[i * channels + ch] = s;
            }
        }
    } else if (format == AVAudioPCMFormatInt32 && buffer.int32ChannelData != NULL) {
        for (int ch = 0; ch < channels; ch++) {
            int32_t* src = buffer.int32ChannelData[ch];
            for (int i = 0; i < frames; i++) {
                int32_t v = src[i] >> 16;
                if (v > INT16_MAX) v = INT16_MAX;
                if (v < INT16_MIN) v = INT16_MIN;
                dst[i * channels + ch] = (int16_t)v;
            }
        }
    }
    
    if ([FlutterWebRTCPlugin sharedSingleton].eventSink != nil) {
        NSDictionary* event = @{
            @"event": @"onAudioPcmData",
            @"recorderId": _recorderId ?: @(-1),
            @"sampleRate": @(sampleRate),
            @"numOfChannels": @(channels),
            @"bitsPerSample": @16,
            @"data": [FlutterStandardTypedData typedDataWithBytes:pcmData]
        };
        postEvent([FlutterWebRTCPlugin sharedSingleton].eventSink, event);
    }
}

- (NSString*)stringForAudioFormat:(AVAudioCommonFormat)format {
    switch (format) {
        case AVAudioPCMFormatInt16:
            return @"Int16";
        case AVAudioPCMFormatInt32:
            return @"Int32";
        case AVAudioPCMFormatFloat32:
            return @"Float32";
        case AVAudioPCMFormatFloat64:
            return @"Float64";
        default:
            return @"Unknown";
    }
}

- (void)dealloc {
    [self stopCapturing];
}

@end

#endif
