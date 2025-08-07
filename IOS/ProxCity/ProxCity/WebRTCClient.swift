#if os(iOS)
import AVFoundation
#endif
import Foundation
import WebRTC

class WebRTCClient: NSObject {
    private var peerConnection: RTCPeerConnection?
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
        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)

        let audioSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        audioTrack = factory.audioTrack(with: audioSource, trackId: "ARDAMSa0")
        if let track = audioTrack {
            peerConnection?.add(track, streamIds: ["ARDAMS"])
        }
    }

    func offer() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"], optionalConstraints: nil)
        print("➡️ WebRTCClient: Creating OFFER")
        peerConnection?.offer(for: constraints) { [weak self] sdp, error in
            guard let sdp = sdp else { return }
            self?.peerConnection?.setLocalDescription(sdp, completionHandler: { _ in })
            self?.delegate?(["type": "offer", "sdp": sdp.sdp])
        }
    }

    func answer() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"], optionalConstraints: nil)
        print("⬅️ WebRTCClient: Creating ANSWER")
        peerConnection?.answer(for: constraints) { [weak self] sdp, error in
            guard let sdp = sdp else { return }
            self?.peerConnection?.setLocalDescription(sdp, completionHandler: { _ in })
            self?.delegate?(["type": "answer", "sdp": sdp.sdp])
        }
    }

    func set(remoteSdp type: String, sdp: String) {
        let sdpType: RTCSdpType = (type == "offer") ? .offer : .answer
        let sessionDescription = RTCSessionDescription(type: sdpType, sdp: sdp)
        peerConnection?.setRemoteDescription(sessionDescription, completionHandler: { _ in })
        print("✅ WebRTCClient: set remote SDP of type \(type)")
    }

    func add(iceCandidate: [String: Any]) {
        guard let sdp = iceCandidate["candidate"] as? String,
              let sdpMLineIndex = iceCandidate["sdpMLineIndex"] as? Int32,
              let sdpMid = iceCandidate["sdpMid"] as? String else { return }

        let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        peerConnection?.add(candidate)
    }
}

extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("🌐 ICE connection state changed to: \(newState)")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("🧩 ICE gathering state changed to: \(newState)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let candidateDict: [String: Any] = [
            "type": "candidate",
            "candidate": candidate.sdp,
            "sdpMLineIndex": candidate.sdpMLineIndex,
            "sdpMid": candidate.sdpMid ?? ""
        ]
        delegate?(candidateDict)
        onIceCandidate?(candidate)
        print("🧊 WebRTCClient: Generated ICE candidate: \(candidate.sdp)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}