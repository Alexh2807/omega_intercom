Omega Intercom UDP Relay (Node.js)

Usage

- Install Node.js >= 14
- In the `server` folder:
  - `npm start` (defaults to `0.0.0.0:55667`)
  - or `node index.js --port 55667 --host 0.0.0.0 --verbose`

What it does

- Listens for UDP packets (PCM16 mono 16k encapsulated with a small header)
- Tracks peers by their UDP source address:port
- For each incoming packet, forwards it to all other peers (excludes the sender)
- Does not modify payload; client mix-minus is handled in the Flutter app

Flutter settings

- In the app, set mode to Internet and host to the machine running this relay (public IP or LAN IP if reachable)
- Keep default port `55667` or change it on both sides

Notes

- The relay purges peers inactive for 15 seconds
- This is not encrypted/authenticated; deploy behind a VPN or trusted network if needed

