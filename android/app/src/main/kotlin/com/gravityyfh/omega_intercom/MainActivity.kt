package com.gravityyfh.omega_intercom

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    
    private var bluetoothAudioHandler: BluetoothAudioHandler? = null
    private var robustBluetoothManager: RobustBluetoothManager? = null
    private val AUDIO_ROUTING_CHANNEL = "omega/audio_routing"
    private val BROADCAST_CHANNEL = "com.gravityyfh.omega_intercom/broadcast"
    private var serviceUpdateReceiver: BroadcastReceiver? = null
    private var broadcastEventSink: EventChannel.EventSink? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialiser l'ancien gestionnaire Bluetooth (rétrocompatibilité)
        bluetoothAudioHandler = BluetoothAudioHandler(this)
        
        // Initialiser le nouveau gestionnaire Bluetooth robuste
        robustBluetoothManager = RobustBluetoothManager(this)
        
        // Configurer l'ancien canal Bluetooth (rétrocompatibilité)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BluetoothAudioHandler.CHANNEL_NAME
        ).setMethodCallHandler(bluetoothAudioHandler)
        
        // Configurer le nouveau canal Bluetooth robuste
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RobustBluetoothManager.CHANNEL_NAME
        ).setMethodCallHandler(robustBluetoothManager)
        
        // Canal d'événements pour l'ancien système
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BluetoothAudioHandler.EVENT_CHANNEL_NAME
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                bluetoothAudioHandler?.setEventSink(events)
            }
            
            override fun onCancel(arguments: Any?) {
                bluetoothAudioHandler?.setEventSink(null)
            }
        })
        
        // Canal d'événements pour le nouveau système robuste
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RobustBluetoothManager.EVENT_CHANNEL_NAME
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                robustBluetoothManager?.setEventSink(events)
            }
            
            override fun onCancel(arguments: Any?) {
                robustBluetoothManager?.setEventSink(null)
            }
        })

        // Configurer le canal pour le service de routage audio
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AUDIO_ROUTING_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val username = call.argument<String>("username") ?: "Utilisateur"
                    val room = call.argument<String>("room") ?: "Salon"
                    val micEnabled = call.argument<Boolean>("micEnabled") ?: false
                    val isConnected = call.argument<Boolean>("isConnected") ?: false
                    
                    val i = Intent(this, AudioRoutingService::class.java).apply {
                        action = AudioRoutingService.ACTION_START
                        putExtra("username", username)
                        putExtra("room", room)
                        putExtra("micEnabled", micEnabled)
                        putExtra("isConnected", isConnected)
                    }
                    startForegroundService(i)
                    result.success(true)
                }
                "stopService" -> {
                    val i = Intent(this, AudioRoutingService::class.java).apply {
                        action = AudioRoutingService.ACTION_STOP
                    }
                    startService(i)
                    result.success(true)
                }
                "enableSco" -> {
                    val i = Intent(this, AudioRoutingService::class.java).apply {
                        action = AudioRoutingService.ACTION_ENABLE_SCO
                    }
                    startService(i)
                    result.success(true)
                }
                "disableSco" -> {
                    val i = Intent(this, AudioRoutingService::class.java).apply {
                        action = AudioRoutingService.ACTION_DISABLE_SCO
                    }
                    startService(i)
                    result.success(true)
                }
                "speakerOn" -> {
                    val i = Intent(this, AudioRoutingService::class.java).apply {
                        action = AudioRoutingService.ACTION_SPEAKER_ON
                    }
                    startService(i)
                    result.success(true)
                }
                "speakerOff" -> {
                    val i = Intent(this, AudioRoutingService::class.java).apply {
                        action = AudioRoutingService.ACTION_SPEAKER_OFF
                    }
                    startService(i)
                    result.success(true)
                }
                "updateNotificationState" -> {
                    val username = call.argument<String>("username")
                    val room = call.argument<String>("room")
                    val micEnabled = call.argument<Boolean>("micEnabled")
                    val isConnected = call.argument<Boolean>("isConnected")
                    val audioRoute = call.argument<String>("audioRoute")
                    val scoEnabled = call.argument<Boolean>("scoEnabled")
                    
                    // Appeler la méthode du service pour mettre à jour la notification
                    // (nécessiterait une interface ou un binding service, pour simplifier on utilisera un broadcast)
                    val i = Intent("com.gravityyfh.omega_intercom.UPDATE_NOTIFICATION").apply {
                        putExtra("username", username)
                        putExtra("room", room)
                        putExtra("micEnabled", micEnabled)
                        putExtra("isConnected", isConnected)
                        putExtra("audioRoute", audioRoute)
                        putExtra("scoEnabled", scoEnabled)
                    }
                    sendBroadcast(i)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        
        // Configurer le canal de broadcast pour la communication Flutter ↔ Android
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BROADCAST_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendBroadcast" -> {
                    val action = call.argument<String>("action") ?: ""
                    val data = call.argument<Map<String, Any>>("data") ?: emptyMap()
                    
                    when (action) {
                        "update_notification" -> {
                            val intent = Intent("com.gravityyfh.omega_intercom.UPDATE_NOTIFICATION").apply {
                                putExtra("username", data["username"] as? String)
                                putExtra("room", data["room"] as? String)
                                putExtra("micEnabled", data["micEnabled"] as? Boolean ?: false)
                                putExtra("isConnected", data["isConnected"] as? Boolean ?: false)
                                putExtra("audioRoute", data["audioRoute"] as? String)
                                putExtra("scoEnabled", data["scoEnabled"] as? Boolean ?: false)
                            }
                            sendBroadcast(intent)
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        
        // Configurer le récepteur de broadcast pour les mises à jour du service
        setupServiceUpdateReceiver(flutterEngine)
        
        // Configurer le canal de broadcast pour les événements du service
        setupBroadcastChannel(flutterEngine)
    }
    
    private fun setupServiceUpdateReceiver(flutterEngine: FlutterEngine) {
        serviceUpdateReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "com.gravityyfh.omega_intercom.SERVICE_UPDATE") {
                    val action = intent.getStringExtra("action")
                    when (action) {
                        "mic_toggled" -> {
                            val micEnabled = intent.getBooleanExtra("value", false)
                            // Envoyer l'info à Flutter via le canal
                            MethodChannel(
                                flutterEngine.dartExecutor.binaryMessenger,
                                AUDIO_ROUTING_CHANNEL
                            ).invokeMethod("onMicToggled", mapOf("enabled" to micEnabled))
                        }
                        "reconnect_requested" -> {
                            // Envoyer l'événement de reconnexion à Flutter
                            broadcastEventSink?.success(mapOf("action" to "reconnect_requested", "value" to true))
                        }
                        "disconnect_requested" -> {
                            // Envoyer l'événement de déconnexion à Flutter
                            broadcastEventSink?.success(mapOf("action" to "disconnect_requested", "value" to true))
                        }
                        "audio_route_requested" -> {
                            // Envoyer l'événement de changement de route à Flutter
                            val route = intent.getStringExtra("value")
                            broadcastEventSink?.success(mapOf("action" to "audio_route_requested", "value" to route))
                        }
                        "route_toggled" -> {
                            val route = intent.getStringExtra("value")
                            broadcastEventSink?.success(mapOf("action" to "route_toggled", "value" to route))
                        }
                    }
                }
            }
        }
        
        registerReceiver(serviceUpdateReceiver, IntentFilter("com.gravityyfh.omega_intercom.SERVICE_UPDATE"), Context.RECEIVER_NOT_EXPORTED)
    }
    
    private fun setupBroadcastChannel(flutterEngine: FlutterEngine) {
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BROADCAST_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                broadcastEventSink = events
            }
            
            override fun onCancel(arguments: Any?) {
                broadcastEventSink = null
            }
        })
    }
    
    override fun onDestroy() {
        bluetoothAudioHandler?.cleanup()
        robustBluetoothManager?.cleanup()
        serviceUpdateReceiver?.let { unregisterReceiver(it) }
        super.onDestroy()
    }
}