import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sdp_transform/sdp_transform.dart' as sdp_transform;

void setPreferredCodec(RTCSessionDescription description,
    {String audio = 'opus', String video = 'vp8'}) {
  var capSel = CodecCapabilitySelector(description.sdp!);
  var acaps = capSel.getCapabilities('audio');
  if (acaps != null) {
    acaps.codecs = acaps.codecs
        .where((e) => (e['codec'] as String).toLowerCase() == audio)
        .toList();
    acaps.setCodecPreferences('audio', acaps.codecs);
    capSel.setCapabilities(acaps);
  }

  var vcaps = capSel.getCapabilities('video');
  if (vcaps != null) {
    vcaps.codecs = vcaps.codecs
        .where((e) => (e['codec'] as String).toLowerCase() == video)
        .toList();
    vcaps.setCodecPreferences('video', vcaps.codecs);
    capSel.setCapabilities(vcaps);
  }
  description.sdp = capSel.sdp();
}

class CodecCapability {
  CodecCapability(
      this.kind, this.payloads, this.codecs, this.fmtp, this.rtcpFb) {
    codecs.forEach((element) {
      element['orign_payload'] = element['payload'];
    });
  }
  String kind;
  List<dynamic> rtcpFb;
  List<dynamic> fmtp;
  List<String> payloads;
  List<dynamic> codecs;
  bool setCodecPreferences(String kind, List<dynamic>? newCodecs) {
    if (newCodecs == null) {
      return false;
    }
    var newRtcpFb = <dynamic>[];
    var newFmtp = <dynamic>[];
    var newPayloads = <String>[];
    newCodecs.forEach((element) {
      var orign_payload = element['orign_payload'] as int;
      var payload = element['payload'] as int;
      // change payload type
      if (payload != orign_payload) {
        newRtcpFb.addAll(rtcpFb.where((e) {
          if (e['payload'] == orign_payload) {
            e['payload'] = payload;
            return true;
          }
          return false;
        }).toList());
        newFmtp.addAll(fmtp.where((e) {
          if (e['payload'] == orign_payload) {
            e['payload'] = payload;
            return true;
          }
          return false;
        }).toList());
        if (payloads.contains('$orign_payload')) {
          newPayloads.add('$payload');
        }
      } else {
        newRtcpFb.addAll(rtcpFb.where((e) => e['payload'] == payload).toList());
        newFmtp.addAll(fmtp.where((e) => e['payload'] == payload).toList());
        newPayloads.addAll(payloads.where((e) => e == '$payload').toList());
      }
    });
    rtcpFb = newRtcpFb;
    fmtp = newFmtp;
    payloads = newPayloads;
    codecs = newCodecs;
    return true;
  }
}

class CodecCapabilitySelector {
  CodecCapabilitySelector(String sdp) {
    _sdp = sdp;
    _session = sdp_transform.parse(_sdp);
  }
  late String _sdp;
  late Map<String, dynamic> _session;
  Map<String, dynamic> get session => _session;
  String sdp() => sdp_transform.write(_session, null);

  CodecCapability? getCapabilities(String kind) {
    var mline = _mline(kind);
    if (mline == null) {
      return null;
    }
    var rtcpFb = mline['rtcpFb'] ?? <dynamic>[];
    var fmtp = mline['fmtp'] ?? <dynamic>[];
    var payloads = (mline['payloads'] as String).split(' ');
    var codecs = mline['rtp'] ?? <dynamic>[];
    return CodecCapability(kind, payloads, codecs, fmtp, rtcpFb);
  }

  bool setCapabilities(CodecCapability? caps) {
    if (caps == null) {
      return false;
    }
    var mline = _mline(caps.kind);
    if (mline == null) {
      return false;
    }
    mline['payloads'] = caps.payloads.join(' ');
    mline['rtp'] = caps.codecs;
    mline['fmtp'] = caps.fmtp;
    mline['rtcpFb'] = caps.rtcpFb;
    return true;
  }

