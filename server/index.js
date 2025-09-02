// Simple UDP audio relay (hub) for Omega Intercom
// - Listens on UDP port (default 55667)
// - Tracks senders by remote address:port
// - Forwards each incoming packet to all other known peers (excludes sender)
// - Broadcasts peer count via control datagrams: "ICSV1|PEERS|<n>"
// - Does not modify audio payload (client mix-minus via header)

const dgram = require('dgram');

// Args
const args = process.argv.slice(2);
let PORT = 55667;
let HOST = '0.0.0.0';
let VERBOSE = false;
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--port' && args[i + 1]) PORT = parseInt(args[++i], 10) || PORT;
  else if (a === '--host' && args[i + 1]) HOST = args[++i];
  else if (a === '--verbose') VERBOSE = true;
}

const socket = dgram.createSocket('udp4');

// Peers map: key -> { address, port, lastSeen }
const peers = new Map();
const PEER_TTL_MS = 15000; // 15s inactivity = purge

function keyOf(rinfo) {
  return `${rinfo.address}:${rinfo.port}`;
}

function log(...parts) {
  if (VERBOSE) console.log('[srv]', ...parts);
}

socket.on('listening', () => {
  const addr = socket.address();
  console.log(`Omega Intercom UDP relay listening on ${addr.address}:${addr.port}`);
});

socket.on('message', (msg, rinfo) => {
  const key = keyOf(rinfo);
  // Update sender last seen
  const isNew = !peers.has(key);
  const entry = peers.get(key) || { address: rinfo.address, port: rinfo.port };
  entry.lastSeen = Date.now();
  peers.set(key, entry);
  if (isNew) {
    // Notify all peers about count change
    broadcastPeerCount();
  }

  // Presence control messages
  try {
    if (msg.length >= 6 && msg[0] === 0x49 && msg[1] === 0x43) {
      const txt = msg.toString('utf8');
      if (txt.startsWith('ICSV1|PRES|')) {
        const parts = txt.split('|');
        entry.id = parts[2] || '';
        entry.name = (parts.slice(3).join('|')) || '';
        // rebroadcast as-is
        for (const p of peers.values()) {
          try { socket.send(msg, p.port, p.address); } catch (_) {}
        }
        return;
      }
    }
  } catch (_) {}

  // Forward to all others
  let fanout = 0;
  for (const [k, p] of peers.entries()) {
    if (k === key) continue; // exclude sender
    try {
      socket.send(msg, p.port, p.address);
      fanout++;
    } catch (e) {
      log('send error to', p.address, p.port, e.message);
    }
  }
  log('rx', msg.length, 'bytes from', key, '→', fanout, 'peers');
});

socket.on('error', (err) => {
  console.error('UDP server error:', err);
});

// Periodic purge of stale peers
setInterval(() => {
  const now = Date.now();
  let removed = 0;
  for (const [k, p] of peers.entries()) {
    if (now - p.lastSeen > PEER_TTL_MS) {
      if (p.id) {
        const gone = Buffer.from(`ICSV1|GONE|${p.id}`);
        for (const v of peers.values()) {
          try { socket.send(gone, v.port, v.address); } catch (_) {}
        }
      }
      peers.delete(k);
      removed++;
    }
  }
  if (removed > 0) {
    if (VERBOSE) console.log('[srv] purged', removed, 'stale peers, left =', peers.size);
    broadcastPeerCount();
  }
}, 5000).unref();

socket.bind(PORT, HOST);

function broadcastPeerCount() {
  const n = peers.size;
  const payload = Buffer.from(`ICSV1|PEERS|${n}`);
  for (const p of peers.values()) {
    try { socket.send(payload, p.port, p.address); } catch (e) { /* ignore */ }
  }
}
