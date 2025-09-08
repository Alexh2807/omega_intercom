# OMEGA Intercom - Système d'intercom temps réel avec LiveKit

## 📋 Description

Application Flutter combinant GPS et système d'intercom temps réel. L'intercom utilise **LiveKit** pour permettre la communication audio full-duplex entre plusieurs téléphones simultanément.

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│   Application   │    │   Backend Node   │    │   Serveur LiveKit   │
│     Flutter     │◄──►│  (Tokens JWT)    │◄──►│      + Redis        │
│                 │    │                  │    │                     │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
```

- **Flutter App**: Interface utilisateur + client LiveKit
- **Backend Node.js**: Génération des tokens d'authentification JWT
- **LiveKit Server**: Serveur SFU (Selective Forwarding Unit) pour l'audio temps réel
- **Redis**: Base de données en mémoire pour LiveKit

## 🚀 Installation et démarrage

### Prérequis

- Docker & Docker Compose
- Node.js 18+ 
- Flutter SDK
- Un PC avec l'IP `192.168.1.86` (ou modifier les configurations)

### 1. Démarrer le serveur LiveKit

```bash
# Dans le dossier racine du projet
docker-compose up -d

# Vérifier que les conteneurs sont actifs
docker-compose ps
```

Les services seront disponibles sur :
- **LiveKit Server**: `ws://192.168.1.86:7880`
- **Redis**: Port interne 6379

### 2. Démarrer le backend Node.js

```bash
# Aller dans le dossier backend
cd backend

# Installer les dépendances
npm install

# Copier et configurer l'environnement
cp .env.example .env
# Modifier .env si nécessaire (IP, ports, secrets)

# Démarrer le backend
npm start

# Ou pour le développement avec auto-reload
npm run dev
```

Le backend sera disponible sur : `http://192.168.1.86:3000`

### 3. Lancer l'application Flutter

```bash
# Dans le dossier racine du projet
flutter pub get
flutter run
```

## 🔧 Configuration

### Modifier l'adresse IP

Si votre PC n'a pas l'IP `192.168.1.86`, modifiez ces fichiers :

#### Backend (.env)
```env
LIVEKIT_WS_URL=ws://VOTRE_IP:7880
```

#### Flutter (token_service.dart)
```dart
static const String _baseUrl = 'http://VOTRE_IP:3000';
```

#### LiveKit (livekit.yaml)
```yaml
turn:
  domain: "VOTRE_IP"
```

### Configuration réseau

Assurez-vous que les ports suivants sont accessibles :
- **3000**: Backend Node.js
- **7880**: LiveKit WebSocket
- **7881**: LiveKit RTC/UDP
- **50000-50100**: Ports RTC pour WebRTC

## 📱 Test avec plusieurs téléphones

### Étape 1: Préparer l'environnement

1. **Démarrez tous les services** (voir section Installation)
2. **Vérifiez la connectivité réseau** :
   ```bash
   # Test backend depuis un téléphone
   curl http://192.168.1.86:3000/health
   ```

### Étape 2: Installer l'app sur les téléphones

1. **Compilez l'APK** :
   ```bash
   flutter build apk --release
   ```

2. **Installez sur les téléphones** :
   - Copiez `build/app/outputs/flutter-apk/app-release.apk`
   - Installez sur chaque téléphone Android

### Étape 3: Test de l'intercom

1. **Ouvrez l'app** sur chaque téléphone
2. **Allez sur l'onglet "Intercom"**
3. **L'app se connecte automatiquement** à la room `omega-intercom`
4. **Parlez dans un téléphone** → les autres entendent en temps réel
5. **Vérifiez le full-duplex** : plusieurs personnes peuvent parler simultanément

### Troubleshooting du test

| Problème | Solution |
|----------|----------|
| "Backend non accessible" | Vérifiez que le backend Node.js est démarré et accessible sur le réseau |
| "Erreur de connexion LiveKit" | Vérifiez que le serveur LiveKit est actif avec `docker-compose ps` |
| "Permission microphone refusée" | Accordez la permission microphone dans les paramètres Android |
| Pas d'audio | Vérifiez que le microphone est activé (bouton "Micro ON") |
| Latence élevée | Vérifiez la qualité du réseau WiFi |

