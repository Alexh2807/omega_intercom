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
import android.media.AudioFocusRequest
import android.media.AudioAttributes as SysAudioAttributes
import android.content.pm.PackageManager
import android.media.AudioDeviceCallback
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.BlockingQueue
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val channelName = "intercom_native_audio"
    private val fgChannelName = "intercom_fg_service"
    private val metricsChannelName = "debug.metrics"
    private var audioTrack: AudioTrack? = null
    private var writerThread: Thread? = null
    private var running = AtomicBoolean(false)
    private var queue: BlockingQueue<ByteArray>? = null
    private var sampleRate = 16000
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
    private val focusListener = AudioManager.OnAudioFocusChangeListener { _ ->
        // Optional: react to focus changes (pause/duck)
    }
    private var deviceCallback: AudioDeviceCallback? = null

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fgChannelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "start" -> {
                        val args = call.arguments as? Map<*, *>
                        val title = (args?.get("title") as? String) ?: "Intercom actif"
                        val body = (args?.get("body") as? String) ?: "En cours"
                        try {
                            val ctx = applicationContext
                            IntercomFgService.ensureChannel(ctx)
                            val intent = android.content.Intent(ctx, IntercomFgService::class.java)
                            intent.putExtra(IntercomFgService.EXTRA_TITLE, title)
                            intent.putExtra(IntercomFgService.EXTRA_BODY, body)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                ctx.startForegroundService(intent)
                            } else {
                                ctx.startService(intent)
                            }
                            result.success(null)
                        } catch (t: Throwable) {
                            result.error("fg_start_error", t.message, null)
                        }
                    }
                    "stop" -> {
                        try {
                            val ctx = applicationContext
                            val intent = android.content.Intent(ctx, IntercomFgService::class.java)
                            ctx.stopService(intent)
                            result.success(null)
                        } catch (t: Throwable) {
                            result.error("fg_stop_error", t.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Debug metrics channel: returns CPU% (app), MEM% (device used), app PSS MB
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, metricsChannelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "sample" -> {
                        try {
                            val cpuPct = sampleAppCpuPercent()
                            val mem = sampleMem(applicationContext)
                            val out: HashMap<String, Any> = hashMapOf(
                                "cpuAppPct" to cpuPct,
                                "memUsedPct" to mem.first,
                                "memAppMB" to mem.second
                            )
                            result.success(out)
                        } catch (t: Throwable) {
                            result.error("metrics_error", t.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // App config channel: read AndroidManifest <meta-data>
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.config")
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "getMeta" -> {
                        val args = call.arguments as? Map<*, *>
                        val name = (args?.get("name") as? String)
                        if (name == null) {
                            result.error("bad_args", "missing name", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val pm = applicationContext.packageManager
                            val ai = pm.getApplicationInfo(applicationContext.packageName, PackageManager.GET_META_DATA)
                            val v = ai.metaData?.getString(name)
                            result.success(v)
                        } catch (t: Throwable) {
                            result.error("meta_error", t.message, null)
                        }
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
        requestAudioFocus(am)
        registerDeviceCallback(am)
        // Préférer intercom Bluetooth SCO si dispo, sinon fallback haut-parleur
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val devices = am.availableCommunicationDevices
                val btSco = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
                if (btSco != null) {
                    am.setCommunicationDevice(btSco)
                } else {
                    val speaker = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    if (speaker != null) am.setCommunicationDevice(speaker)
                }
            } else {
                @Suppress("DEPRECATION")
                run {
                    am.mode = AudioManager.MODE_IN_COMMUNICATION
                    if (am.isBluetoothScoAvailableOffCall) {
                        try { am.startBluetoothSco(); } catch (_: Throwable) {}
                        @Suppress("DEPRECATION") am.isBluetoothScoOn = true
                        @Suppress("DEPRECATION") am.isSpeakerphoneOn = false
                    } else {
                        @Suppress("DEPRECATION") am.isSpeakerphoneOn = true
                    }
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
                // Release focus and callbacks
                abandonAudioFocus(am)
                unregisterDeviceCallback(am)
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

    private fun requestAudioFocus(am: AudioManager) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = SysAudioAttributes.Builder()
                    .setUsage(SysAudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(SysAudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
                val fr = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .setOnAudioFocusChangeListener(focusListener)
                    .setAcceptsDelayedFocusGain(false)
                    .setAudioAttributes(attrs)
                    .build()
                val res = am.requestAudioFocus(fr)
                if (res == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                    focusRequest = fr
                }
            } else {
                @Suppress("DEPRECATION")
                am.requestAudioFocus(focusListener, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            }
        } catch (_: Throwable) {}
    }

    private fun abandonAudioFocus(am: AudioManager) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focusRequest?.let { am.abandonAudioFocusRequest(it) }
                focusRequest = null
            } else {
                @Suppress("DEPRECATION")
                am.abandonAudioFocus(focusListener)
            }
        } catch (_: Throwable) {}
    }

    private fun registerDeviceCallback(am: AudioManager) {
        if (deviceCallback != null) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                deviceCallback = object : AudioDeviceCallback() {
                    override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                        configureRouting(am)
                    }
                    override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                        configureRouting(am)
                    }
                }
                am.registerAudioDeviceCallback(deviceCallback!!, null)
            }
        } catch (_: Throwable) {}
    }

    private fun unregisterDeviceCallback(am: AudioManager) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                deviceCallback?.let { am.unregisterAudioDeviceCallback(it) }
                deviceCallback = null
            }
        } catch (_: Throwable) {}
    }

    private fun configureRouting(am: AudioManager) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val devices = am.availableCommunicationDevices
                val btSco = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
                if (btSco != null) {
                    am.setCommunicationDevice(btSco)
                } else {
                    val speaker = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    if (speaker != null) am.setCommunicationDevice(speaker)
                }
            }
        } catch (_: Throwable) {}
    }
}

