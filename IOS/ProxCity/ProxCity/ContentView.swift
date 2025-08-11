import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject var locationManager = LocationManager()
    @StateObject var socketService = WebSocketService()
    @State private var selectedPeer: String? = nil

    var body: some View {
        VStack(spacing: 20) {
            Text("ProxCity Chat")
                .font(.largeTitle)

            Button(socketService.isSocketConnected ? "Disconnect" : "Connect") {
                if socketService.isSocketConnected {
                    socketService.disconnect()
                } else {
                    selectedPeer = nil
                    socketService.connect(location: locationManager.currentLocation)
                }
            }

            Button("Call Peer") {
                guard let target = selectedPeer,
                    !(selectedPeer.flatMap { socketService.connectedPeers.contains($0) } ?? false) else { return }
                Task { @MainActor in
                    socketService.startCall(to: target)
                }
            }
            .disabled(
                selectedPeer == nil ||
                (selectedPeer.flatMap { socketService.connectedPeers.contains($0) } ?? false)
            )

            List(socketService.peers, id: \.self) { peer in
                HStack {
                    Circle()
                        .fill(socketService.connectedPeers.contains(peer) ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    Text(peer)
                    Spacer()
                    if selectedPeer == peer {
                        Image(systemName: "checkmark")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPeer = peer
                }
            }
            .frame(height: 200)

            if let loc = locationManager.currentLocation {
                Text("📍 \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
                    .font(.footnote)
            }

            HStack(spacing: 16) {
                Circle().fill(socketService.isReceivingAudio ? Color.red : Color.gray)
                    .frame(width: 16, height: 16)
                Text("Receiving Audio")
                    .font(.caption)
                Circle().fill(socketService.isSpeaking ? Color.green : Color.gray)
                    .frame(width: 16, height: 16)
                Text("Speaking")
                    .font(.caption)
                HStack(spacing: 4) {
                    Image(systemName: socketService.isUsingMainSpeaker ? "speaker.wave.2.fill" : "ear.fill")
                        .foregroundColor(socketService.isUsingMainSpeaker ? .blue : .green)
                        .font(.caption)
                    Text(socketService.isUsingMainSpeaker ? "Main" : "Ear")
                        .font(.caption)
                        .foregroundColor(socketService.isUsingMainSpeaker ? .blue : .green)
                }
                Spacer()
            }
            .padding(.horizontal)
            // Push-to-talk button
            HStack {
                Spacer()
                Circle()
                    .fill(socketService.isSpeaking ? Color.green : Color.blue)
                    .frame(width: 80, height: 80)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                socketService.webRTCClient?.setMicEnabled(true)
                            }
                            .onEnded { _ in
                                socketService.webRTCClient?.setMicEnabled(false)
                            }
                    )
                Spacer()
            }
            .padding(.vertical)
            
            // Speaker toggle button
            HStack {
                Spacer()
                Button(action: {
                    socketService.toggleSpeaker()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: socketService.isUsingMainSpeaker ? "speaker.wave.3.fill" : "ear.fill")
                            .foregroundColor(socketService.isUsingMainSpeaker ? .blue : .green)
                            .font(.title2)
                        Text(socketService.isUsingMainSpeaker ? "Main Speaker" : "Earpiece")
                            .font(.caption)
                            .foregroundColor(socketService.isUsingMainSpeaker ? .blue : .green)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(socketService.isUsingMainSpeaker ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 25)
                                    .stroke(socketService.isUsingMainSpeaker ? Color.blue : Color.green, lineWidth: 2)
                            )
                    )
                }
                .scaleEffect(socketService.isUsingMainSpeaker ? 1.0 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: socketService.isUsingMainSpeaker)
                Spacer()
            }
            .padding(.bottom)

            Text("🪵 Debug Log")
                .font(.headline)
                .padding(.top)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(socketService.logs.enumerated().reversed()), id: \.0) { index, log in
                        Text(log)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            #if os(iOS)
            .background(Color(UIColor.systemGray6))
            #else
            .background(Color.gray.opacity(0.2))
            #endif
            .cornerRadius(8)
            .padding(.top)
        }
            HStack {
                Button("Clear Logs") {
                    socketService.logs.removeAll()
                }
                // Add other control buttons here if desired
            }
        .padding()
    }
}