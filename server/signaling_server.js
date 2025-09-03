// signaling_server.js
// Simple WebSocket signaling server for WebRTC
const WebSocket = require('ws');
const os = require('os');

const PORT = 55667;
const wss = new WebSocket.Server({ port: PORT });

// Map to store clients: clientId -> { ws, name }
const clients = new Map();

function getLocalIpAddresses() {
    const interfaces = os.networkInterfaces();
    const addresses = [];
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if (iface.family === 'IPv4' && !iface.internal) {
                addresses.push(iface.address);
            }
        }
    }
    return addresses;
}

function broadcast(message, senderId) {
  for (const [id, client] of clients.entries()) {
    if (id !== senderId && client.ws.readyState === WebSocket.OPEN) {
      client.ws.send(JSON.stringify(message));
    }
  }
}

wss.on('connection', (ws) => {
  const clientId = Date.now().toString();
  console.log(`[SERVER] New client connected. Assigning ID: ${clientId}`);

  const existingPeers = [];
  for (const [id, client] of clients.entries()) {
    existingPeers.push({ id, name: client.name });
  }

  ws.send(JSON.stringify({
    type: 'welcome',
    id: clientId,
    peers: existingPeers,
  }));

  clients.set(clientId, { ws, name: 'Anonymous' });

  ws.on('message', (message) => {
    let data;
    try {
      data = JSON.parse(message);
    } catch (e) {
      console.error('[ERROR] Invalid JSON received:', message);
      return;
    }

    const { type, to, from, sdp, candidate, name } = data;
    const fromClient = clients.get(from);

    console.log(`[SIGNAL] Received: ${type} from ${from || 'new client'} to ${to || 'all'}`);

    switch (type) {
      case 'announce':
        if (fromClient) {
          fromClient.name = name;
          console.log(`[SERVER] Client ${from} announced name: ${name}`);
          broadcast({ type: 'peer-joined', id: from, name }, from);
        }
        break;

      case 'offer':
      case 'answer':
        console.log(`[SIGNAL] Relaying ${type} from ${from} to ${to}`);
        const targetClient = clients.get(to);
        if (targetClient && targetClient.ws.readyState === WebSocket.OPEN) {
          targetClient.ws.send(JSON.stringify({ type, from, sdp, candidate }));
        } else {
          console.log(`[WARNING] Could not relay ${type}: Target client ${to} not found or connection not open.`);
        }
        break;
        
      case 'candidate':
        console.log(`[SIGNAL] Relaying ICE candidate from ${from} to ${to}`);
        const targetCandClient = clients.get(to);
        if (targetCandClient && targetCandClient.ws.readyState === WebSocket.OPEN) {
            targetCandClient.ws.send(JSON.stringify({ type, from, sdp, candidate }));
        } else {
            console.log(`[WARNING] Could not relay candidate: Target client ${to} not found or connection not open.`);
        }
        break;

      default:
        console.log(`[INFO] Unknown message type: ${type}`);
    }
  });

  ws.on('close', () => {
    console.log(`[SERVER] Client ${clientId} disconnected.`);
    clients.delete(clientId);
    broadcast({ type: 'peer-left', id: clientId }, null);
  });

  ws.on('error', (error) => {
    console.error(`[ERROR] WebSocket error for client ${clientId}:`, error);
    clients.delete(clientId);
    broadcast({ type: 'peer-left', id: clientId }, null);
  });
});

const localIPs = getLocalIpAddresses();
console.log('-----------------------------------');
console.log(`Signaling server started on port ${PORT}`);
console.log('Accessible on this machine at:');
console.log(`  - ws://localhost:${PORT}`);
if (localIPs.length > 0) {
    localIPs.forEach(ip => {
        console.log(`  - ws://${ip}:${PORT} (for LAN)`);
    });
}
console.log(`  - ws://93.1.78.21:${PORT} (for Internet)`);
console.log('-----------------------------------');
console.log('Waiting for clients to connect...');