private var prevProcTicks: Long = 0L
private var prevTotalTicks: Long = 0L

private fun readProcSelfTicks(): Long {
    return try {
        val stat = java.io.RandomAccessFile("/proc/self/stat", "r").use { it.readLine() }
        // fields separated by space; utime=14, stime=15
        val parts = stat.split(" ")
        val utime = parts[13].toLong()
        val stime = parts[14].toLong()
        utime + stime
    } catch (_: Throwable) {
        0L
    }
}

private fun readTotalCpuTicks(): Long {
    return try {
        val line = java.io.RandomAccessFile("/proc/stat", "r").use { it.readLine() }
        // line like: cpu  3357 0 4313 1362393 0 0 0 0 0 0
        val parts = line.trim().split(Regex("\\s+")).drop(1) // skip 'cpu'
        parts.take(8).map { it.toLong() }.sum()
    } catch (_: Throwable) {
        0L
    }
}

private fun sampleAppCpuPercent(): Double {
    val proc = readProcSelfTicks()
    val total = readTotalCpuTicks()
    val dProc = (proc - prevProcTicks).coerceAtLeast(0L)
    val dTotal = (total - prevTotalTicks).coerceAtLeast(1L)
    prevProcTicks = proc
    prevTotalTicks = total
    val cpuCount = Runtime.getRuntime().availableProcessors().coerceAtLeast(1)
    val ratio = dProc.toDouble() / dTotal.toDouble()
    val pct = ratio * 100.0 * cpuCount.toDouble()
    return pct.coerceIn(0.0, 100.0)
}

private fun sampleMem(ctx: Context): Pair<Double, Double> {
    return try {
        val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        val mi = android.app.ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)
        val usedPct = if (mi.totalMem > 0) ((mi.totalMem - mi.availMem).toDouble() / mi.totalMem.toDouble()) * 100.0 else 0.0
        val pssKb = android.os.Debug.getPss().toDouble()
        val appMb = pssKb / 1024.0
        Pair(usedPct.coerceIn(0.0, 100.0), appMb)
    } catch (_: Throwable) {
        Pair(0.0, 0.0)
    }
}
