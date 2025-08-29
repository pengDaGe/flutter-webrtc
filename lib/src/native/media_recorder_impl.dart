import 'dart:async';
import 'dart:typed_data';
import 'dart:math';

import 'package:webrtc_interface/webrtc_interface.dart';

import 'media_stream_track_impl.dart';
import 'utils.dart';
import 'event_channel.dart';

class MediaRecorderNative extends MediaRecorder {
  MediaRecorderNative({
    String? albumName = 'FlutterWebRTC',
  }) : _albumName = albumName;
  static final _random = Random();
  final _recorderId = _random.nextInt(0x7FFFFFFF);
  var _isStarted = false;
  final String? _albumName;
  StreamSubscription<Map<String, dynamic>>? _pcmSubscription;
  void Function(Uint8List data, int sampleRate, int channels, int bitsPerSample)? onPcm;

  @override
  Future<void> start(
      String path, {
        MediaStreamTrack? videoTrack,
        RecorderAudioChannel? audioChannel,
      }) async {
    if (audioChannel == null && videoTrack == null) {
      throw Exception('Neither audio nor video track were provided');
    }

    await WebRTC.invokeMethod('startRecordToFile', {
      'path': path,
      if (audioChannel != null) 'audioChannel': audioChannel.index,
      if (videoTrack != null) 'videoTrackId': videoTrack.id,
      'recorderId': _recorderId,
      'peerConnectionId': videoTrack is MediaStreamTrackNative
          ? videoTrack.peerConnectionId
          : null
    });
    _isStarted = true;

    _pcmSubscription?.cancel();
    _pcmSubscription = FlutterWebRTCEventChannel.instance.handleEvents.stream.listen((data) {
      final event = data.keys.first;
      if (event == 'onAudioPcmData') {
        final map = data[event]!;
        if (map['recorderId'] == _recorderId) {
          if (onPcm != null) {
            final Uint8List bytes = map['data'] as Uint8List;
            onPcm!(bytes, map['sampleRate'] as int, map['numOfChannels'] as int, map['bitsPerSample'] as int);
          }
        }
      }
    });
  }

  @override
  void startWeb(MediaStream stream,
      {Function(dynamic blob, bool isLastOne)? onDataChunk,
        String? mimeType,
        int timeSlice = 1000}) {
    throw 'It\'s for Flutter Web only';
  }

  @override
  Future<dynamic> stop() async {
    if (!_isStarted) {
      throw "Media recorder not started!";
    }
    final res = await WebRTC.invokeMethod('stopRecordToFile', {
      'recorderId': _recorderId,
      'albumName': _albumName,
    });
    await _pcmSubscription?.cancel();
    _pcmSubscription = null;
    onPcm = null;
    _isStarted = false;
    return res;
  }
}
