import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// PCM 回调类型
typedef PCMCallback = void Function(
    Uint8List data,
    int sampleRate,
    int channels,
    int bitsPerSample,
    );

class WebrtcAudioRecorder {
  MediaRecorder? _mediaRecorder;
  MediaStream? _localStream;

  // 文件写入
  IOSink? _pcmFile;
  String? _pcmFilePath;

  bool _isRecording = false;

  final PCMCallback onPCM;

  WebrtcAudioRecorder({required this.onPCM});

  /// 初始化音频流
  Future<void> _initStream() async {
    if (_localStream != null) return;
    final constraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'sampleRate': 24000, // 设置采样率
        'channelCount': 1,   // 单声道
      },
      'video': false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
  }

  /// 开始录制
  Future<void> startRecording() async {
    if (_isRecording) return;

    await _initStream();

    _mediaRecorder = MediaRecorder();

    // 设置PCM回调
    _mediaRecorder!.setOnPcm(
          (Uint8List data, int sampleRate, int channels, int bitsPerSample) {
        onPCM(data, sampleRate, channels, bitsPerSample);

        // 写入文件
        if (_pcmFile != null) {
          _pcmFile!.add(data);
        }
      },
    );

    // 文件路径
    final directory = Directory.systemTemp;
    _pcmFilePath =
    '${directory.path}/ios_audio_${DateTime.now().millisecondsSinceEpoch}.pcm';
    _pcmFile = File(_pcmFilePath!).openWrite();

    // 开始录制
    await _mediaRecorder!.start(
      _pcmFilePath!,
      audioChannel: RecorderAudioChannel.INPUT,
    );

    _isRecording = true;
  }

  /// 停止录制
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    await _mediaRecorder?.stop();

    // 关闭文件
    await _pcmFile?.close();
    _pcmFile = null;

    _isRecording = false;
  }

  /// 获取当前录制的PCM文件路径
  String? get pcmFilePath => _pcmFilePath;

  /// 释放资源
  Future<void> dispose() async {
    await stopRecording();
    await _localStream?.dispose();
    _localStream = null;
  }
}