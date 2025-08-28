import 'dart:core';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'utils.dart';
import 'android_pcm_test.dart';

/*
 * getUserMedia sample
 */
class GetUserMediaSample extends StatefulWidget {
  static String tag = 'get_usermedia_sample';

  @override
  _GetUserMediaSampleState createState() => _GetUserMediaSampleState();
}

class _GetUserMediaSampleState extends State<GetUserMediaSample> {
  MediaStream? _localStream;
  final _localRenderer = RTCVideoRenderer();
  bool _inCalling = false;
  bool _isTorchOn = false;
  bool _isFrontCamera = true;
  MediaRecorder? _mediaRecorder;
  String? _mediaRecorderFilePath;
  File? _pcmFile;
  String? _pcmFilePath;

  // 新增变量用于音频录制
  bool _isAudioRecording = false;
  String? _audioPcmFilePath;
  File? _audioPcmFile;
  MediaRecorder? _audioRecorder;

  // PCM数据统计
  int _pcmDataCount = 0;
  int _totalPcmBytes = 0;
  DateTime? _recordingStartTime;

  // 音频信息
  int _sampleRate = 0;
  int _channels = 0;
  int _bitsPerSample = 0;

  bool get _isRec => _mediaRecorder != null;
  bool get _isAudioRec => _audioRecorder != null;

  List<MediaDeviceInfo>? _mediaDevicesList;

  @override
  void initState() {
    super.initState();
    initRenderers();
    navigator.mediaDevices.ondevicechange = (event) async {
      print('++++++ ondevicechange ++++++');
      _mediaDevicesList = await navigator.mediaDevices.enumerateDevices();
    };
  }

  @override
  void deactivate() {
    super.deactivate();
    if (_inCalling) {
      _hangUp();
    }
    _stopAudioRecording();
    _localRenderer.dispose();
    navigator.mediaDevices.ondevicechange = null;
  }

  void initRenderers() async {
    await _localRenderer.initialize();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  void _makeCall() async {
    // 先检查权限
    if (!await PermissionUtils.checkAndRequestAllPermissions(context)) {
      return;
    }

    final mediaConstraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'sampleRate': 48000, // 设置采样率
        'channelCount': 1,   // 单声道
      },
      'video': {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      }
    };

