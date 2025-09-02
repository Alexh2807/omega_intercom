package com.gravityyfh.omega_intercom

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.content.Context
import android.media.AudioDeviceInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.BlockingQueue
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val channelName = "intercom_native_audio"
    private var audioTrack: AudioTrack? = null
    private var writerThread: Thread? = null
    private var running = AtomicBoolean(false)
    private var queue: BlockingQueue<ByteArray>? = null
    private var sampleRate = 16000
    private var audioManager: AudioManager? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "start" -> {
                        val args = call.arguments as? Map<*, *>
                        val sr = (args?.get("sr") as? Int) ?: 16000
                        try {
                            startPlayer(sr)
                            result.success(null)
                        } catch (t: Throwable) {
                            result.error("start_error", t.message, null)
                        }
                    }
                    "write" -> {
                        val bytes = call.arguments as? ByteArray
                        if (bytes == null || bytes.isEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        // Enqueue non-bloquant, drop si plein (préférer latence faible)
                        queue?.offer(bytes)
                        result.success(null)
                    }
                    "stop" -> {
                        stopPlayer()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startPlayer(sr: Int) {
        stopPlayer()
        sampleRate = sr
        queue = ArrayBlockingQueue(32)
        running.set(true)

        val am = audioManager ?: (getSystemService(Context.AUDIO_SERVICE) as AudioManager).also { audioManager = it }
        // Force haut-parleur
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val devices = am.availableCommunicationDevices
                val speaker = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                if (speaker != null) {
                    am.setCommunicationDevice(speaker)
                } else {
                    @Suppress("DEPRECATION")
                    am.mode = AudioManager.MODE_IN_COMMUNICATION
                    @Suppress("DEPRECATION")
                    am.isSpeakerphoneOn = true
                }
            } else {
                @Suppress("DEPRECATION")
                run {
                    am.mode = AudioManager.MODE_IN_COMMUNICATION
                    am.isSpeakerphoneOn = true
                }
            }
            // Diriger les touches volume sur la sortie voix/appareil
            @Suppress("DEPRECATION")
            setVolumeControlStream(AudioManager.STREAM_VOICE_CALL)
        } catch (_: Throwable) {}

        val channelOut = AudioFormat.CHANNEL_OUT_MONO
        val encoding = AudioFormat.ENCODING_PCM_16BIT
        val minBuf = AudioTrack.getMinBufferSize(sampleRate, channelOut, encoding)
        val bufferSize = (minBuf.coerceAtLeast(2048) * 2)

        audioTrack = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            val format = AudioFormat.Builder()
                .setEncoding(encoding)
                .setSampleRate(sampleRate)
                .setChannelMask(channelOut)
                .build()
            AudioTrack(
                attrs,
                format,
                bufferSize,
                AudioTrack.MODE_STREAM,
                AudioManager.AUDIO_SESSION_ID_GENERATE
            )
        } else {
            @Suppress("DEPRECATION")
            AudioTrack(
                // Préfère le haut-parleur sur anciens Android
                AudioManager.STREAM_MUSIC,
                sampleRate,
                channelOut,
                encoding,
                bufferSize,
                AudioTrack.MODE_STREAM
            )
        }

        audioTrack?.play()

        writerThread = Thread {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_AUDIO)
            val track = audioTrack
            if (track == null) {
                running.set(false)
                return@Thread
            }
            try {
                while (running.get()) {
                    val data = queue?.poll()
                    if (data == null) {
                        // Fine-grained wait to keep latency low
                        try { Thread.sleep(5) } catch (_: InterruptedException) {}
                        continue
                    }
                    var offset = 0
                    while (offset < data.size && running.get()) {
                        val written = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            track.write(data, offset, data.size - offset, AudioTrack.WRITE_NON_BLOCKING)
                        } else {
                            @Suppress("DEPRECATION")
                            track.write(data, offset, data.size - offset)
                        }
                        if (written <= 0) break
                        offset += written
                    }
                }
            } catch (_: Throwable) {
                // swallow
            }
        }
        writerThread?.isDaemon = true
        writerThread?.start()
    }

    private fun stopPlayer() {
        running.set(false)
        writerThread?.interrupt()
        writerThread = null
        queue?.clear()
        queue = null
        audioTrack?.let { track ->
            try {
                track.stop()
            } catch (_: Throwable) {}
            try {
                track.release()
            } catch (_: Throwable) {}
        }
        audioTrack = null

        // Rétablir le routage audio par défaut
        audioManager?.let { am ->
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    am.clearCommunicationDevice()
                }
                @Suppress("DEPRECATION")
                run {
                    am.isSpeakerphoneOn = false
                    am.mode = AudioManager.MODE_NORMAL
                }
                @Suppress("DEPRECATION")
                setVolumeControlStream(AudioManager.USE_DEFAULT_STREAM_TYPE)
            } catch (_: Throwable) {}
        }
    }
}
