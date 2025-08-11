# ProxCity iOS App

A proximity-based chat application that enables real-time voice communication with nearby users.

## Features

- **Proximity-based Discovery**: Automatically finds and connects to nearby users
- **Real-time Voice Chat**: Push-to-talk voice communication using WebRTC
- **Speaker Switching**: Toggle between main speaker and earpiece for optimal audio experience
- **Secure Communication**: End-to-end encrypted messaging using Curve25519 key pairs
- **Location-based**: Uses GPS coordinates for proximity detection

## Speaker Switching

The app now supports switching between two audio output modes:

- **Main Speaker**: Audio plays through the device's main speaker (default)
- **Earpiece**: Audio plays through the device's earpiece for private listening

### How to Use Speaker Switching

1. **Toggle Button**: Tap the speaker toggle button located below the push-to-talk button
2. **Visual Feedback**: The button shows the current speaker mode with different icons and colors
3. **Status Indicator**: The current audio route is also displayed in the status bar at the bottom
4. **Real-time Switching**: You can switch speakers at any time during a call

### Speaker Modes

- **🔊 Main Speaker** (Blue): Audio plays through the main speaker for hands-free use
- **👂 Earpiece** (Green): Audio plays through the earpiece for private conversations

## Usage

1. **Connect**: Tap "Connect" to join the proximity network
2. **Select Peer**: Choose a nearby user from the peer list
3. **Start Call**: Tap "Call Peer" to initiate a voice connection
4. **Push-to-Talk**: Hold the large blue circle to speak
5. **Switch Speakers**: Use the speaker toggle button to change audio output

## Technical Details

- Built with SwiftUI and WebRTC
- Uses AVAudioSession for audio routing control
- Supports both main speaker and earpiece output modes
- Real-time audio switching without interrupting calls

## Requirements

- iOS 14.0+
- Xcode 12.0+
- WebRTC framework
- Starscream for WebSocket communication
