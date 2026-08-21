import 'dart:async';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

import 'device_discovery_service.dart';
import 'audio_socket_service.dart';

class ConnectionProvider {
  // ============================================================
  // SERVICES
  // ============================================================

  final DeviceDiscoveryService discoveryService =
      DeviceDiscoveryService();

  final AudioSocketService audioSocketService =
      AudioSocketService();

  // ============================================================
  // DISCOVERED DEVICES
  // ============================================================

  final List<nsd.Service> discoveredDevices = [];

  // ============================================================
  // TCP INCOMING DATA
  // ============================================================

  StreamSubscription<Uint8List>? _incomingSubscription;

  // ============================================================
  // CONNECTED DEVICE
  // ============================================================

  nsd.Service? connectedDevice;

  // ============================================================
  // CONNECTION STATUS
  // ============================================================

  bool get isConnected =>
      audioSocketService.isConnected;

  // ============================================================
  // START mDNS DISCOVERY
  // ============================================================

  Future<void> startDiscovery() async {
    discoveredDevices.clear();

    await discoveryService.startDiscovery(
      onDeviceFound: (nsd.Service service) {
        if (!discoveredDevices.contains(service)) {
          discoveredDevices.add(service);
        }
      },
    );
  }

  // ============================================================
  // CONNECT TO DISCOVERED DEVICE
  // ============================================================

  Future<void> connectToDevice(
    nsd.Service service,
  ) async {
    final host = service.host;
    final port = service.port;

    if (host == null || host.isEmpty) {
      throw StateError(
        'Device does not have a valid IP address.',
      );
    }

    if (port == null) {
      throw StateError(
        'Device does not have a TCP port.',
      );
    }

    await audioSocketService.connect(
      host: host,
      port: port,
    );

    connectedDevice = service;

    // Listen for incoming TCP data.
    _incomingSubscription =
        audioSocketService.incomingData.listen(
      (Uint8List data) {
        _handleIncomingData(data);
      },
    );
  }

  // ============================================================
  // HANDLE INCOMING TCP DATA
  // ============================================================

  void _handleIncomingData(
    Uint8List data,
  ) {
    final response = String.fromCharCodes(data);

    print(
      'EchoCube incoming data: $response',
    );

    // Later we can decode:
    // - audio packets
    // - device status
    // - LLM responses
    // - commands
  }

  // ============================================================
  // SEND AUDIO
  // ============================================================

  Future<void> sendAudio(
    Uint8List audioData,
  ) async {
    await audioSocketService.sendAudio(
      audioData,
    );
  }

  // ============================================================
  // SEND TEXT
  // ============================================================

  Future<void> sendText(
    String text,
  ) async {
    await audioSocketService.sendText(
      text,
    );
  }

  // ============================================================
  // MOCK ECHOCUBE CONNECTION TEST
  //
  // Used while physical EchoCube hardware is not available.
  //
  // PC:
  // 192.168.100.250
  //
  // TCP:
  // Port 5000
  // ============================================================

  Future<void> testMockConnection() async {
    print(
      'Connecting to mock EchoCube server...',
    );

    await audioSocketService.connect(
      host: '192.168.100.250',
      port: 5000,
    );

    print(
      'TCP connection established.',
    );

    // Listen for server response.
    _incomingSubscription =
        audioSocketService.incomingData.listen(
      (Uint8List data) {
        final response =
            String.fromCharCodes(data);

        print(
          'EchoCube server response: $response',
        );
      },
      onError: (Object error) {
        print(
          'TCP incoming data error: $error',
        );
      },
    );

    // Send test message.
    await audioSocketService.sendText(
      'Hello from Flutter',
    );

    print(
      'Test message sent to mock EchoCube.',
    );
  }

  // ============================================================
  // DISCONNECT
  // ============================================================

  Future<void> disconnect() async {
    await _incomingSubscription?.cancel();

    _incomingSubscription = null;

    await audioSocketService.disconnect();

    connectedDevice = null;
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  Future<void> dispose() async {
    await disconnect();

    await discoveryService.dispose();

    await audioSocketService.dispose();
  }
}