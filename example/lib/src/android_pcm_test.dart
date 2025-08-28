import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';

class AndroidPcmTestPage extends StatefulWidget {
  const AndroidPcmTestPage({Key? key}) : super(key: key);

  @override
  State<AndroidPcmTestPage> createState() => _AndroidPcmTestPageState();
}

class _AndroidPcmTestPageState extends State<AndroidPcmTestPage> {
  MediaRecorder? _mediaRecorder;
  MediaStream? _localStream;
  bool _isRecording = false;
  bool _isStreamActive = false;
  
  // PCM相关变量
  File? _pcmFile;
  String? _pcmFilePath;
  int _pcmDataCount = 0;
  int _totalPcmBytes = 0;
  int _sampleRate = 0;
  int _channels = 0;
  int _bitsPerSample = 0;
  
  // 音频参数
  int _currentSampleRate = 0;
  int _currentChannels = 0;
  int _currentBitsPerSample = 0;

  @override
  void initState() {
    super.initState();
    _initMediaStream();
  }

  @override
  void dispose() {
    _stopRecording();
    _disposeMediaStream();
    super.dispose();
  }

  Future<void> _initMediaStream() async {
    try {
      // 获取音频权限
      final constraints = <String, dynamic>{
        'audio': true,
        'video': false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      
      setState(() {
        _isStreamActive = true;
      });
      
      print('音频流已初始化');
    } catch (e) {
      print('初始化音频流失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('初始化音频流失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _disposeMediaStream() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream = null;
    setState(() {
      _isStreamActive = false;
    });
  }

  Future<void> _startRecording() async {
    if (_localStream == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先初始化音频流')),
      );
      return;
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempDir = await getTemporaryDirectory();

      _pcmFilePath = '${tempDir.path}/android_pcm_test_$timestamp.pcm';
      _pcmFile = File(_pcmFilePath!);

      // 删除已存在的文件
      if (await _pcmFile!.exists()) {
        await _pcmFile!.delete();
      }

      // 重置计数器
      _pcmDataCount = 0;
      _totalPcmBytes = 0;

      // 创建媒体录制器
      _mediaRecorder = MediaRecorder(albumName: 'FlutterWebRTC');

      // 设置PCM回调 - 接收Android端实时回传的PCM数据
      _mediaRecorder!.setOnPcm((Uint8List data, int sampleRate, int channels, int bitsPerSample) async {
        _pcmDataCount++;
        _totalPcmBytes += data.length;

        // 保存音频参数
        _sampleRate = sampleRate;
        _channels = channels;
        _bitsPerSample = bitsPerSample;

        // 更新UI（在主线程中）
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _currentSampleRate = sampleRate;
            _currentChannels = channels;
            _currentBitsPerSample = bitsPerSample;
          });
        });

        print('=== Android端实时PCM数据 ===');
        print('数据包 #$_pcmDataCount');
        print('数据长度: ${data.length} 字节');
        print('采样率: $sampleRate Hz');
        print('声道数: $channels');
        print('位深度: $bitsPerSample bit');
        print('累计字节数: ${_formatBytes(_totalPcmBytes)}');
        print('PCM数据前10字节: ${data.take(10).toList()}');

        // 实时写入PCM文件
        if (_pcmFile != null) {
          try {
            await _pcmFile!.writeAsBytes(data, mode: FileMode.append, flush: false);
            print('PCM数据已实时写入文件');
          } catch (e) {
            print('PCM写入错误: $e');
          }
        }
      });

      // 获取音频轨道
      final audioTrack = _localStream!.getAudioTracks().firstWhere(
        (track) => track.kind == 'audio',
        orElse: () => throw Exception('未找到音频轨道'),
      );

      print('开始Android PCM测试录制');
      print('音频轨道ID: ${audioTrack.id}');
      print('PCM文件路径: $_pcmFilePath');

      // 开始录制 - 只录制音频
      await _mediaRecorder!.start(
        _pcmFilePath!,
        audioChannel: RecorderAudioChannel.INPUT,
      );

      setState(() {
        _isRecording = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Android PCM测试录制已开始'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

    } catch (e) {
      print('开始录制失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('开始录制失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || _mediaRecorder == null) {
      return;
    }

    try {
      await _mediaRecorder!.stop();
      
      setState(() {
        _isRecording = false;
      });

      // 显示录制结果
      final savedPcm = _pcmFilePath;
      _pcmFile = null;
      _pcmFilePath = null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('录制已停止，PCM文件: $savedPcm'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 3),
        ),
      );

      print('Android PCM测试录制已停止');
      print('最终统计:');
      print('- 总数据包数: $_pcmDataCount');
      print('- 总字节数: ${_formatBytes(_totalPcmBytes)}');
      print('- 采样率: $_sampleRate Hz');
      print('- 声道数: $_channels');
      print('- 位深度: $_bitsPerSample bit');

    } catch (e) {
      print('停止录制失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('停止录制失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Android PCM实时回传测试'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 状态信息卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '音频流状态',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _isStreamActive ? Icons.check_circle : Icons.error,
                          color: _isStreamActive ? Colors.green : Colors.red,
                        ),
                        SizedBox(width: 8),
                        Text(_isStreamActive ? '音频流已激活' : '音频流未激活'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // 录制状态卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '录制状态',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _isRecording ? Icons.fiber_manual_record : Icons.stop_circle,
                          color: _isRecording ? Colors.red : Colors.grey,
                        ),
                        SizedBox(width: 8),
                        Text(_isRecording ? '正在录制' : '未录制'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // PCM数据统计卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PCM数据统计',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),
                    _buildStatRow('数据包数', '$_pcmDataCount'),
                    _buildStatRow('总字节数', _formatBytes(_totalPcmBytes)),
                    _buildStatRow('当前采样率', '$_currentSampleRate Hz'),
                    _buildStatRow('当前声道数', '$_currentChannels'),
                    _buildStatRow('当前位深度', '$_currentBitsPerSample bit'),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // 控制按钮
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isStreamActive && !_isRecording ? _startRecording : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text('开始录制'),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isRecording ? _stopRecording : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text('停止录制'),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 16),
            
            // 说明文字
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '测试说明',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '此页面专门用于测试Android端的PCM数据实时回传功能。\n'
                      '1. 点击"开始录制"开始音频录制\n'
                      '2. Android端会实时回传PCM数据到Flutter端\n'
                      '3. PCM数据会实时写入文件并显示统计信息\n'
                      '4. 点击"停止录制"结束录制并查看最终统计',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
