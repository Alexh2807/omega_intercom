import 'dart:developer' as developer;

/// Service d'intercom simulé pour le web
/// Remplace les fonctionnalités LiveKit qui ne sont pas disponibles sur web
class WebIntercomService {
  static bool _isConnected = false;
  static bool _isMicEnabled = false;
  static String _currentRoom = '';
  static String _currentUser = '';
  static List<String> _participants = [];

  static bool get isConnected => _isConnected;
  static bool get isMicEnabled => _isMicEnabled;
  static String get currentRoom => _currentRoom;
  static List<String> get participants => _participants;

  static Future<bool> connect({
    required String serverUrl,
    required String token,
    required String roomName,
    required String userName,
  }) async {
    developer.log('🌐 [WEB] Simulation connexion intercom', name: 'WebIntercom');
    
    // Simulation d'une connexion
    await Future.delayed(const Duration(seconds: 2));
    
    _isConnected = true;
    _currentRoom = roomName;
    _currentUser = userName;
    _participants = [userName, 'Utilisateur Demo 1', 'Utilisateur Demo 2'];
    
    developer.log('✅ [WEB] Connexion simulée réussie', name: 'WebIntercom');
    return true;
  }

  static Future<void> disconnect() async {
    developer.log('🌐 [WEB] Déconnexion intercom simulée', name: 'WebIntercom');
    
    _isConnected = false;
    _currentRoom = '';
    _currentUser = '';
    _participants.clear();
    _isMicEnabled = false;
  }

  static Future<void> toggleMicrophone() async {
    if (!_isConnected) return;
    
    _isMicEnabled = !_isMicEnabled;
    developer.log('🎤 [WEB] Micro ${_isMicEnabled ? "activé" : "désactivé"}', name: 'WebIntercom');
  }

  static void simulateParticipantJoin(String userName) {
    if (!_participants.contains(userName)) {
      _participants.add(userName);
      developer.log('👤 [WEB] $userName a rejoint la room', name: 'WebIntercom');
    }
  }

  static void simulateParticipantLeave(String userName) {
    _participants.remove(userName);
    developer.log('👤 [WEB] $userName a quitté la room', name: 'WebIntercom');
  }
}