## 🎯 Fonctionnalités

### Intercom temps réel
- ✅ **Full-duplex** : Conversation simultanée dans les deux sens
- ✅ **Multi-participants** : Jusqu'à 10 téléphones simultanément  
- ✅ **Auto-connexion** : Se connecte automatiquement au démarrage
- ✅ **Reconnexion automatique** : En cas de perte de connexion
- ✅ **Qualité audio optimisée** : Echo cancellation, noise suppression

### Interface utilisateur
- ✅ **État de connexion** : Indicateur visuel temps réel
- ✅ **Liste des participants** : Voir qui est connecté
- ✅ **Contrôle microphone** : Activer/désactiver facilement
- ✅ **Messages de statut** : Log détaillé des événements

### GPS (existant)
- ✅ **Carte Google Maps**
- ✅ **Localisation temps réel**
- ✅ **Navigation**

## 🔍 Monitoring et débogage

### Vérifier les services

```bash
# Statut des conteneurs
docker-compose ps

# Logs LiveKit
docker logs omega-livekit-server

# Logs Redis  
docker logs omega-redis

# Logs Backend
cd backend && npm start
```

### API Backend

```bash
# Santé du backend
curl http://192.168.1.86:3000/health

# Générer un token de test
curl -X POST http://192.168.1.86:3000/api/token \
  -H "Content-Type: application/json" \
  -d '{"roomName":"omega-intercom","participantName":"TestUser"}'

# Informations de connexion
curl http://192.168.1.86:3000/api/connection-info
```

### Debug Flutter

```bash
# Logs détaillés Flutter
flutter run --verbose

# Analyser le code
flutter analyze
```

## 📂 Structure du projet

```
OMEGA_Intercom/
├── lib/
│   ├── main.dart                    # Point d'entrée de l'app
│   ├── screens/
│   │   ├── gps_screen.dart         # Écran GPS (existant)
│   │   └── intercom_page.dart      # Écran intercom LiveKit
│   └── services/
│       └── token_service.dart      # Service d'authentification
├── backend/
│   ├── package.json               # Dépendances Node.js
│   ├── .env                       # Configuration (à créer)
│   ├── .env.example              # Template de configuration
│   └── index.js                  # Serveur Express + génération tokens
├── docker-compose.yml            # Configuration Docker
├── livekit.yaml                  # Configuration serveur LiveKit
└── README.md                     # Ce fichier
```

## 🔐 Sécurité

### En développement
- Clés API et secrets en dur dans les fichiers (⚠️ pour dev uniquement)
- Pas de HTTPS (⚠️ pour dev uniquement)
- Tokens avec TTL de 24h

### Pour la production
- [ ] Changez tous les secrets dans `livekit.yaml` et `.env`
- [ ] Configurez HTTPS avec certificats SSL
- [ ] Utilisez des variables d'environnement sécurisées
- [ ] Implémentez l'authentification utilisateur
- [ ] Réduisez le TTL des tokens (ex: 1h)

## 🆘 Support

### Logs utiles
- **Flutter**: Messages de statut dans l'interface
- **Backend**: Console Node.js 
- **LiveKit**: `docker logs omega-livekit-server`
- **Redis**: `docker logs omega-redis`

### Problèmes courants

**"Backend non accessible"**
```bash
# Vérifier si le backend répond
curl http://192.168.1.86:3000/health
# Si pas de réponse, redémarrer :
cd backend && npm start
```

**"Permission microphone refusée"**  
→ Aller dans Paramètres Android > Apps > OMEGA GPS > Permissions > Microphone

**"Erreur de connexion LiveKit"**
```bash
# Vérifier les conteneurs
docker-compose ps
# Si arrêtés, redémarrer :
docker-compose up -d
```

## 📋 TODO / Améliorations futures

- [ ] Interface web d'administration LiveKit
- [ ] Enregistrement des conversations
- [ ] Salles multiples (différents groupes)
- [ ] Push-to-talk optionnel
- [ ] Indicateurs de niveau audio
- [ ] Support iOS natif
- [ ] Chiffrement end-to-end
- [ ] Authentification utilisateur

---

**🎉 Votre système d'intercom temps réel est prêt ! Testez avec plusieurs téléphones pour une expérience complète.**