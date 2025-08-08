    import SwiftUI
import CoreLocation
import Foundation

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
                    let newClient = WebRTCClient()
                    socketService.webRTCClient = newClient
                    selectedPeer = nil
                    socketService.connect(location: locationManager.currentLocation)
                    socketService.webRTCClient?.delegate = { signal in
                        guard let from = (signal["from"] as? String) ?? selectedPeer else { return }
                        let msg: [String: Any] = [
                            "type": "SIGNAL",
                            "to": from,
                            "from": socketService.keyPair.publicKey,
                            "signal": signal
                        ]
                        print("📤 Sending SIGNAL:", msg)
                        socketService.send(data: msg)
                    }
                }
            }

            Button("Call Peer") {
                // Prevent dialing the same peer when already connected
                guard let target = selectedPeer, !(socketService.webRTCClient?.isConnected ?? false) else { return }
                socketService.webRTCClient?.delegate = { signal in
                    let msg: [String: Any] = [
                        "type": "SIGNAL",
                        "to": target,
                        "from": socketService.keyPair.publicKey,
                        "signal": signal
                    ]
                    print("📤 Sending SIGNAL:", msg)
                    socketService.send(data: msg)
                }
                socketService.webRTCClient?.offer()
            }
            .disabled(selectedPeer == nil || (socketService.webRTCClient?.isConnected ?? false))

            List(socketService.peers, id: \.self) { peer in
                HStack {
                    Circle()
                        .fill(socketService.connectedPeer == peer ? Color.green : Color.red)
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
                Circle().fill((socketService.webRTCClient?.isReceivingAudio ?? false) ? Color.red : Color.gray)
                    .frame(width: 16, height: 16)
                Text("Receiving Audio")
                    .font(.caption)
                Circle().fill((socketService.webRTCClient?.isSpeaking ?? false) ? Color.green : Color.gray)
                    .frame(width: 16, height: 16)
                Text("Speaking")
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal)
            // Push-to-talk button
            HStack {
                Spacer()
                Circle()
                    .fill((socketService.webRTCClient?.isSpeaking ?? false) ? Color.green : Color.blue)
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