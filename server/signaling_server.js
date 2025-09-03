// signaling_server.js
// Simple WebSocket signaling server for WebRTC
const WebSocket = require('ws');

const wss = new WebSocket.Server({ port: 8080 });

// Map to store clients: clientId -> { ws, name }
const clients = new Map();

function broadcast(message, senderId) {
  for (const [id, client] of clients.entries()) {
    if (id !== senderId && client.ws.readyState === WebSocket.OPEN) {
      client.ws.send(JSON.stringify(message));
    }
  }
}

wss.on('connection', (ws) => {
  console.log('Client connected');

  // 1. Generate ID and get list of existing peers
  const clientId = Date.now().toString();
  const existingPeers = [];
  for (const [id, client] of clients.entries()) {
    existingPeers.push({ id, name: client.name });
  }

  // 2. Send welcome message to the new client
  ws.send(JSON.stringify({
    type: 'welcome',
    id: clientId,
    peers: existingPeers,
  }));

  // 3. Add the new client to the map (without a name yet)
  clients.set(clientId, { ws, name: 'Anonymous' });

  ws.on('message', (message) => {
    let data;
    try {
      data = JSON.parse(message);
    } catch (e) {
      console.error('Invalid JSON', message);
      return;
    }

    const { type, to, from, sdp, candidate, name } = data;
    const fromClient = clients.get(from);

    console.log(`Received: ${type} from ${from} to ${to || 'all'}`);

    switch (type) {
      // 4. When a client announces itself, store its name and notify others
      case 'announce':
        if (fromClient) {
          fromClient.name = name;
          broadcast({ type: 'peer-joined', id: from, name }, from);
        }
        break;

      // Relay messages to specific clients
      case 'offer':
      case 'answer':
      case 'candidate':
        const targetClient = clients.get(to);
        if (targetClient && targetClient.ws.readyState === WebSocket.OPEN) {
          targetClient.ws.send(JSON.stringify({ type, from, sdp, candidate }));
        }
        break;

      default:
        console.log(`Unknown message type: ${type}`);
    }
  });

  ws.on('close', () => {
    console.log('Client disconnected');
    clients.delete(clientId);
    broadcast({ type: 'peer-left', id: clientId }, null);
  });

  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
    clients.delete(clientId);
    broadcast({ type: 'peer-left', id: clientId }, null);
  });
});

console.log('Signaling server started on ws://localhost:8080');