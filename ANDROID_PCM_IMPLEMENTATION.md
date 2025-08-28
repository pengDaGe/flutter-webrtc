# Android端PCM实时回传功能实现

## 功能概述

本功能实现了Android端实时回传PCM音频数据到Flutter端，支持实时音频录制和PCM数据流处理。

## 架构设计

### 数据流
```
Android音频输入 → WebRTC音频处理 → AudioSamplesInterceptor → Flutter事件通道 → Flutter端PCM回调
```

### 核心组件

1. **AudioSamplesInterceptor**: 音频样本拦截器，负责捕获WebRTC音频数据
2. **FlutterWebRTCPlugin**: Flutter插件主类，负责事件通道管理
3. **MediaRecorder**: Flutter端媒体录制器，接收PCM数据
4. **EventChannel**: Flutter事件通道，传输PCM数据

## 实现细节

### 1. Android端修改

#### AudioSamplesInterceptor.java
- 添加PCM数据回传功能
- 支持多个recorder的PCM数据管理
- 通过FlutterWebRTCPlugin发送事件

```java
public class AudioSamplesInterceptor implements SamplesReadyCallback {
    private final HashMap<Integer, Boolean> pcmEnabledRecorders = new HashMap<>();
    
    public void enablePcmData(Integer recorderId) {
        pcmEnabledRecorders.put(recorderId, true);
    }
    
    public void disablePcmData(Integer recorderId) {
        pcmEnabledRecorders.remove(recorderId);
    }
    
    private void sendPcmDataToFlutter(AudioSamples audioSamples) {
        // 发送PCM数据到Flutter端
    }
}
```

#### FlutterWebRTCPlugin.java
- 添加静态实例访问方法
- 支持AudioSamplesInterceptor的事件发送

#### GetUserMediaImpl.java
- 在开始录制时启用PCM数据回传
- 在停止录制时禁用PCM数据回传

### 2. Flutter端修改

#### MediaRecorderNative
- 监听`onAudioPcmData`事件
- 通过`onPcm`回调传递PCM数据

#### MediaRecorder
- 提供`setOnPcm`方法设置PCM回调

## 使用方法

### 1. 基本使用

```dart
// 创建媒体录制器
final recorder = MediaRecorder(albumName: 'FlutterWebRTC');

// 设置PCM回调
recorder.setOnPcm((Uint8List data, int sampleRate, int channels, int bitsPerSample) {
  print('收到PCM数据: ${data.length} 字节');
  print('采样率: $sampleRate Hz');
  print('声道数: $channels');
  print('位深度: $bitsPerSample bit');
  
  // 处理PCM数据
  // 例如：写入文件、实时播放、音频分析等
});

// 开始录制
await recorder.start(
  'output.pcm',
  audioChannel: RecorderAudioChannel.INPUT,
);

// 停止录制
await recorder.stop();
```

### 2. 实时PCM文件写入

```dart
File? pcmFile;
String? pcmFilePath;

// 设置PCM回调
recorder.setOnPcm((Uint8List data, int sampleRate, int channels, int bitsPerSample) async {
  if (pcmFile != null) {
    // 实时写入PCM文件
    await pcmFile!.writeAsBytes(data, mode: FileMode.append, flush: false);
  }
});
```

### 3. 音频数据分析

```dart
int totalBytes = 0;
int dataCount = 0;

recorder.setOnPcm((Uint8List data, int sampleRate, int channels, int bitsPerSample) {
  totalBytes += data.length;
  dataCount++;
  
  // 计算音频时长
  final duration = Duration(
    microseconds: (totalBytes * 1000000) ~/ (sampleRate * channels * (bitsPerSample / 8))
  );
  
  print('累计数据: ${totalBytes} 字节, 时长: ${duration.inSeconds} 秒');
});
```

## 测试页面

### AndroidPcmTestPage
专门用于测试Android端PCM实时回传功能的测试页面，包含：

- 音频流状态显示
- 录制状态控制
- PCM数据实时统计
- 文件路径显示
- 详细的测试说明

### 使用方法
1. 在GetUserMedia示例页面点击"开始Android PCM测试"按钮
2. 进入专门的测试页面
3. 点击"开始录制"开始测试
4. 观察PCM数据的实时回传
5. 点击"停止录制"结束测试

## 技术特点

### 1. 实时性
- PCM数据从Android端到Flutter端的延迟极低
- 支持连续音频流处理

### 2. 高效性
- 使用二进制数据传输，减少序列化开销
- 支持多个recorder同时工作

### 3. 灵活性
- 支持不同的音频参数（采样率、声道数、位深度）
- 可自定义PCM数据处理逻辑

### 4. 稳定性
- 完善的错误处理机制
- 资源自动清理

## 注意事项

### 1. 平台限制
- 此功能仅在Android平台有效
- iOS和Web平台会忽略PCM回调

### 2. 性能考虑
- PCM数据量较大，注意内存使用
- 建议在后台线程处理PCM数据

### 3. 权限要求
- 需要录音权限
- Android 6.0+需要动态权限申请

### 4. 文件管理
- PCM文件为原始音频数据，无压缩
- 文件大小与录制时长成正比
- 建议定期清理临时文件

## 故障排除

### 1. 常见问题

**Q: 没有收到PCM数据**
A: 检查是否设置了`setOnPcm`回调，确保音频权限已获取

**Q: PCM数据不连续**
A: 检查音频流是否稳定，确保没有音频处理中断

**Q: 文件写入失败**
A: 检查文件路径权限，确保有写入权限

### 2. 调试信息

启用详细日志：
```dart
// 在PCM回调中添加详细日志
recorder.setOnPcm((data, sampleRate, channels, bitsPerSample) {
  print('PCM数据: ${data.length} 字节, 采样率: $sampleRate Hz');
});
```

### 3. 性能监控

监控PCM数据处理性能：
```dart
final stopwatch = Stopwatch()..start();
// 处理PCM数据
stopwatch.stop();
print('PCM处理耗时: ${stopwatch.elapsedMicroseconds} 微秒');
```

## 扩展功能

### 1. 音频格式转换
可以将PCM数据转换为其他音频格式：
- WAV
- MP3
- AAC
- OGG

### 2. 实时音频处理
- 音量分析
- 频谱分析
- 音频滤波
- 降噪处理

### 3. 网络传输
- 实时音频流传输
- WebRTC音频流
- 音频会议功能

## 总结

Android端PCM实时回传功能为Flutter应用提供了强大的实时音频处理能力，适用于：

- 音频录制应用
- 实时语音分析
- 音频流处理
- 语音识别
- 音频质量检测

通过合理使用此功能，可以构建功能丰富的音频处理应用。
