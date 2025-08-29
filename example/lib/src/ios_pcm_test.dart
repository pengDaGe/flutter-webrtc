import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class IOSPcmTestPage extends StatefulWidget {
  const IOSPcmTestPage({Key? key}) : super(key: key);

  @override
  State<IOSPcmTestPage> createState() => _IOSPcmTestPageState();
}

class _IOSPcmTestPageState extends State<IOSPcmTestPage> {
  MediaRecorder? _mediaRecorder;
  MediaStream? _localStream;
  bool _isRecording = false;
  
  // PCM 统计信息
  int _totalBytes = 0;
  int _dataCount = 0;
  int _lastSampleRate = 0;
  int _lastChannels = 0;
  int _lastBitsPerSample = 0;
  DateTime? _startTime;
  
  // 文件写入
  IOSink? _pcmFile;
  String? _pcmFilePath;

  @override
  void initState() {
    super.initState();
    _initMediaStream();
  }

  @override
  void dispose() {
    _stopRecording();
    _localStream?.dispose();
    super.dispose();
  }

  Future<void> _initMediaStream() async {
    try {
      // 获取音频流
      final Map<String, dynamic> mediaConstraints = {
        'audio': true,
        'video': false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      //开始录制
      await _startRecording();
      setState(() {});
      
      print('[iOS PCM测试] 音频流初始化成功');
    } catch (e) {
      print('[iOS PCM测试] 音频流初始化失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('音频流初始化失败: $e')),
      );
    }
  }

  Future<void> _startRecording() async {
    if (_localStream == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先初始化音频流')),
      );
      return;
    }

    try {
      // 创建 MediaRecorder
      _mediaRecorder = MediaRecorder();
      
      // 设置 PCM 回调
      _mediaRecorder!.setOnPcm((Uint8List data, int sampleRate, int channels, int bitsPerSample) async {
        setState(() {
          _totalBytes += data.length;
          _dataCount++;
          _lastSampleRate = sampleRate;
          _lastChannels = channels;
          _lastBitsPerSample = bitsPerSample;
        });
        
        print('[iOS PCM测试] 收到PCM数据: 长度=${data.length}, 采样率=$sampleRate, 声道数=$channels, 位深=$bitsPerSample, pcm数据=$data');
        
        // 写入文件
        if (_pcmFile != null) {
          _pcmFile!.add(data);
        }
      });

      // 生成文件路径
      final directory = Directory.systemTemp;
      _pcmFilePath = '${directory.path}/ios_audio_${DateTime.now().millisecondsSinceEpoch}.pcm';
      _pcmFile = File(_pcmFilePath!).openWrite();
      
      // 开始录制
      await _mediaRecorder!.start(
        _pcmFilePath!,
        audioChannel: RecorderAudioChannel.INPUT,
      );
      
      setState(() {
        _isRecording = true;
        _startTime = DateTime.now();
        _totalBytes = 0;
        _dataCount = 0;
      });
      
      print('[iOS PCM测试] 开始录制，文件路径: $_pcmFilePath');
      
    } catch (e) {
      print('[iOS PCM测试] 开始录制失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开始录制失败: $e')),
      );
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    
    try {
      await _mediaRecorder?.stop();
      
      // 关闭文件
      await _pcmFile?.close();
      _pcmFile = null;
      
      setState(() {
        _isRecording = false;
      });
      
      // 显示统计信息
      final duration = _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero;
      final durationSeconds = duration.inMilliseconds / 1000.0;
      final bytesPerSecond = durationSeconds > 0 ? _totalBytes / durationSeconds : 0;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('录制完成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('录制时长: ${durationSeconds.toStringAsFixed(2)}秒'),
              Text('PCM数据包数: $_dataCount'),
              Text('总字节数: $_totalBytes'),
              Text('平均比特率: ${(bytesPerSecond * 8 / 1024).toStringAsFixed(2)} kbps'),
              Text('文件路径: $_pcmFilePath'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      
      print('[iOS PCM测试] 录制停止，总字节数: $_totalBytes, 数据包数: $_dataCount');
      // await _localStream?.dispose();
      
    } catch (e) {
      print('[iOS PCM测试] 停止录制失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('停止录制失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('iOS 音频 PCM 测试'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 状态信息
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '录制状态: ${_isRecording ? "录制中" : "未录制"}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _isRecording ? Colors.green[700] : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('音频流状态: ${_localStream != null ? "已初始化" : "未初始化"}'),
                  if (_startTime != null)
                    Text('开始时间: ${_startTime!.toString().substring(11, 19)}'),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // PCM 统计信息
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PCM 数据统计',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('数据包数: $_dataCount'),
                  Text('总字节数: ${(_totalBytes / 1024).toStringAsFixed(2)} KB'),
                  Text('采样率: $_lastSampleRate Hz'),
                  Text('声道数: $_lastChannels'),
                  Text('位深: $_lastBitsPerSample bit'),
                  if (_startTime != null && _isRecording)
                    Text('实时比特率: ${(_totalBytes * 8 / 1024 / (DateTime.now().difference(_startTime!).inMilliseconds / 1000.0)).toStringAsFixed(2)} kbps'),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 控制按钮
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isRecording ? null : _startRecording,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始录制'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isRecording ? _stopRecording : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('停止录制'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // 说明信息
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '功能说明',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('• 此页面专门测试 iOS 端的实时音频 PCM 回调功能'),
                  const Text('• 使用 AVAudioEngine 直接采集麦克风音频'),
                  const Text('• 实时显示 PCM 数据统计信息'),
                  const Text('• 自动保存 PCM 数据到临时文件'),
                  const Text('• 支持实时比特率计算'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