  Map<String, dynamic>? _mline(String kind) {
    var mlist = _session['media'] as List<dynamic>;
    return mlist.firstWhere((element) => element['type'] == kind,
        orElse: () => null);
  }
}

class PermissionUtils {
  /// 检查并请求Android设备所需的所有权限
  static Future<bool> checkAndRequestAllPermissions(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    try {
      // 请求相机权限
      var cameraStatus = await Permission.camera.request();
      if (cameraStatus.isDenied || cameraStatus.isPermanentlyDenied) {
        _showPermissionDialog(context, '相机权限', '需要相机权限来录制视频');
        return false;
      }

      // 请求麦克风权限
      var microphoneStatus = await Permission.microphone.request();
      if (microphoneStatus.isDenied || microphoneStatus.isPermanentlyDenied) {
        _showPermissionDialog(context, '麦克风权限', '需要麦克风权限来录制音频');
        return false;
      }

      // 请求存储权限
      var storageStatus = await Permission.storage.request();
      if (storageStatus.isDenied || storageStatus.isPermanentlyDenied) {
        _showPermissionDialog(context, '存储权限', '需要存储权限来保存录制文件');
        return false;
      }

      print('所有权限已获取: 相机=$cameraStatus, 麦克风=$microphoneStatus, 存储=$storageStatus');
      return true;

    } catch (e) {
      print('权限检查失败: $e');
      return false;
    }
  }

  /// 检查特定权限
  static Future<bool> checkSpecificPermission(Permission permission) async {
    var status = await permission.status;
    return status.isGranted;
  }

  /// 请求特定权限
  static Future<bool> requestSpecificPermission(Permission permission) async {
    var status = await permission.request();
    return status.isGranted;
  }

  /// 显示权限说明对话框
  static void _showPermissionDialog(BuildContext context, String permissionName, String description) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('需要$permissionName'),
          content: Text(description),
          actions: <Widget>[
            TextButton(
              child: Text('取消'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('去设置'),
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
            ),
          ],
        );
      },
    );
  }

  /// 获取权限状态描述
  static String getPermissionStatusDescription(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
        return '已授权';
      case PermissionStatus.denied:
        return '已拒绝';
      case PermissionStatus.permanentlyDenied:
        return '永久拒绝';
      case PermissionStatus.restricted:
        return '受限制';
      case PermissionStatus.limited:
        return '有限权限';
      case PermissionStatus.provisional:
        return '临时权限';
      default:
        return '未知状态';
    }
  }

  /// 检查是否所有必要权限都已获取
  static Future<Map<Permission, bool>> checkAllRequiredPermissions() async {
    Map<Permission, bool> results = {};

    List<Permission> requiredPermissions = [
      Permission.camera,
      Permission.microphone,
      Permission.storage
    ];

    for (Permission permission in requiredPermissions) {
      bool isGranted = await checkSpecificPermission(permission);
      results[permission] = isGranted;
    }

    return results;
  }
}

class AudioUtils {
  /// 格式化音频数据大小
  static String formatAudioDataSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  /// 格式化采样率
  static String formatSampleRate(int sampleRate) {
    if (sampleRate >= 1000) {
      return '${(sampleRate / 1000).toStringAsFixed(1)} kHz';
    }
    return '$sampleRate Hz';
  }

  /// 计算音频时长（基于PCM数据）
  static Duration calculateAudioDuration(int totalBytes, int sampleRate, int channels, int bitsPerSample) {
    if (sampleRate <= 0 || channels <= 0 || bitsPerSample <= 0) {
      return Duration.zero;
    }

    // PCM数据大小 = 采样率 × 声道数 × 位深度/8 × 时长
    // 时长 = 数据大小 / (采样率 × 声道数 × 位深度/8)
    double bytesPerSecond = sampleRate * channels * (bitsPerSample / 8);
    int durationMicroseconds = (totalBytes / bytesPerSecond * 1000000).round();

    return Duration(microseconds: durationMicroseconds);
  }
}
