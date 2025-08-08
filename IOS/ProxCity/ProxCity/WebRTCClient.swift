#if os(iOS)
import AVFoundation
#endif
import Foundation
import WebRTC
import Combine

@MainActor
class WebRTCClient: NSObject, ObservableObject {
    @Published var isConnected: Bool = false
    @Published var isReceivingAudio: Bool = false
    @Published var isSpeaking: Bool = false

    /// Callback invoked after setRemoteDescription completes
    var onRemoteDescription: (() -> Void)?
    
    public var rtcPeerConnection: RTCPeerConnection?
    private var factory: RTCPeerConnectionFactory
    private var audioTrack: RTCAudioTrack?
    var onIceCandidate: ((RTCIceCandidate) -> Void)?
    var delegate: (([String: Any]) -> Void)?
    var onLocalDescription: ((RTCSessionDescription) -> Void)?

    override init() {
        #if os(iOS)
        // Configure audio session for WebRTC
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setMode(.voiceChat)
            try session.setActive(true)
            print("🎤 AVAudioSession configured and activated")
        } catch {
            print("⚠️ Failed to configure AVAudioSession: \(error)")
        }
        #endif

        RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        super.init()
        self.setupPeerConnection()
    }

    private func setupPeerConnection() {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        rtcPeerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)
        // Always create and add the audio track
        if let audioTrack = createAudioTrack() {
            rtcPeerConnection?.add(audioTrack, streamIds: ["ARDAMS"])
            print("🎙️ Persistent audio track added during setup")
        }
        // States start false, so no changes here
    }

    func offer() {
        print("📞 Starting offer process...")
        let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"], optionalConstraints: nil)
        print("➡️ WebRTCClient: Creating OFFER")
        Task {
            do {
                let sdp = try await rtcPeerConnection?.offer(for: constraints)
                if let sdp = sdp {
                    try await rtcPeerConnection?.setLocalDescription(sdp)
                    self.onLocalDescription?(sdp)
                    DispatchQueue.main.async {
                        self.isSpeaking = true
                    }
                    self.delegate?(["type": "offer", "sdp": sdp.sdp])
                }
            } catch {
                print("⚠️ Failed to create or set offer SDP: \(error)")
            }
        }
    }

    func createAudioTrack() -> RTCAudioTrack? {
        let audioSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let track = factory.audioTrack(with: audioSource, trackId: "ARDAMSa0")
        track.isEnabled = false
        self.audioTrack = track
        return track
    }

    func answer() {
        print("📞 Starting answer process...")
        let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"], optionalConstraints: nil)
        print("⬅️ WebRTCClient: Creating ANSWER")
        Task {
            do {
                if let sdp = try await rtcPeerConnection?.answer(for: constraints) {
                    try await rtcPeerConnection?.setLocalDescription(sdp)
                    self.onLocalDescription?(sdp)
                    DispatchQueue.main.async {
                        self.isSpeaking = true
                    }
                    self.delegate?(["type": "answer", "sdp": sdp.sdp])
                }
            } catch {
                print("⚠️ Failed to create or set answer SDP: \(error)")
            }
        }
    }

    func set(remoteSdp type: String, sdp: String) {
        let sdpType: RTCSdpType = (type == "offer") ? .offer : .answer
        let sessionDescription = RTCSessionDescription(type: sdpType, sdp: sdp)
        Task { @MainActor in
            do {
                try await rtcPeerConnection?.setRemoteDescription(sessionDescription)
                print("✅ Remote description applied")
                self.onRemoteDescription?()
            } catch {
                print("⚠️ Failed to set remote description: \(error)")
            }
        }
        print("✅ WebRTCClient: set remote SDP of type \(type)")
    }

    func add(iceCandidate: [String: Any]) {
        guard let sdp = iceCandidate["candidate"] as? String,
              let sdpMLineIndex = iceCandidate["sdpMLineIndex"] as? Int32,
              let sdpMid = iceCandidate["sdpMid"] as? String else { return }

        let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        Task { @MainActor in
            do {
                try await rtcPeerConnection?.add(candidate)
                print("✅ Successfully added ICE candidate")
            } catch {
                print("⚠️ Failed to add ICE candidate: \(error)")
            }
        }
    }
    
    func close() {
        Task { @MainActor in
            rtcPeerConnection?.close()
        }
        DispatchQueue.main.async {
            self.isConnected = false
            self.isReceivingAudio = false
            self.isSpeaking = false
        }
    }
    
    /// Enable or disable the local microphone (push-to-talk)
    func setMicEnabled(_ enabled: Bool) {
        DispatchQueue.main.async {
            if let track = self.audioTrack {
                track.isEnabled = enabled
                print("🎙️ Microphone \(enabled ? "ENABLED" : "DISABLED")")
            } else {
                print("⚠️ setMicEnabled called but audioTrack is nil")
            }
            self.isSpeaking = enabled
        }
    }
}

extension WebRTCClient: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("🔊 Received remote stream with \(stream.audioTracks.count) audio track(s)")
        // Enable and play the first incoming audio track
        if let remoteAudioTrack = stream.audioTracks.first {
            remoteAudioTrack.isEnabled = true
            print("🔊 Playing audio from remote track")
            DispatchQueue.main.async {
                self.isReceivingAudio = true
            }
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async {
            self.isConnected = (newState == .connected || newState == .completed)
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("🧩 ICE gathering state changed to: \(newState)")
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let candidateDict: [String: Any] = [
            "type": "candidate",
            "candidate": candidate.sdp,
            "sdpMLineIndex": candidate.sdpMLineIndex,
            "sdpMid": candidate.sdpMid ?? ""
        ]
        Task { @MainActor in
            self.delegate?(candidateDict)
            self.onIceCandidate?(candidate)
        }
        print("🧊 WebRTCClient: Generated ICE candidate: \(candidate.sdp)")
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
