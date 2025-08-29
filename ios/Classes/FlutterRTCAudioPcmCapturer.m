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
        
        // 初始化音频引擎
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
        // 设置音频会话
        AVAudioSession* session = [AVAudioSession sharedInstance];
        NSError* error = nil;
        
        // 设置为录音模式
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
        
        // 获取输入格式
        AVAudioFormat* inputFormat = [_inputNode outputFormatForBus:0];
        NSLog(@"[AudioPcmCapturer:%@] 输入格式: 采样率=%.0f, 声道数=%lu, 格式=%@", 
              _recorderId, inputFormat.sampleRate, (unsigned long)inputFormat.channelCount, 
              [self stringForAudioFormat:inputFormat.commonFormat]);
        
        // 安装音频采集回调
        __weak typeof(self) weakSelf = self;
        [_inputNode installTapOnBus:0 
                         bufferSize:1024 
                             format:inputFormat 
                              block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
            [weakSelf processAudioBuffer:buffer];
        }];
        
        // 准备并启动音频引擎
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
        // 移除音频采集回调
        [_inputNode removeTapOnBus:0];
        
        // 停止音频引擎
        [_audioEngine stop];
        
        // 停用音频会话
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
    
    // 获取音频参数
    AVAudioFrameCount frames = buffer.frameLength;
    AVAudioChannelCount channels = buffer.format.channelCount;
    int sampleRate = (int)buffer.format.sampleRate;
    AVAudioCommonFormat format = buffer.format.commonFormat;
    
    // 计算数据长度
    size_t bytesPerSample = 0;
    switch (format) {
        case AVAudioPCMFormatInt16:
            bytesPerSample = 2;
            break;
        case AVAudioPCMFormatInt32:
            bytesPerSample = 4;
            break;
        case AVAudioPCMFormatFloat32:
            bytesPerSample = 4;
            break;
        default:
            NSLog(@"[AudioPcmCapturer:%@] 不支持的音频格式: %@", _recorderId, [self stringForAudioFormat:format]);
            return;
    }
    
    size_t totalLength = frames * channels * bytesPerSample;
    
    // 转换为 16-bit PCM 数据
    NSMutableData* pcmData = [NSMutableData dataWithLength:frames * channels * 2]; // 16-bit = 2 bytes
    int16_t* dst = (int16_t*)pcmData.mutableBytes;
    
    // 根据原始格式进行转换
    if (format == AVAudioPCMFormatInt16 && buffer.int16ChannelData != NULL) {
        // 已经是 16-bit，直接复制
        for (int ch = 0; ch < channels; ch++) {
            int16_t* src = buffer.int16ChannelData[ch];
            for (int i = 0; i < frames; i++) {
                dst[i * channels + ch] = src[i];
            }
        }
    } else if (format == AVAudioPCMFormatFloat32 && buffer.floatChannelData != NULL) {
        // 从 float32 转换为 16-bit
        for (int ch = 0; ch < channels; ch++) {
            float* src = buffer.floatChannelData[ch];
            for (int i = 0; i < frames; i++) {
                float sample = src[i];
                // 限制范围到 [-1.0, 1.0]
                if (sample > 1.0f) sample = 1.0f;
                if (sample < -1.0f) sample = -1.0f;
                // 转换为 16-bit
                int16_t s = (int16_t)lrintf(sample * 32767.0f);
                dst[i * channels + ch] = s;
            }
        }
    } else if (format == AVAudioPCMFormatInt32 && buffer.int32ChannelData != NULL) {
        // 从 32-bit 转换为 16-bit
        for (int ch = 0; ch < channels; ch++) {
            int32_t* src = buffer.int32ChannelData[ch];
            for (int i = 0; i < frames; i++) {
                int32_t v = src[i] >> 16; // 右移 16 位，从 32-bit 转为 16-bit
                // 限制范围
                if (v > INT16_MAX) v = INT16_MAX;
                if (v < INT16_MIN) v = INT16_MIN;
                dst[i * channels + ch] = (int16_t)v;
            }
        }
    }
    
    // 发送 PCM 数据到 Flutter
    if ([FlutterWebRTCPlugin sharedSingleton].eventSink != nil) {
        NSDictionary* event = @{
            @"event": @"onAudioPcmData",
            @"recorderId": _recorderId ?: @(-1),
            @"sampleRate": @(sampleRate),
            @"numOfChannels": @(channels),
            @"bitsPerSample": @16,
            @"data": [FlutterStandardTypedData typedDataWithBytes:pcmData]
        };
        
        // 使用 postEvent 发送数据
        postEvent([FlutterWebRTCPlugin sharedSingleton].eventSink, event);
        
        NSLog(@"[AudioPcmCapturer:%@] 发送PCM数据: 长度=%zu, 采样率=%d, 声道数=%lu", 
              _recorderId, pcmData.length, sampleRate, (unsigned long)channels);
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
    NSLog(@"[AudioPcmCapturer:%@] 释放", _recorderId);
}

@end

#endif
