import { WebSocketServer, WebSocket } from 'ws';
import http from 'http';
import crypto from 'crypto';

// sessionId -> ws
const sessions = new Map<string, WebSocket>();
// sessionId -> publicKey
const keyBySession = new Map<string, string>();
// publicKey -> set(sessionId)
const sessionsByKey = new Map<string, Set<string>>();

function removeSession(sessionId: string | undefined, publicKey?: string, opts: { notify?: boolean } = {}) {
  const { notify = true } = opts;
  if (!sessionId) return;
  // Remove from primary maps
  sessions.delete(sessionId);
  keyBySession.delete(sessionId);
  if (publicKey) {
    const set = sessionsByKey.get(publicKey);
    if (set) {
      set.delete(sessionId);
      if (set.size === 0) sessionsByKey.delete(publicKey);
    }
    if (notify) {
      broadcastExceptPublicKey(publicKey, { type: 'LEAVE', publicKey, sessionId });
    }
  }
}

function send(ws: WebSocket, msg: any) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
}
function broadcastExceptPublicKey(senderKey: string | null, msg: any) {
  const data = JSON.stringify(msg);
  for (const [sid, ws] of sessions.entries()) {
    const pk = keyBySession.get(sid);
    if (pk && pk !== senderKey && ws.readyState === ws.OPEN) {
      ws.send(data);
    }
  }
}

const server = http.createServer((_, res) => {
  res.writeHead(200);
  res.end('Signaling server is running');
});

const wss = new WebSocketServer({ server });

// Server-driven heartbeat using timestamps so we can drop multiple dead sockets together
const HEARTBEAT_INTERVAL_MS = 5000; // 5s ping cadence
const DEAD_TIMEOUT_MS = 12000;      // consider dead if no pong for >12s
const heartbeat = setInterval(() => {
  const now = Date.now();
  for (const [sid, ws] of sessions.entries()) {
    const pk = keyBySession.get(sid);
    const lastPongAt = (ws as any).lastPongAt ?? 0;
    const lastPingAt = (ws as any).lastPingAt ?? 0;

    // 1) Reap dead connections in this same tick if they exceeded timeout
    if (now - lastPongAt > DEAD_TIMEOUT_MS) {
      try { ws.terminate(); } catch {}
      removeSession(sid, pk, { notify: true });
      console.log('💀 Terminated unresponsive session:', pk, `(${sid})`);
      continue;
    }

    // 2) Send ping if due
    if (now - lastPingAt >= HEARTBEAT_INTERVAL_MS) {
      try {
        ws.ping();
        (ws as any).lastPingAt = now;
      } catch {}
    }
  }
}, HEARTBEAT_INTERVAL_MS);

wss.on('close', () => clearInterval(heartbeat));

wss.on('connection', (ws: WebSocket) => {
  console.log('Client connected');
  // Heartbeat timestamps: record lastPongAt and lastPingAt
  (ws as any).lastPongAt = Date.now();
  (ws as any).lastPingAt = 0;
  ws.on('pong', () => { (ws as any).lastPongAt = Date.now(); });

  ws.on('message', (raw: string) => {
    let data: any;
    try {
      data = JSON.parse(raw.toString());
    } catch (e) {
      console.error('Invalid JSON', e);
      return;
    }

    // JOIN — register a session for this publicKey
    if (data.type === 'JOIN' && typeof data.publicKey === 'string') {
      const publicKey: string = data.publicKey;
      const sessionId = crypto.randomUUID();
      (ws as any).sessionId = sessionId;
      (ws as any).publicKey = publicKey;

      sessions.set(sessionId, ws);
      keyBySession.set(sessionId, publicKey);
      let set = sessionsByKey.get(publicKey);
      if (!set) {
        set = new Set();
        sessionsByKey.set(publicKey, set);
      }
      set.add(sessionId);

      console.log(`User joined: ${publicKey} (session ${sessionId})`);

      // 1) Send roster of unique publicKeys to the joiner
      const uniquePeers = Array.from(sessionsByKey.keys()).filter(k => k !== publicKey);
      send(ws, { type: 'PEERS', peers: uniquePeers });

      // 2) Broadcast JOIN (with sessionId) to everyone else
      broadcastExceptPublicKey(publicKey, { type: 'JOIN', publicKey, sessionId });
      return;
    }

    // LIST — reply with unique publicKeys
    if (data.type === 'LIST') {
      const me: string | undefined = (ws as any).publicKey;
      const uniquePeers = Array.from(sessionsByKey.keys()).filter(k => k !== me);
      send(ws, { type: 'PEERS', peers: uniquePeers });
      return;
    }

    // SIGNAL — forward by toSessionId or toPublicKey (fallback)
    if (data.type === 'SIGNAL') {
      const toKey: string | undefined = data.toPublicKey || data.to;
      const toSessionId: string | undefined = data.toSessionId;

      if (toSessionId) {
        const target = sessions.get(toSessionId);
        if (target) send(target, data);
      } else if (toKey) {
        const set = sessionsByKey.get(toKey);
        if (set) {
          for (const sid of set) {
            const ws2 = sessions.get(sid);
            if (ws2) send(ws2, data);
          }
        }
      }
      return;
    }

    if (data.type === 'LEAVE') {
      const sid: string | undefined = (ws as any).sessionId;
      const pk: string | undefined = (ws as any).publicKey;
      removeSession(sid, pk, { notify: true });
      console.log(`User left via LEAVE: ${pk} (${sid})`);
      return;
    }

    // TRUST — (placeholder)
    if (data.type === 'TRUST' && data.to && data.signature) {
      console.log(`Trust declaration from ${(ws as any).publicKey} to ${data.to}`);
      return;
    }
  });

  ws.on('close', () => {
    const sid: string | undefined = (ws as any).sessionId;
    const pk: string | undefined = (ws as any).publicKey;
    removeSession(sid, pk, { notify: true });
    console.log('Client disconnected:', pk, `(${sid})`);
  });

  ws.on('error', (err) => {
    const sid: string | undefined = (ws as any).sessionId;
    const pk: string | undefined = (ws as any).publicKey;
    console.error('WebSocket error for session', pk, `(${sid})`, err);
    removeSession(sid, pk, { notify: true });
  });
});

server.listen(3000, '0.0.0.0', () => {
  console.log('Signaling server listening on ws://0.0.0.0:3000');
});