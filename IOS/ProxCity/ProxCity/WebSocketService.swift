import Foundation
import Starscream
import CoreLocation
import WebRTC

class WebSocketService: NSObject, ObservableObject, WebSocketDelegate, RTCPeerConnectionDelegate {
    // User’s key pair for identity
    let keyPair = KeyPairManager.shared
    // Discovered peers
    @Published var peers: [String] = []
    // Debug logs
    @Published var logs: [String] = []

    /// Append a log message (max 100)
    func log(_ message: String) {
        DispatchQueue.main.async {
            self.logs.append(message)
            if self.logs.count > 100 {
                self.logs.removeFirst()
            }
        }
    }
    // WebRTC client for signaling
    var webRTCClient: WebRTCClient? {
        didSet {
            webRTCClient?.onIceCandidate = { [weak self] candidate in
                guard let toKey = self?.answeringTo else { return }
                let candMsg: [String: Any] = [
                    "type": "SIGNAL",
                    "to": toKey,
                    "from": self?.keyPair.publicKey ?? "",
                    "signal": [
                        "type": "candidate",
                        "candidate": candidate.sdp,
                        "sdpMid": candidate.sdpMid ?? "",
                        "sdpMLineIndex": candidate.sdpMLineIndex
                    ]
                ]
                print("📤 Auto-sending ICE:", candMsg)
                self?.log("📤 Auto-sending ICE: \(candMsg)")
                self?.send(data: candMsg)
            }
            webRTCClient?.onLocalDescription = { [weak self] localDesc in
                guard let self = self else { return }
                let answerMsg: [String: Any] = [
                    "type": "SIGNAL",
                    "to": self.answeringTo ?? "",
                    "from": self.keyPair.publicKey,
                    "signal": ["type": "answer", "sdp": localDesc.sdp]
                ]
                print("📤 Auto-sending ANSWER:", answerMsg)
                self.log("📤 Auto-sending ANSWER: \(answerMsg)")
                self.send(data: answerMsg)
            }
        }
    }
    // Underlying WebSocket
    private var socket: WebSocket?
    // Store the peer we are answering to for ICE/answer sending
    private var answeringTo: String?

    func connect(location: CLLocation?) {
        var request = URLRequest(url: URL(string: "ws://192.168.1.188:3000")!)
        request.timeoutInterval = 5
        socket = WebSocket(request: request)
        socket?.delegate = self
        print("📡 Attempting connection to: \(request.url!)")
        self.log("📡 Attempting connection to: \(request.url!)")
        print("🧩 WebSocket delegate assigned")
        self.log("🧩 WebSocket delegate assigned")
        socket?.connect()
    }

    func send(data: [String: Any]) {
        guard let socket = socket else { return }
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                socket.write(string: jsonString)
            }
        } catch {
            print("Failed to serialize message: \(error)")
            self.log("Failed to serialize message: \(error)")
        }
    }

    // MARK: - WebSocketDelegate

    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected(let headers):
            print("✅ Connected with headers: \(headers)")
            self.log("✅ Connected with headers: \(headers)")
            let joinMsg: [String: Any] = [
                "type": "JOIN",
                "publicKey": keyPair.publicKey,
                "lat": 0.0,
                "lng": 0.0
            ]
            send(data: joinMsg)

        case .disconnected(let reason, let code):
            print("❌ Disconnected: \(reason) with code: \(code)")
            self.log("❌ Disconnected: \(reason) with code: \(code)")

        case .text(let string):
            handleText(string)

        case .binary(let data):
            print("📦 Received binary data: \(data.count) bytes")
            self.log("📦 Received binary data: \(data.count) bytes")

        case .error(let error):
            print("❗ Error: \(error?.localizedDescription ?? "Unknown error")")
            self.log("❗ Error: \(error?.localizedDescription ?? "Unknown error")")

        case .cancelled:
            print("❌ Connection cancelled")
            self.log("❌ Connection cancelled")

        default:
            print("🔄 Event: \(event)")
            self.log("🔄 Event: \(event)")
        }
    }

    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msgType = json["type"] as? String else {
            print("📨 Received text (unparsable): \(text)")
            self.log("📨 Received text (unparsable): \(text)")
            return
        }

        switch msgType {
        case "JOIN":
            if let key = json["publicKey"] as? String,
               key != keyPair.publicKey,
               !peers.contains(key) {
                peers.append(key)
                print("➕ New peer discovered: \(key)")
                self.log("➕ New peer discovered: \(key)")
            }

        case "SIGNAL":
            guard let signal = json["signal"] as? [String: Any],
                  let signalType = signal["type"] as? String,
                  let fromKey = json["from"] as? String else {
                return
            }
            handleSignal(type: signalType, signal: signal, fromKey: fromKey)

        case "TRUST":
            if let to = json["to"] as? String, let sig = json["signature"] as? String {
                print("Trust declaration from \(keyPair.publicKey) to \(to): \(sig)")
                self.log("Trust declaration from \(keyPair.publicKey) to \(to): \(sig)")
            }

        default:
            print("📨 Received text: \(text)")
            self.log("📨 Received text: \(text)")
        }
    }

    private func handleSignal(type signalType: String, signal: [String: Any], fromKey: String) {
        switch signalType {
        case "offer":
            webRTCClient?.set(remoteSdp: "offer", sdp: signal["sdp"] as! String)
            self.log("⬅️ Received offer from \(fromKey)")
            webRTCClient?.answer()
            answeringTo = fromKey
            // Send answer using closure when localDescription is set
            // ICE candidates will be forwarded via delegate

        case "answer":
            webRTCClient?.set(remoteSdp: "answer", sdp: signal["sdp"] as! String)
            self.log("⬅️ Received answer from \(fromKey)")

        case "candidate":
            webRTCClient?.add(iceCandidate: signal)
            self.log("⬅️ Received ICE candidate from \(fromKey): \(signal)")

        default:
            print("⚠️ Unknown signal type: \(signalType)")
            self.log("⚠️ Unknown signal type: \(signalType)")
        }
    }

    // MARK: - RTCPeerConnectionDelegate

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        // This method is no longer used for sending ICE candidates
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
