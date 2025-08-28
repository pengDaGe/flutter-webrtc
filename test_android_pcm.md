# Android端PCM实时回传功能测试指南

## 测试环境要求

- Android设备或模拟器（API 21+）
- Flutter开发环境
- 音频权限已获取

## 测试步骤

### 1. 编译和运行

```bash
# 进入example目录
cd example

# 获取依赖
flutter pub get

# 运行应用
flutter run
```

### 2. 功能测试

#### 2.1 基本音频录制测试
1. 在GetUserMedia示例页面获取音频流
2. 点击"开始音频录制"按钮
3. 观察PCM回调是否被触发
4. 检查PCM文件是否正确生成

#### 2.2 Android PCM实时回传测试
1. 在GetUserMedia示例页面点击"开始Android PCM测试"按钮
2. 进入专门的测试页面
3. 点击"开始录制"开始测试
4. 观察PCM数据的实时回传
5. 检查统计信息是否正确更新
6. 点击"停止录制"结束测试

### 3. 验证要点

#### 3.1 PCM数据流
- [ ] PCM数据包数量正确递增
- [ ] 总字节数正确累加
- [ ] 音频参数（采样率、声道数、位深度）正确

#### 3.2 实时性
- [ ] PCM数据实时到达Flutter端
- [ ] 没有明显的数据延迟
- [ ] 数据流连续不间断

#### 3.3 文件写入
- [ ] PCM文件正确创建
- [ ] 文件大小与录制时长匹配
- [ ] 文件内容为有效的PCM数据

#### 3.4 错误处理
- [ ] 权限不足时正确提示
- [ ] 音频流中断时正确处理
- [ ] 资源释放正确

### 4. 日志检查

#### 4.1 Android端日志
```bash
adb logcat | grep -E "(AudioSamplesInterceptor|FlutterWebRTCPlugin)"
```

关键日志：
- "启用PCM数据回传，recorderId: X"
- "发送PCM数据到Flutter，recorderId: X, 数据长度: Y"
- "禁用PCM数据回传，recorderId: X"

#### 4.2 Flutter端日志
```bash
flutter logs
```

关键日志：
- "=== Android端实时PCM数据 ==="
- "PCM数据长度: X 字节"
- "采样率: X Hz"
- "PCM数据已实时写入文件"

### 5. 性能测试

#### 5.1 数据量测试
- 录制1分钟音频
- 检查PCM文件大小
- 验证数据完整性

#### 5.2 延迟测试
- 使用音频分析工具
- 测量从音频输入到PCM回调的延迟
- 目标延迟 < 100ms

#### 5.3 内存测试
- 长时间录制（10分钟+）
- 监控内存使用情况
- 确保没有内存泄漏

### 6. 边界情况测试

#### 6.1 权限测试
- 拒绝录音权限
- 运行时权限撤销
- 权限重新授权

#### 6.2 音频中断测试
- 来电中断
- 其他应用占用音频
- 音频设备切换

#### 6.3 应用生命周期测试
- 应用进入后台
- 应用被系统杀死
- 应用重新启动

### 7. 兼容性测试

#### 7.1 Android版本兼容性
- Android 5.0 (API 21)
- Android 6.0 (API 23)
- Android 7.0 (API 24)
- Android 8.0 (API 26)
- Android 9.0 (API 28)
- Android 10.0 (API 29)
- Android 11.0 (API 30)
- Android 12.0 (API 31)
- Android 13.0 (API 33)

#### 7.2 设备兼容性
- 不同品牌设备
- 不同屏幕尺寸
- 不同音频硬件

### 8. 问题排查

#### 8.1 常见问题

**问题：没有收到PCM数据**
排查步骤：
1. 检查音频权限
2. 确认音频流已获取
3. 检查PCM回调是否设置
4. 查看Android端日志

**问题：PCM数据不连续**
排查步骤：
1. 检查音频流稳定性
2. 确认没有音频处理中断
3. 检查recorderId匹配
4. 验证事件通道状态

**问题：文件写入失败**
排查步骤：
1. 检查文件路径权限
2. 确认存储空间充足
3. 检查文件操作异常
4. 验证文件句柄状态

#### 8.2 调试技巧

1. **启用详细日志**
```dart
// 在PCM回调中添加详细日志
recorder.setOnPcm((data, sampleRate, channels, bitsPerSample) {
  print('=== PCM数据详情 ===');
  print('时间戳: ${DateTime.now()}');
  print('数据长度: ${data.length}');
  print('数据前10字节: ${data.take(10).toList()}');
});
```

2. **性能监控**
```dart
final stopwatch = Stopwatch()..start();
// 处理PCM数据
stopwatch.stop();
print('PCM处理耗时: ${stopwatch.elapsedMicroseconds} 微秒');
```

3. **数据验证**
```dart
// 验证PCM数据有效性
bool isValidPcmData(Uint8List data, int sampleRate, int channels, int bitsPerSample) {
  // 检查数据长度是否为偶数（16位PCM）
  if (data.length % 2 != 0) return false;
  
  // 检查采样率范围
  if (sampleRate < 8000 || sampleRate > 48000) return false;
  
  // 检查声道数
  if (channels < 1 || channels > 2) return false;
  
  // 检查位深度
  if (bitsPerSample != 16) return false;
  
  return true;
}
```

### 9. 测试报告模板

#### 9.1 基本信息
- 测试设备：XXX
- Android版本：XXX
- Flutter版本：XXX
- 测试时间：XXX

#### 9.2 功能测试结果
- [ ] 基本音频录制：通过/失败
- [ ] PCM实时回传：通过/失败
- [ ] 文件写入：通过/失败
- [ ] 错误处理：通过/失败

#### 9.3 性能测试结果
- 平均延迟：XXX ms
- 内存使用：XXX MB
- 数据完整性：XXX%

#### 9.4 兼容性测试结果
- Android版本兼容性：XXX
- 设备兼容性：XXX

#### 9.5 问题记录
- 问题描述：XXX
- 复现步骤：XXX
- 解决方案：XXX

#### 9.6 建议改进
- 功能改进：XXX
- 性能优化：XXX
- 用户体验：XXX

## 总结

通过以上测试步骤，可以全面验证Android端PCM实时回传功能的正确性、稳定性和性能。建议在多个设备和Android版本上进行测试，确保功能的广泛兼容性。
