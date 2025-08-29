# iOS 端音频 PCM 实时回调功能实现

## 功能概述

本功能为 iOS 端实现了实时音频 PCM 数据回调，允许 Flutter 应用实时接收来自设备麦克风的原始音频数据。与 Android 端类似，iOS 端也支持通过 `MediaRecorder` 的 `setOnPcm` 回调接收实时 PCM 数据。

## 架构设计

### 核心组件

1. **FlutterRTCAudioPcmCapturer**: iOS 端音频 PCM 采集器
2. **FlutterRTCMediaRecorder**: 修改后的媒体录制器，支持纯音频录制
3. **FlutterWebRTCPlugin**: 主插件类，管理音频 PCM 采集器生命周期

### 数据流

```
麦克风 → AVAudioEngine → FlutterRTCAudioPcmCapturer → postEvent → Flutter EventChannel → Flutter onPcm 回调
```

## 实现细节

### 1. FlutterRTCAudioPcmCapturer

**功能**: 使用 `AVAudioEngine` 直接采集麦克风音频，转换为 16-bit PCM 格式

**关键特性**:
- 支持多种音频格式转换 (Int16, Int32, Float32 → Int16)
- 自动音频会话管理
- 实时 PCM 数据回传
- 错误处理和异常捕获

**核心方法**:
```objc
- (void)startCapturing;           // 开始采集
- (void)stopCapturing;            // 停止采集
- (void)processAudioBuffer:(AVAudioPCMBuffer*)buffer;  // 处理音频数据
```

### 2. 修改后的 FlutterRTCMediaRecorder

**支持纯音频录制**:
- 检测 `videoTrack` 是否为 `nil`
- 纯音频录制时跳过视频写入器初始化
- 使用 `AVFileTypeM4A` 作为纯音频文件格式
- 兼容现有的视频录制功能

**关键修改**:
```objc
// 条件初始化视频写入器
if (self.videoTrack != nil) {
    // 视频录制逻辑
} else {
    // 纯音频录制逻辑
}

// 根据内容选择文件类型
NSString* fileType = (self.videoTrack != nil) ? AVFileTypeMPEG4 : AVFileTypeM4A;
```

### 3. FlutterWebRTCPlugin 集成

**音频 PCM 采集器管理**:
- 在 `startRecordToFile` 中检测录制类型
- 纯音频录制时创建 `FlutterRTCAudioPcmCapturer`
- 管理采集器生命周期（启动/停止/清理）

**关键代码**:
```objc
} else if (audioTrack != nil && [audioTrack isKindOfClass:[RTCAudioTrack class]]) {
    // 纯音频录制 - 使用音频 PCM 采集器
    FlutterRTCAudioPcmCapturer* audioCapturer = [[FlutterRTCAudioPcmCapturer alloc] 
        initWithRecorderId:recorderId 
                audioTrack:(RTCAudioTrack*)audioTrack];
    
    _audioPcmCapturers[recorderId] = audioCapturer;
    [audioCapturer startCapturing];
}
```

## 使用方法

### Flutter 端

```dart
// 创建 MediaRecorder
final mediaRecorder = MediaRecorder();

// 设置 PCM 回调
mediaRecorder.setOnPcm((Uint8List data, int sampleRate, int channels, int bitsPerSample) {
  print('收到PCM数据: 长度=${data.length}, 采样率=$sampleRate, 声道数=$channels, 位深=$bitsPerSample');
  // 处理 PCM 数据
});

// 开始录制（纯音频）
await mediaRecorder.startRecording(
  path: '/path/to/audio.m4a',
  audioChannel: RecorderAudioChannel.INPUT,
);
```

### iOS 端

**自动检测录制类型**:
- 如果提供 `videoTrack`，使用现有的视频录制逻辑
- 如果只提供 `audioTrack`，自动启用音频 PCM 采集器
- 无需额外配置，插件自动选择最佳录制方式

## 技术特点

### 1. 音频格式支持

- **输入格式**: 支持 Int16、Int32、Float32 等常见格式
- **输出格式**: 统一转换为 16-bit PCM
- **采样率**: 自动检测设备支持的采样率
- **声道数**: 支持单声道和多声道

### 2. 性能优化

- **缓冲区大小**: 使用 1024 样本的缓冲区，平衡延迟和性能
- **内存管理**: 避免不必要的内存分配和复制
- **异常处理**: 完善的错误处理和资源清理

### 3. 兼容性

- **iOS 版本**: 支持 iOS 9.0 及以上版本
- **设备兼容**: 支持所有支持 WebRTC 的 iOS 设备
- **音频设备**: 支持内置麦克风、外接麦克风、蓝牙耳机等

## 与 Android 端的差异

| 特性 | iOS 端 | Android 端 |
|------|--------|------------|
| 音频采集方式 | AVAudioEngine | AudioRecord |
| 音频会话管理 | 自动管理 | 手动管理 |
| 格式转换 | 内置支持 | 需要额外处理 |
| 错误处理 | 异常捕获 | 错误码返回 |
| 性能特点 | 低延迟，高质量 | 稳定，兼容性好 |

## 测试验证

### 测试页面

创建了专门的 `IOSPcmTestPage` 用于测试 iOS 端功能：

- 实时 PCM 数据统计
- 音频流状态监控
- 文件保存验证
- 性能指标显示

### 验证要点

1. **PCM 数据接收**: 确认 `onPcm` 回调被正确调用
2. **数据完整性**: 验证 PCM 数据的采样率、声道数、位深
3. **实时性**: 检查数据延迟和丢包情况
4. **文件保存**: 确认音频文件正确保存
5. **资源管理**: 验证录制停止后资源正确释放

## 故障排除

### 常见问题

1. **权限问题**: 确保麦克风权限已授予
2. **音频会话冲突**: 检查是否有其他应用占用音频会话
3. **设备兼容性**: 确认设备支持所需的音频格式
4. **内存不足**: 检查设备可用内存

### 调试方法

1. **查看控制台日志**: 所有关键操作都有详细日志
2. **检查音频会话状态**: 使用 `AVAudioSession` 调试信息
3. **验证 PCM 数据**: 检查数据长度和格式是否正确
4. **性能监控**: 观察 CPU 使用率和内存占用

## 总结

iOS 端音频 PCM 实时回调功能通过以下方式实现：

1. **FlutterRTCAudioPcmCapturer**: 专门负责音频采集和 PCM 转换
2. **修改后的 MediaRecorder**: 支持纯音频录制模式
3. **插件集成**: 自动检测录制类型并选择最佳实现

该实现提供了与 Android 端一致的用户体验，同时充分利用了 iOS 平台的音频处理优势，确保了高质量、低延迟的音频数据采集。
