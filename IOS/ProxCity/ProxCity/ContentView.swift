import SwiftUI
import CoreLocation
import Foundation

struct ContentView: View {
    @StateObject var locationManager = LocationManager()
    @StateObject var socketService = WebSocketService()
    @State var webRTCClient = WebRTCClient()
    @State private var selectedPeer: String? = nil

    var body: some View {
        VStack(spacing: 20) {
            Text("ProxCity Chat")
                .font(.largeTitle)

            Button("Connect") {
                // Link WebSocketService to WebRTCClient
                socketService.webRTCClient = webRTCClient
                socketService.connect(location: locationManager.currentLocation)
                // Setup outgoing signaling for both offer and auto-answer
                webRTCClient.delegate = { signal in
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

            Button("Call Peer") {
                guard let target = selectedPeer else { return }
                webRTCClient.delegate = { signal in
                    let msg: [String: Any] = [
                        "type": "SIGNAL",
                        "to": target,
                        "from": socketService.keyPair.publicKey,
                        "signal": signal
                    ]
                    print("📤 Sending SIGNAL:", msg)
                    socketService.send(data: msg)
                }
                webRTCClient.offer()
            }

            List(socketService.peers, id: \.self) { peer in
                HStack {
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