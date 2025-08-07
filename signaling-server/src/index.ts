import { WebSocketServer } from 'ws';
import http from 'http';
import { WebSocket } from 'ws';
import { log } from 'console';

const clients = new Map<string, WebSocket>();

const server = http.createServer((_, res) => {
  log('Connected.')
  res.writeHead(200);
  res.end("Signaling server is running");
});

const wss = new WebSocketServer({ server });

wss.on('connection', (ws: WebSocket) => {
  console.log("Client connected");

  ws.on('message', (message: string) => {
    try {
      const data = JSON.parse(message.toString());

      if (data.type === "JOIN" && typeof data.publicKey === "string") {
        const newKey = data.publicKey;
        clients.set(newKey, ws);
        (ws as any).publicKey = newKey;
        console.log(`User joined: ${newKey}`);

        // 1. Send all existing peers to the new client
        for (const existingKey of clients.keys()) {
          if (existingKey !== newKey) {
            ws.send(JSON.stringify({
              type: "JOIN",
              publicKey: existingKey
            }));
          }
        }

        // 2. Notify all other clients about the new client
        for (const [otherKey, otherWs] of clients.entries()) {
          if (otherKey !== newKey) {
            otherWs.send(JSON.stringify({
              type: "JOIN",
              publicKey: newKey
            }));
          }
        }
      }

      // SIGNAL handling
      if (data.type === "SIGNAL" &&
          data.signal && typeof data.signal === "object" &&
          typeof data.signal.type === "string" &&
          typeof data.from === "string") {
        const signalType = data.signal.type;
        const fromKey = data.from;

        switch (signalType) {
          case "offer":
            // Caller SENT an offer → Callee: set remote sdp, then answer
            // Configure delegate to send all subsequent signals back to the offerer
            // Create and send the answer (and its ICE candidates via delegate)
            // Since this is server side, just forward the offer to the callee
            const callee = clients.get(data.to);
            if (callee) {
              callee.send(JSON.stringify(data));
            }
            break;

          case "answer":
            // Caller receives answer → set remote sdp
            // Forward answer to the caller
            const caller = clients.get(data.to);
            if (caller) {
              caller.send(JSON.stringify(data));
            }
            break;

          case "candidate":
            // Add ICE candidate
            // Forward candidate to the target peer
            const target = clients.get(data.to);
            if (target) {
              target.send(JSON.stringify(data));
            }
            break;

          default:
            console.log(`⚠️ Unknown signal type: ${signalType}`);
        }
        return;
      }

      else if (data.type === "TRUST" && data.to && data.signature) {
        console.log(`Trust declaration from ${(ws as any).publicKey} to ${data.to}`);
      }

    } catch (err) {
      console.error("Invalid message", err);
    }
  });

  ws.on('close', () => {
    if ((ws as any).publicKey) {
      clients.delete((ws as any).publicKey);
      console.log(`Client disconnected: ${(ws as any).publicKey}`);
    }
  });
});

server.listen(3000, '0.0.0.0', () => {
  console.log("Signaling server listening on ws://0.0.0.0:3000");
});