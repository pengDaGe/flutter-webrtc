package com.cloudwebrtc.webrtc.record;

import android.annotation.SuppressLint;
import android.util.Log;

import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin;
import com.cloudwebrtc.webrtc.utils.ConstraintsMap;

import org.webrtc.audio.JavaAudioDeviceModule.SamplesReadyCallback;
import org.webrtc.audio.JavaAudioDeviceModule.AudioSamples;

import java.util.HashMap;

/** JavaAudioDeviceModule allows attaching samples callback only on building
 *  We don't want to instantiate VideoFileRenderer and codecs at this step
 *  It's simple dummy class, it does nothing until samples are necessary */
@SuppressWarnings("WeakerAccess")
public class AudioSamplesInterceptor implements SamplesReadyCallback {

    private static final String TAG = "AudioSamplesInterceptor";

    @SuppressLint("UseSparseArrays")
    protected final HashMap<Integer, SamplesReadyCallback> callbacks = new HashMap<>();
    
    // 添加recorderId到PCM数据回传的映射
    private final HashMap<Integer, Boolean> pcmEnabledRecorders = new HashMap<>();

    @Override
    public void onWebRtcAudioRecordSamplesReady(AudioSamples audioSamples) {

        Log.w(TAG, "数据进来了");
        // 实时PCM数据回传
        sendPcmDataToFlutter(audioSamples);
        
        // 原有的录制回调
        for (SamplesReadyCallback callback : callbacks.values()) {
            callback.onWebRtcAudioRecordSamplesReady(audioSamples);
        }
    }

    public void attachCallback(Integer id, SamplesReadyCallback callback) throws Exception {
        callbacks.put(id, callback);
    }

    public void detachCallback(Integer id) {
        callbacks.remove(id);
        pcmEnabledRecorders.remove(id);
    }
    
    /**
     * 启用指定recorder的PCM数据回传
     */
    public void enablePcmData(Integer recorderId) {
        pcmEnabledRecorders.put(recorderId, true);
        Log.d(TAG, "启用PCM数据回传，recorderId: " + recorderId);
    }
    
    /**
     * 禁用指定recorder的PCM数据回传
     */
    public void disablePcmData(Integer recorderId) {
        pcmEnabledRecorders.remove(recorderId);
        Log.d(TAG, "禁用PCM数据回传，recorderId: " + recorderId);
    }
    
    /**
     * 发送PCM数据到Flutter端
     */
    private void sendPcmDataToFlutter(AudioSamples audioSamples) {
        if (pcmEnabledRecorders.isEmpty()) {
            return; // 没有启用的recorder，不发送数据
        }
        
        try {
            byte[] data = audioSamples.getData();
            int sampleRate = audioSamples.getSampleRate();
            int channels = audioSamples.getChannelCount();
            int bitsPerSample = 16; // WebRTC默认使用16位PCM
            
            // 为每个启用的recorder发送PCM数据
            for (Integer recorderId : pcmEnabledRecorders.keySet()) {
                ConstraintsMap params = new ConstraintsMap();
                params.putString("event", "onAudioPcmData");
                params.putInt("recorderId", recorderId);
                params.putInt("sampleRate", sampleRate);
                params.putInt("numOfChannels", channels);
                params.putInt("bitsPerSample", bitsPerSample);
                params.putByte("data", data);
                
                // 通过插件单例发送事件（判空以避免崩溃）
                if (FlutterWebRTCPlugin.sharedSingleton != null) {
                    FlutterWebRTCPlugin.sharedSingleton.sendEvent(params.toMap());
                    Log.v(TAG, String.format("事件已发送: onAudioPcmData, recorderId=%d, len=%d, sr=%d, ch=%d",
                            recorderId, data.length, sampleRate, channels));
                } else {
                    Log.w(TAG, "FlutterWebRTCPlugin.sharedSingleton 为空，事件未发送");
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "发送PCM数据到Flutter失败: " + e.getMessage(), e);
        }
    }
}
