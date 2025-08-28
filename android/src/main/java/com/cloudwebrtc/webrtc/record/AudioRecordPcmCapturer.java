package com.cloudwebrtc.webrtc.record;

import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.util.Log;

import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin;
import com.cloudwebrtc.webrtc.utils.ConstraintsMap;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Captures PCM data using Android AudioRecord directly and posts onAudioPcmData events.
 * This acts as a fallback when WebRTC ADM callbacks are not available (no PeerConnection pipeline).
 */
public final class AudioRecordPcmCapturer {

    private static final String TAG = "AudioRecordCapturer";

    private final int recorderId;
    private final int sampleRate;
    private final int channelConfig;
    private final int audioFormat;

    private AudioRecord audioRecord;
    private Thread worker;
    private final AtomicBoolean isRunning = new AtomicBoolean(false);

    public AudioRecordPcmCapturer(int recorderId,
                                  int sampleRate,
                                  int channelConfig,
                                  int audioFormat) {
        this.recorderId = recorderId;
        this.sampleRate = sampleRate;
        this.channelConfig = channelConfig;
        this.audioFormat = audioFormat;
    }

    public void start() throws Exception {
        if (isRunning.get()) return;

        int minBuffer = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat);
        if (minBuffer <= 0) {
            throw new IllegalStateException("Invalid minBufferSize: " + minBuffer);
        }
        // Use a larger buffer to reduce risk of underruns
        int bufferSize = Math.max(minBuffer * 2, 4096);

        audioRecord = new AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                sampleRate,
                channelConfig,
                audioFormat,
                bufferSize
        );
        if (audioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
            throw new IllegalStateException("AudioRecord init failed, state=" + audioRecord.getState());
        }

        audioRecord.startRecording();
        if (audioRecord.getRecordingState() != AudioRecord.RECORDSTATE_RECORDING) {
            throw new IllegalStateException("AudioRecord not recording, state=" + audioRecord.getRecordingState());
        }

        isRunning.set(true);
        worker = new Thread(this::loopRead, "AudioRecordCapturer-" + recorderId);
        worker.start();
        Log.d(TAG, "AudioRecord started. sr=" + sampleRate + ", chCfg=" + channelConfig + ", fmt=" + audioFormat);
    }

    private void loopRead() {
        final int bytesPerSample = (audioFormat == AudioFormat.ENCODING_PCM_16BIT) ? 2 : 1;
        final int channels = (channelConfig == AudioFormat.CHANNEL_IN_MONO) ? 1 : 2;
        final int bitsPerSample = (audioFormat == AudioFormat.ENCODING_PCM_16BIT) ? 16 : 8;

        byte[] buffer = new byte[4096];
        while (isRunning.get()) {
            int read = 0;
            try {
                read = audioRecord.read(buffer, 0, buffer.length);
            } catch (Exception e) {
                Log.e(TAG, "AudioRecord.read error: " + e.getMessage(), e);
            }
            if (read > 0) {
                // Copy exact length
                byte[] data = new byte[read];
                System.arraycopy(buffer, 0, data, 0, read);

                ConstraintsMap params = new ConstraintsMap();
                params.putString("event", "onAudioPcmData");
                params.putInt("recorderId", recorderId);
                params.putInt("sampleRate", sampleRate);
                params.putInt("numOfChannels", channels);
                params.putInt("bitsPerSample", bitsPerSample);
                params.putByte("data", data);

                if (FlutterWebRTCPlugin.sharedSingleton != null) {
                    FlutterWebRTCPlugin.sharedSingleton.sendEvent(params.toMap());
                }
            } else if (read < 0) {
                Log.w(TAG, "AudioRecord.read returned " + read);
                try { Thread.sleep(10); } catch (InterruptedException ignored) {}
            }
        }
    }

    public void stop() {
        if (!isRunning.getAndSet(false)) return;
        Log.d(TAG, "Stopping AudioRecord...");
        try {
            if (worker != null) {
                worker.join(500);
            }
        } catch (InterruptedException ignored) {}
        try {
            if (audioRecord != null) {
                audioRecord.stop();
                audioRecord.release();
            }
        } catch (Exception e) {
            Log.w(TAG, "Stop/Release AudioRecord error: " + e.getMessage());
        } finally {
            audioRecord = null;
            worker = null;
        }
    }
}
