// udp_relay.js
// Petit serveur UDP pour relayer l'audio entre plusieurs clients
// - Chaque client envoie au serveur -> le serveur redistribue aux autres
// - Diffuse aussi le nombre de clients connectés via messages de contrôle "ICSV1|PEERS|<n>"

const dgram = require('dgram');
const server = dgram.createSocket('udp4');

// Clients { key -> { address, port, lastSeen } }
const clients = new Map();
const PEER_TTL_MS = 15000; // 15s sans trafic => purge

function keyOf(rinfo) { return `${rinfo.address}:${rinfo.port}`; }

function broadcastPeerCount() {
  const n = clients.size;
  const payload = Buffer.from(`ICSV1|PEERS|${n}`);
  for (const c of clients.values()) {
    server.send(payload, c.port, c.address, (err) => {
      if (err) console.error(`Erreur envoi count -> ${c.address}:${c.port}`, err);
    });
  }
}

server.on('listening', () => {
  const address = server.address();
  console.log(`✅ Serveur UDP en écoute sur ${address.address}:${address.port}`);
});

server.on('message', (msg, rinfo) => {
  const key = keyOf(rinfo);

  const isNew = !clients.has(key);
  clients.set(key, { address: rinfo.address, port: rinfo.port, lastSeen: Date.now() });
  if (isNew) {
    console.log(`➕ Nouveau client connecté : ${key}`);
    broadcastPeerCount();
  }

  // Relayer le message vers tous les autres clients
  for (const [k, c] of clients.entries()) {
    if (k === key) continue;
    server.send(msg, c.port, c.address, (err) => {
      if (err) console.error(`Erreur envoi vers ${k}:`, err);
    });
  }
});

// Purge périodique des clients inactifs
setInterval(() => {
  const now = Date.now();
  let removed = 0;
  for (const [k, c] of clients.entries()) {
    if (now - c.lastSeen > PEER_TTL_MS) {
      clients.delete(k);
      removed++;
    }
  }
  if (removed > 0) {
    console.log(`♻️ Purge ${removed} client(s) inactif(s). Clients actifs: ${clients.size}`);
    broadcastPeerCount();
  }
}, 5000).unref();

// Lancer le serveur sur le port 55667
server.bind(55667, () => {
  console.log("🚀 Serveur relay intercom lancé !");
});

