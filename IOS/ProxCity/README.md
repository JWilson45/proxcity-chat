# ProxCity iOS App

A decentralized, peer-to-peer voice chat platform that enables nearby users to discover each other and connect directly without relying on a central voice server.

## Features

### Connection Management
- **Automatic Reconnection**: The app automatically attempts to reconnect to the signaling server when the connection is lost
- **Exponential Backoff**: Reconnection attempts use exponential backoff (1s, 2s, 4s, 8s, etc.) up to a maximum of 60 seconds
- **Network Monitoring**: Built-in network reachability monitoring to detect when network connectivity is restored
- **Connection State Management**: Clear visual indicators for connection status (Connected, Connecting, Reconnecting, Disconnected, Failed)

### WebRTC Features
- **Push-to-Talk**: Hold the microphone button to speak
- **Live Audio Indicators**: Visual feedback for speaking and receiving audio
- **Call Re-establishment**: Ability to re-establish calls after reconnection to the signaling server
- **Graceful Disconnection**: Proper cleanup of WebRTC connections when signaling server disconnects

### UI Improvements
- **Connection Status Display**: Real-time connection status with color-coded indicators
- **Reconnection Overlay**: Visual feedback during reconnection attempts
- **Retry Button**: Manual retry option when connection fails
- **Debug Logging**: Comprehensive logging for troubleshooting connection issues

## Connection States

- **Connected** (Green): Successfully connected to signaling server
- **Connecting** (Orange): Attempting initial connection
- **Reconnecting** (Orange): Attempting to reconnect after disconnection
- **Disconnected** (Gray): Not connected to signaling server
- **Failed** (Red): Connection failed after maximum retry attempts

## Reconnection Behavior

1. **Automatic Detection**: App detects disconnections from signaling server
2. **Exponential Backoff**: Reconnection attempts start at 1 second and double each time
3. **Network Awareness**: Only attempts reconnection when network is available
4. **WebRTC Cleanup**: Properly closes WebRTC connections during disconnection
5. **State Restoration**: Recreates WebRTC client after successful reconnection

## Usage

1. **Connect**: Tap "Connect" to establish connection to signaling server
2. **Select Peer**: Choose a peer from the list to call
3. **Call**: Tap "Call Peer" to initiate a WebRTC connection
4. **Push-to-Talk**: Hold the microphone button to speak
5. **Reconnect Call**: Use "Reconnect Call" button to re-establish calls after reconnection

## Technical Details

### Reconnection Configuration
- Maximum reconnection attempts: 10
- Base delay: 1 second
- Maximum delay: 60 seconds
- Exponential backoff formula: `min(baseDelay * 2^(attempt-1), maxDelay)`

### Network Monitoring
- Uses `NWPathMonitor` for network reachability
- Automatically attempts reconnection when network is restored
- Prevents reconnection attempts when network is unavailable

### WebRTC Management
- Automatic cleanup of WebRTC connections on signaling disconnect
- Recreation of WebRTC client after successful reconnection
- Proper handling of ICE candidates and session descriptions

## Troubleshooting

### Connection Issues
1. Check network connectivity
2. Verify signaling server is running at `ws://192.168.1.188:3000`
3. Use "Retry" button if connection fails
4. Check debug logs for detailed error information

### Audio Issues
1. Ensure microphone permissions are granted
2. Check that audio session is properly configured
3. Verify WebRTC connection state in debug logs

### Reconnection Issues
1. Monitor connection status indicator
2. Check network availability
3. Review reconnection attempt logs
4. Use "Force Reconnect" if needed