    try {
      var stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _mediaDevicesList = await navigator.mediaDevices.enumerateDevices();
      _localStream = stream;
      _localRenderer.srcObject = _localStream;


      print('获取到媒体流: ${stream.getTracks().length} 个轨道');
      stream.getTracks().forEach((track) {
        print('轨道类型: ${track.kind}, 启用状态: ${track.enabled}, ID: ${track.id},muted: ${track.muted}');
      });

    } catch (e) {
      print('获取媒体流失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('获取媒体流失败: $e')),
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _inCalling = true;
    });
  }

  void _hangUp() async {
    try {
      if (kIsWeb) {
        _localStream?.getTracks().forEach((track) => track.stop());
      }
      await _localStream?.dispose();
      _localRenderer.srcObject = null;
      setState(() {
        _inCalling = false;
      });
    } catch (e) {
      print(e.toString());
    }
  }

  // 开始音频录制（专门用于PCM数据）
  void _startAudioRecording() async {
    if (_localStream == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先获取媒体流')),
      );
      return;
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempDir = await getTemporaryDirectory();

      _audioPcmFilePath = '${tempDir.path}/audio_$timestamp.pcm';
      _audioPcmFile = File(_audioPcmFilePath!);

      // 删除已存在的文件
      if (await _audioPcmFile!.exists()) {
        await _audioPcmFile!.delete();
      }

      // 创建音频录制器
      _audioRecorder = MediaRecorder(albumName: 'FlutterWebRTC');

      // 设置PCM回调 - 这是Android端实时回传的PCM数据
      _audioRecorder!.setOnPcm((Uint8List data, int sampleRate, int channels, int bitsPerSample) async {
        _pcmDataCount++;
        _totalPcmBytes += data.length;

        // 保存音频参数
        _sampleRate = sampleRate;
        _channels = channels;
        _bitsPerSample = bitsPerSample;

        print('=== Android端实时PCM回调 ===');
        print('数据长度: ${data.length} 字节');
        print('采样率: ${AudioUtils.formatSampleRate(sampleRate)}');
        print('声道数: $channels');
        print('位深度: $bitsPerSample bit');
        print('累计数据包: $_pcmDataCount');
        print('累计字节数: ${AudioUtils.formatAudioDataSize(_totalPcmBytes)}');
        print('PCM数据前10字节: ${data.take(10).toList()}');

        // 实时写入PCM文件
        if (_audioPcmFile != null) {
          try {
            await _audioPcmFile!.writeAsBytes(data, mode: FileMode.append, flush: false);
            print('PCM数据已实时写入文件: ${_audioPcmFile!.path}');
          } catch (e) {
            debugPrint('PCM写入错误: $e');
          }
        } else {
          print('PCM文件为空，无法写入');
        }
      });

      // 获取音频轨道
      final audioTrack = _localStream!.getAudioTracks().firstWhere(
            (track) => track.kind == 'audio',
        orElse: () => throw Exception('未找到音频轨道'),
      );

      print('开始音频录制，音频轨道ID: ${audioTrack.id}');
      
      // 开始录制 - 只录制音频，不录制视频
      await _audioRecorder!.start(
        _audioPcmFilePath!,
        audioChannel: RecorderAudioChannel.INPUT,
      );

      navigator.mediaDevices.ondevicechange = (event) {
        print("[WebRTC] 设备状态变化: $event");
      };

      setState(() {
        _isAudioRecording = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('音频录制已开始，PCM文件: $_audioPcmFilePath'),
          duration: Duration(seconds: 2),
        ),
      );

      print('音频录制已开始，PCM文件路径: $_audioPcmFilePath');
    } catch (e) {
      print('开始音频录制失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('开始音频录制失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 停止音频录制
  void _stopAudioRecording() async {
    if (_audioRecorder == null) return;

    try {
      await _audioRecorder!.stop();

      final recordingDuration = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!)
          : Duration.zero;

      final calculatedDuration = AudioUtils.calculateAudioDuration(
          _totalPcmBytes, _sampleRate, _channels, _bitsPerSample
      );

      print('音频录制已停止');
      print('录制时长: ${recordingDuration.inSeconds} 秒');
      print('计算时长: ${calculatedDuration.inSeconds} 秒');
      print('总数据包数: $_pcmDataCount');
      print('总字节数: ${AudioUtils.formatAudioDataSize(_totalPcmBytes)}');
      print('PCM文件路径: $_audioPcmFilePath');
      print('音频参数: ${AudioUtils.formatSampleRate(_sampleRate)}, ${_channels}声道, ${_bitsPerSample}bit');

      // 保存PCM文件到相册（可选）
      if (_audioPcmFilePath != null) {
        try {
          // await GallerySaver.saveFile(_audioPcmFilePath!);
          print('PCM文件已保存到相册');
        } catch (e) {
          print('保存PCM文件到相册失败: $e');
        }
      }

      setState(() {
        _isAudioRecording = false;
        _audioRecorder = null;
        _audioPcmFile = null;
        _audioPcmFilePath = null;
        _pcmDataCount = 0;
        _totalPcmBytes = 0;
        _recordingStartTime = null;
        _sampleRate = 0;
        _channels = 0;
        _bitsPerSample = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('音频录制已停止，PCM文件已保存'),
          duration: Duration(seconds: 2),
        ),
      );

    } catch (e) {
      print('停止音频录制失败: $e');
    }
  }

  void _startRecording() async {
    if (_localStream == null) throw Exception('Stream is not initialized');

    // 检查权限
    if (!await PermissionUtils.checkAndRequestAllPermissions(context)) {
      return;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      throw 'Unsupported platform';
    }

    final tempDir = await getTemporaryDirectory();
    if (!(await tempDir.exists())) {
      await tempDir.create(recursive: true);
    }

    _mediaRecorderFilePath = '${tempDir.path}/$timestamp.mp4';
    _pcmFilePath = '${tempDir.path}/$timestamp.pcm';

    if (_mediaRecorderFilePath == null) {
      throw Exception('Can\'t find storagePath');
    }

    final file = File(_mediaRecorderFilePath!);
    if (await file.exists()) {
      await file.delete();
    }
    if (_pcmFilePath != null) {
      _pcmFile = File(_pcmFilePath!);
      if (await _pcmFile!.exists()) {
        await _pcmFile!.delete();
      }
    }

    _mediaRecorder = MediaRecorder(albumName: 'FlutterWebRTC');
    setState(() {});

    final videoTrack = _localStream!
        .getVideoTracks()
        .firstWhere((track) => track.kind == 'video');

    // 实时 PCM 回调：将 S16LE 原始 PCM 追加写入 .pcm 文件
    _mediaRecorder!.setOnPcm((Uint8List data, int sampleRate, int channels, int bitsPerSample) async {
      print("=== 视频录制PCM回调 ===");
      print("数据长度: ${data.length} 字节");
      print("采样率: ${AudioUtils.formatSampleRate(sampleRate)}");
      print("声道数: $channels");
      print("位深度: $bitsPerSample bit");
      print("pcm的数据为: $data");

      if (_pcmFile != null) {
        try {
          await _pcmFile!.writeAsBytes(data, mode: FileMode.append, flush: false);
          print("PCM数据已写入视频录制文件");
        } catch (e) {
          debugPrint('PCM write error: $e');
        }
      } else {
        print("PCM文件为空，无法写入");
      }
    });

    await _mediaRecorder!.start(
      _mediaRecorderFilePath!,
      videoTrack: videoTrack,
      audioChannel: RecorderAudioChannel.INPUT,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Recording started. MP4: $_mediaRecorderFilePath, PCM: $_pcmFilePath'),
      duration: Duration(seconds: 2),
    ));
  }

  void _stopRecording() async {
    if (_mediaRecorderFilePath == null) {
      return;
    }

    // album name works only for android, for ios use gallerySaver
    await _mediaRecorder?.stop();
    setState(() {
      _mediaRecorder = null;
    });

    // 完成 PCM 文件写入（raw PCM 无需封装，直接留在临时目录）
    final savedPcm = _pcmFilePath;
    _pcmFile = null;
    _pcmFilePath = null;

    // this is only for ios, android already saves to albumName
    await GallerySaver.saveVideo(
      _mediaRecorderFilePath!,
      albumName: 'FlutterWebRTC',
    );

    _mediaRecorderFilePath = null;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Recording stopped. Saved PCM: $savedPcm'),
      duration: Duration(seconds: 2),
    ));
  }

  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    final point = Point<double>(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    Helper.setFocusPoint(_localStream!.getVideoTracks().first, point);
    Helper.setExposurePoint(_localStream!.getVideoTracks().first, point);
  }

  void _toggleTorch() async {
    if (_localStream == null) throw Exception('Stream is not initialized');

    final videoTrack = _localStream!
        .getVideoTracks()
        .firstWhere((track) => track.kind == 'video');
    final has = await videoTrack.hasTorch();
    if (has) {
      print('[TORCH] Current camera supports torch mode');
      setState(() => _isTorchOn = !_isTorchOn);
      await videoTrack.setTorch(_isTorchOn);
      print('[TORCH] Torch state is now ${_isTorchOn ? 'on' : 'off'}');
    } else {
      print('[TORCH] Current camera does not support torch mode');
    }
  }

  void setZoom(double zoomLevel) async {
    if (_localStream == null) throw Exception('Stream is not initialized');
    // await videoTrack.setZoom(zoomLevel); //Use it after published webrtc_interface 1.1.1

    // before the release, use can just call native method directly.
    final videoTrack = _localStream!
        .getVideoTracks()
        .firstWhere((track) => track.kind == 'video');
    await Helper.setZoom(videoTrack, zoomLevel);
  }

  void _switchCamera() async {
    if (_localStream == null) throw Exception('Stream is not initialized');

    final videoTrack = _localStream!
        .getVideoTracks()
        .firstWhere((track) => track.kind == 'video');
    await Helper.switchCamera(videoTrack);
    setState(() {
      _isFrontCamera = _isFrontCamera;
    });
  }

  void _captureFrame() async {
    if (_localStream == null) throw Exception('Stream is not initialized');

    final videoTrack = _localStream!
        .getVideoTracks()
        .firstWhere((track) => track.kind == 'video');
    final frame = await videoTrack.captureFrame();
    await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          content:
          Image.memory(frame.asUint8List(), height: 720, width: 1280),
          actions: <Widget>[
            TextButton(
              onPressed: Navigator.of(context, rootNavigator: true).pop,
              child: Text('OK'),
            )
          ],
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('GetUserMedia API Test'),
        actions: _inCalling
            ? <Widget>[
          IconButton(
            icon: Icon(_isTorchOn ? Icons.flash_off : Icons.flash_on),
            onPressed: _toggleTorch,
          ),
          IconButton(
            icon: Icon(Icons.switch_video),
            onPressed: _switchCamera,
          ),
          IconButton(
            icon: Icon(Icons.camera),
            onPressed: _captureFrame,
          ),
          IconButton(
            icon: Icon(_isRec ? Icons.stop : Icons.fiber_manual_record),
            onPressed: _isRec ? _stopRecording : _startRecording,
          ),
          PopupMenuButton<String>(
            onSelected: _selectAudioOutput,
            itemBuilder: (BuildContext context) {
              if (_mediaDevicesList != null) {
                return _mediaDevicesList!
                    .where((device) => device.kind == 'audiooutput')
                    .map((device) {
                  return PopupMenuItem<String>(
                    value: device.deviceId,
                    child: Text(device.label),
                  );
                }).toList();
              }
              return [];
            },
          ),
        ]
            : null,
      ),
      body: Column(
        children: [
          // 音频录制控制区域
          if (_inCalling) Container(
            padding: EdgeInsets.all(16.0),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '音频PCM录制',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isAudioRec) Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fiber_manual_record, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text('录制中', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isAudioRec ? _stopAudioRecording : _startAudioRecording,
                        icon: Icon(_isAudioRec ? Icons.stop : Icons.mic),
                        label: Text(_isAudioRec ? '停止音频录制' : '开始音频录制'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isAudioRec ? Colors.red : Colors.blue,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),

                // 录制状态信息
                if (_isAudioRec) ...[
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info, color: Colors.green[700], size: 20),
                            SizedBox(width: 8),
                            Text(
                              '录制状态',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green[700]),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildInfoItem('数据包数', '$_pcmDataCount')),
                            Expanded(child: _buildInfoItem('总字节数', AudioUtils.formatAudioDataSize(_totalPcmBytes))),
                          ],
                        ),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(child: _buildInfoItem('采样率', AudioUtils.formatSampleRate(_sampleRate))),
                            Expanded(child: _buildInfoItem('声道数', '$_channels')),
                            Expanded(child: _buildInfoItem('位深度', '$_bitsPerSample bit')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                
                // Android PCM测试导航按钮
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.android, color: Colors.orange[700], size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Android PCM测试',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange[700]),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '专门测试Android端的PCM数据实时回传功能',
                        style: TextStyle(fontSize: 12, color: Colors.orange[600]),
                      ),
                      SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AndroidPcmTestPage(),
                              ),
                            );
                          },
                          icon: Icon(Icons.play_arrow),
                          label: Text('开始Android PCM测试'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange[600],
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // PCM文件信息
                if (_audioPcmFilePath != null) ...[
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.file_present, color: Colors.blue[700], size: 20),
                            SizedBox(width: 8),
                            Text(
                              'PCM文件信息',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue[700]),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          '文件路径: $_audioPcmFilePath',
                          style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                        ),
                        if (_totalPcmBytes > 0 && _sampleRate > 0) ...[
                          SizedBox(height: 4),
                          Text(
                            '预计时长: ${AudioUtils.calculateAudioDuration(_totalPcmBytes, _sampleRate, _channels, _bitsPerSample).inSeconds} 秒',
                            style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 视频显示区域
          Expanded(
            child: OrientationBuilder(
              builder: (context, orientation) {
                return Center(
                    child: Container(
                      margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height,
                      decoration: BoxDecoration(color: Colors.black54),
                      child: LayoutBuilder(
                          builder: (BuildContext context, BoxConstraints constraints) {
                            return GestureDetector(
                              onScaleStart: (details) {},
                              onScaleUpdate: (details) {
                                if (details.scale != 1.0) {
                                  setZoom(details.scale);
                                }
                              },
                              onTapDown: (TapDownDetails details) =>
                                  onViewFinderTap(details, constraints),
                              child: RTCVideoView(_localRenderer, mirror: false),
                            );
                          }),
                    ));
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _inCalling ? _hangUp : _makeCall,
        tooltip: _inCalling ? 'Hangup' : 'Call',
        child: Icon(_inCalling ? Icons.call_end : Icons.phone),
      ),
    );
  }

  // 构建信息项的小部件
  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  void _selectAudioOutput(String deviceId) {
    _localRenderer.audioOutput(deviceId);
  }
}
