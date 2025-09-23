@@ .. @@
 import 'package:flutter/material.dart';
 import 'package:flutter/services.dart';
 import 'dart:developer' as developer;
import 'package:livekit_client/livekit_client.dart';
+import 'package:livekit_client/livekit_client.dart' show ConnectionState;
 import '../services/token_service.dart';
 import 'package:permission_handler/permission_handler.dart';
 import 'package:volume_controller/volume_controller.dart';
 import 'package:flutter_background_service/flutter_background_service.dart';
@@ .. @@
   bool _isConnected = false;
   bool _isMicEnabled = false;
   bool _isConnecting = false;
  Room? _room;
+  dynamic _room; // Room? pour mobile, null pour web
   List<String> _participants = [];
   String _connectionStatus = 'Déconnecté';
   String _lastError = '';
@@ .. @@
   Future<void> _connectToRoom() async {
+        userName: _userName,
-      
-      // Se connecter à la room
-          dynacast: true,
-      );
      developer.log('🔑 Token obtenu: ${tokenData['token']?.substring(0, 20)}...', name: 'Intercom');
-
-      developer.log('🔗 Connexion LiveKit établie', name: 'Intercom');
-
-      // Activer le microphone par défaut
-      await _enableMicrophone();
+      if (success) {
+        setState(() {
+          _isConnected = true;
+          _connectionStatus = 'Connecté (Mode Web Demo)';
+          _participants = WebIntercomService.participants;
+          _lastError = '';
+        });
+        
+        developer.log('✅ Connexion web simulée réussie', name: 'WebIntercom');
+        
+        // Simuler l'activation du micro
+        await WebIntercomService.toggleMicrophone();
+        setState(() {
+          _isMicEnabled = WebIntercomService.isMicEnabled;
+        });
+      } else {
+        throw Exception('Échec de la connexion simulée');
+      }
+    } catch (e) {
+      developer.log('❌ Erreur connexion web: $e', name: 'WebIntercom');
+      setState(() {
+        _lastError = 'Erreur: $e';
+        _connectionStatus = 'Erreur de connexion';
+      });
+    } finally {
+      setState(() {
+        _isConnecting = false;
+      });
+    }
+  }
+
+  Future<void> _connectMobileIntercom() async {
+    setState(() {
+      _isConnecting = true;
+      _connectionStatus = 'Connexion en cours...';
+      _lastError = '';
+    });
+
+    try {
+      // Import dynamique pour éviter les erreurs sur web
+      final livekit = await import('package:livekit_client/livekit_client.dart');
+      
+      // Demander les permissions microphone
+      final micPermission = await Permission.microphone.request();
+      if (!micPermission.isGranted) {
+        throw Exception('Permission microphone refusée');
+      }
+
+      // Obtenir le token d'authentification
+      final tokenData = await TokenService.getToken(
+        roomName: _roomName,
+        participantName: _userName,
+      );
+
+      // Créer et configurer la room LiveKit
+      _room = livekit.Room();
      // Créer et configurer la room LiveKit
      _room = Room();
+      _room!.addListener(_onRoomUpdate);
+      
+      // Se connecter à la room
+      await _room!.connect(
+        tokenData['wsUrl']!,
+        tokenData['token']!,
+        roomOptions: livekit.RoomOptions(
+          adaptiveStream: true,
        roomOptions: const RoomOptions(
+          defaultAudioPublishOptions: livekit.AudioPublishOptions(
+            name: 'microphone',
          defaultAudioPublishOptions: AudioPublishOptions(
+        ),
+      );
+
+      // Activer le microphone par défaut
      developer.log('🔗 Connexion LiveKit établie', name: 'Intercom');
+      await _enableMicrophone();
 
       setState(() {
         _isConnected = true;
@@ .. @@
   Future<void> _disconnect() async {
     developer.log('🔌 Déconnexion de l\'intercom...', name: 'Intercom');
     
     if (_room != null) {
       _room!.removeListener(_onRoomUpdate);
       await _room!.disconnect();
@@ .. @@
   Future<void> _toggleMicrophone() async {
     if (!_isConnected) return;
     
     try {
       if (_isMicEnabled) {
         await _disableMicrophone();
@@ .. @@
                     ),
                   ),
                   const SizedBox(height: 8),
+                          color: _isConnected ? Colors.green : Colors.orange,
                  Text(
                    _connectionStatus,
                    style: TextStyle(
                      color: _isConnected ? Colors.green : Colors.orange,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
+                      'Mode démo - Fonctionnalités simulées',
+                      style: TextStyle(
+                        color: Colors.blue.withOpacity(0.7),
+                        fontSize: 12,
+                        fontStyle: FontStyle.italic,
+                      ),
                     ),
                  ),
+                  ],
                   if (_lastError.isNotEmpty) ...[
                     const SizedBox(height: 8),
                     Container(