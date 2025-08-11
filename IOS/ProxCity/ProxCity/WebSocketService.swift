import Foundation
import Starscream
import CoreLocation
import WebRTC
import CryptoKit
import Combine

private struct KeyPair {
    let privateKey: Curve25519.KeyAgreement.PrivateKey
    let publicKey: String
}

class WebSocketService: NSObject, ObservableObject, WebSocketDelegate, RTCPeerConnectionDelegate {
    @Published var isSocketConnected: Bool = false
    @Published var connectedPeers: Set<String> = []
    @Published var peers: [String] = []
    @Published var logs: [String] = []
    @Published var isReceivingAudio: Bool = false
    @Published var isSpeaking: Bool = false

    // Buffer ICE candidates that arrive before remoteDescription is set
    private var pendingCandidates: [[String: Any]] = []
    private var cancellables = Set<AnyCancellable>()

    // Expose public key safely for UI without touching keyPair directly
    var publicKey: String { keyPair.publicKey }
    
    // Expose speaker switching functionality
    @MainActor
    var isUsingMainSpeaker: Bool {
        get { webRTCClient?.isUsingMainSpeaker ?? true }
        set { webRTCClient?.isUsingMainSpeaker = newValue }
    }
    
    @MainActor
    func toggleSpeaker() {
        webRTCClient?.toggleSpeaker()
        log("🔊 Speaker toggled to: \(isUsingMainSpeaker ? "Main Speaker" : "Earpiece")")
    }

    private let keyPair: KeyPair

