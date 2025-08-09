import { WebSocketServer, WebSocket } from 'ws';
import http from 'http';
import crypto from 'crypto';

// sessionId -> ws
const sessions = new Map<string, WebSocket>();
// sessionId -> publicKey
const keyBySession = new Map<string, string>();
// publicKey -> set(sessionId)
const sessionsByKey = new Map<string, Set<string>>();

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

wss.on('connection', (ws: WebSocket) => {
  console.log('Client connected');

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

    // LEAVE — remove only this socket’s session
    if (data.type === 'LEAVE') {
      const sid: string | undefined = (ws as any).sessionId;
      const pk: string | undefined = (ws as any).publicKey;
      if (sid && pk) {
        sessions.delete(sid);
        keyBySession.delete(sid);
        const set = sessionsByKey.get(pk);
        if (set) {
          set.delete(sid);
          if (set.size === 0) sessionsByKey.delete(pk);
        }
        broadcastExceptPublicKey(pk, { type: 'LEAVE', publicKey: pk, sessionId: sid });
        console.log(`User left via LEAVE: ${pk} (${sid})`);
      }
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
    if (!sid || !pk) return;
    sessions.delete(sid);
    keyBySession.delete(sid);
    const set = sessionsByKey.get(pk);
    if (set) {
      set.delete(sid);
      if (set.size === 0) sessionsByKey.delete(pk);
    }
    broadcastExceptPublicKey(pk, { type: 'LEAVE', publicKey: pk, sessionId: sid });
    console.log('Client disconnected:', pk, `(${sid})`);
  });
});

server.listen(3000, '0.0.0.0', () => {
  console.log('Signaling server listening on ws://0.0.0.0:3000');
});