    override init() {
        self.keyPair = WebSocketService.loadOrGenerateKeyPair()
        super.init()
        if ProcessInfo.processInfo.environment["EPHEMERAL_KEYS"] == "1" {
            self.log("🔑 Using EPHEMERAL key for this session: \(self.keyPair.publicKey.prefix(24))…")
        } else {
            self.log("🔑 Using PERSISTENT key: \(self.keyPair.publicKey.prefix(24))…")
        }
    }

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
            setupWebRTCClientHandlers()
        }
    }
    private func setupWebRTCClientHandlers() {
        Task { @MainActor in
            webRTCClient?.onIceCandidate = { [weak self] candidate in
                guard let toKey = self?.answeringTo else { return }
                let candMsg: [String: Any] = [
                    "type": "SIGNAL",
                    "toPublicKey": toKey,
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
                    "toPublicKey": self.answeringTo ?? "",
                    "from": self.keyPair.publicKey,
                    "signal": ["type": "answer", "sdp": localDesc.sdp]
                ]
                print("📤 Auto-sending ANSWER:", answerMsg)
                self.log("📤 Auto-sending ANSWER: \(answerMsg)")
                self.send(data: answerMsg)
            }
            webRTCClient?.onRemoteDescription = { [weak self] in
                guard let self = self else { return }
                // Drain pending candidates
                for candidate in self.pendingCandidates {
                    self.webRTCClient?.add(iceCandidate: candidate)
                    self.log("📍 Draining buffered ICE candidate: \(candidate)")
                }
                self.pendingCandidates.removeAll()
            }
            webRTCClient?.onICEConnectionStateChange = { [weak self] state in
                guard let self = self else { return }
                self.log("🌐 ICE state: \(state)")
                switch state {
                case .connected, .completed:
                    if let key = self.answeringTo {
                        DispatchQueue.main.async {
                            self.connectedPeers.insert(key)
                        }
                    }
                case .disconnected, .failed, .closed:
                    if let key = self.answeringTo {
                        DispatchQueue.main.async {
                            self.connectedPeers.remove(key)
                        }
                    }
                default:
                    break
                }
            }
            webRTCClient?.onReceivingChanged = { [weak self] value in
                DispatchQueue.main.async { self?.isReceivingAudio = value }
            }
            webRTCClient?.onSpeakingChanged = { [weak self] value in
                DispatchQueue.main.async { self?.isSpeaking = value }
            }
            // Forward speaker state changes
            webRTCClient?.objectWillChange.sink { [weak self] in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }.store(in: &cancellables)
            // Forward SDP offers/answers produced by WebRTCClient
            self.webRTCClient?.delegate = { [weak self] payload in
                guard let self = self else { return }
                guard let type = payload["type"] as? String else { return }
                let toKey = self.answeringTo ?? ""
                if toKey.isEmpty { self.log("⚠️ delegate payload has no target"); return }
                let msg: [String: Any] = [
                    "type": "SIGNAL",
                    "toPublicKey": toKey,
                    "from": self.keyPair.publicKey,
                    "signal": payload
                ]
                self.log("📤 Sending \(type.uppercased()) to=\(toKey)")
                self.send(data: msg)
            }
        }
    }
    // Underlying WebSocket
    private var socket: WebSocket?
    // Store the peer we are answering to for ICE/answer sending
    private var answeringTo: String?
    /// Start an outgoing call to a peer (fresh RTCPeerConnection and proper state)
    @MainActor
    func startCall(to targetKey: String) {
        // Tear down any existing PC to avoid stale state
        if let existing = self.webRTCClient { existing.close() }
        // Create fresh client and bind handlers
        self.webRTCClient = WebRTCClient()
        self.answeringTo = targetKey
        self.setupWebRTCClientHandlers()
        self.log("📞 Outgoing call: preparing offer to \(targetKey)")
        self.webRTCClient?.offer()
    }

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
                self.log("📤 Sent WebSocket message: \(jsonString)")
            }
        } catch {
            print("Failed to serialize message: \(error)")
            self.log("Failed to serialize message: \(error)")
        }
    }

    func disconnect() {
        let leaveMsg: [String: Any] = [
            "type": "LEAVE",
            "publicKey": keyPair.publicKey
        ]
        send(data: leaveMsg)
        if let to = answeringTo {
            let bye: [String: Any] = [
                "type": "HANGUP",
                "from": keyPair.publicKey,
                "toPublicKey": to
            ]
            send(data: bye)
        }
        socket?.disconnect()
        DispatchQueue.main.async {
            self.isSocketConnected = false
            self.connectedPeers.removeAll()
            self.logs.removeAll()
            self.peers.removeAll()
            self.answeringTo = nil
            self.isReceivingAudio = false
            self.isSpeaking = false
            self.pendingCandidates.removeAll()
        }
        Task { @MainActor in
            self.webRTCClient?.close()
        }
        webRTCClient = nil // Reset client on disconnect
        self.log("🔌 Disconnected and cleared state")
    }

    // MARK: - WebSocketDelegate

    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected(let headers):
            print("✅ Connected with headers: \(headers)")
            self.log("✅ Connected with headers: \(headers)")
            DispatchQueue.main.async { self.isSocketConnected = true }
            let joinMsg: [String: Any] = [
                "type": "JOIN",
                "publicKey": keyPair.publicKey,
                "lat": 0.0,
                "lng": 0.0
            ]
            send(data: joinMsg)
            // Request roster after joining, slight delay to ensure JOIN is processed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let listReq: [String: Any] = ["type": "LIST"]
                self.send(data: listReq)
                self.log("📥 Requested peer list (LIST)")
            }

        case .disconnected(let reason, let code):
            print("❌ Disconnected: \(reason) with code: \(code)")
            self.log("❌ Disconnected: \(reason) with code: \(code)")
            DispatchQueue.main.async { self.isSocketConnected = false }

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
            DispatchQueue.main.async { self.isSocketConnected = false }

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
        self.log("📨 Parsed incoming message type: \(msgType)")

        switch msgType {
        case "JOIN":
            if let key = json["publicKey"] as? String,
               key != keyPair.publicKey {
                DispatchQueue.main.async {
                    if !self.peers.contains(key) {
                        self.peers.append(key)
                        print("➕ New peer discovered: \(key)")
                        self.log("➕ New peer discovered: \(key)")
                    }
                }
            }

        case "LIST", "PEERS":
            if let arr = json["peers"] as? [String] {
                let filtered = arr.filter { $0 != self.keyPair.publicKey }
                DispatchQueue.main.async {
                    // replace the list with the server’s view to avoid stale entries
                    self.peers = filtered
                    self.log("📒 Updated peers from server list: \(filtered.count)")
                }
            } else {
                self.log("⚠️ LIST/PEERS message missing 'peers' array: \(json)")
            }

        case "SIGNAL":
            guard let signal = json["signal"] as? [String: Any],
                let signalType = signal["type"] as? String else { return }
            let fromKey = (json["from"] as? String) ?? (json["fromPublicKey"] as? String) ?? ""
            if fromKey.isEmpty { return }
            Task { @MainActor in
                self.handleSignal(type: signalType, signal: signal, fromKey: fromKey)
            }

        case "LEAVE":
            if let key = json["publicKey"] as? String {
                DispatchQueue.main.async {
                    self.peers.removeAll(where: { $0 == key })
                    if self.connectedPeers.contains(key) || self.answeringTo == key {
                        self.connectedPeers.remove(key)
                        self.log("🔌 Peer \(key) left — tearing down connection")
                        Task { @MainActor in
                            self.webRTCClient?.close()
                            self.webRTCClient = nil
                        }
                        self.answeringTo = nil
                        self.pendingCandidates.removeAll()
                        self.isReceivingAudio = false
                        self.isSpeaking = false
                    } else {
                        self.log("➖ Peer left: \(key)")
                    }
                }
                print("➖ Peer left: \(key)")
            }

        case "TRUST":
            if let to = json["to"] as? String, let sig = json["signature"] as? String {
                print("Trust declaration from \(keyPair.publicKey) to \(to): \(sig)")
                self.log("Trust declaration from \(keyPair.publicKey) to \(to): \(sig)")
            }

        case "HANGUP":
            if let from = json["from"] as? String {
                DispatchQueue.main.async {
                    self.connectedPeers.remove(from)
                }
                Task { @MainActor in
                    self.webRTCClient?.close()
                    self.webRTCClient = nil
                }
                self.answeringTo = nil
                self.pendingCandidates.removeAll()
                self.isReceivingAudio = false
                self.isSpeaking = false
                self.log("📴 Received HANGUP from \(from), tore down connection")
            }

        default:
            print("📨 Received text: \(text)")
            self.log("📨 Received text: \(text)")
        }
    }

    @MainActor
    private func handleSignal(type signalType: String, signal: [String: Any], fromKey: String) {
        self.log("🧩 Handling signal type: \(signalType)")
        switch signalType {
        case "offer":
            self.answeringTo = fromKey
            Task { @MainActor in
                // Always start clean to avoid stale state on reconnect
                if let existing = self.webRTCClient { existing.close() }
                self.webRTCClient = WebRTCClient()
                self.setupWebRTCClientHandlers()
                self.pendingCandidates.removeAll()
                self.webRTCClient?.set(remoteSdp: "offer", sdp: signal["sdp"] as! String)
                self.log("⬅️ Received offer from \(fromKey); applied remote SDP and creating answer")
                self.webRTCClient?.answer()
            }

        case "answer":
            if let sdp = signal["sdp"] as? String {
                print("📥 Received answer SDP")
                self.webRTCClient?.set(remoteSdp: "answer", sdp: sdp)
            } else {
                self.log("⚠️ ANSWER missing SDP payload")
            }
            self.answeringTo = fromKey
            self.log("⬅️ Received answer from \(fromKey)")

        case "candidate":
            // Buffer until remote description is applied (and even if client isn’t ready yet)
            if (self.webRTCClient?.rtcPeerConnection?.remoteDescription) == nil {
                self.pendingCandidates.append(signal)
                self.log("⏳ Buffering ICE candidate until remote SDP/client ready: \(signal)")
            } else {
                self.webRTCClient?.add(iceCandidate: signal)
                self.log("⬇️ Added ICE candidate immediately: \(signal)")
            }

        default:
            print("⚠️ Unknown signal type: \(signalType)")
            self.log("⚠️ Unknown signal type: \(signalType)")
        }
    }

    // MARK: - RTCPeerConnectionDelegate

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("🔊 peerConnection didAdd stream with \(stream.audioTracks.count) audio track(s)")
        if let remoteAudioTrack = stream.audioTracks.first {
            print("🔊 Playing audio from remote track: \(remoteAudioTrack.trackId)")
        }
        Task { @MainActor in
            self.webRTCClient?.isReceivingAudio = true
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor in
            self.webRTCClient?.onICEConnectionStateChange?(newState)
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        // This method is no longer used for sending ICE candidates
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    private static func loadOrGenerateKeyPair() -> KeyPair {
        // If EPHEMERAL_KEYS=1, generate a fresh, non-persisted key each run.
        let useEphemeral = ProcessInfo.processInfo.environment["EPHEMERAL_KEYS"] == "1"
        if useEphemeral {
            let priv = Curve25519.KeyAgreement.PrivateKey()
            let base = priv.publicKey.rawRepresentation.base64EncodedString()
            // Return only the base key (no session suffix)
            return KeyPair(privateKey: priv, publicKey: base)
        }

        // Persistent key (default path)
        let keyTag = "webrtc.privateKey"
        if let raw = UserDefaults.standard.data(forKey: keyTag),
           let priv = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) {
            let pubB64 = priv.publicKey.rawRepresentation.base64EncodedString()
            return KeyPair(privateKey: priv, publicKey: pubB64)
        }
        let priv = Curve25519.KeyAgreement.PrivateKey()
        UserDefaults.standard.set(priv.rawRepresentation, forKey: keyTag)
        let pubB64 = priv.publicKey.rawRepresentation.base64EncodedString()
        return KeyPair(privateKey: priv, publicKey: pubB64)
    }
}
