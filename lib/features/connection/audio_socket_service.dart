import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class AudioSocketService {
  Socket? _socket;

  final StreamController<Uint8List> _incomingDataController =
      StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get incomingData =>
      _incomingDataController.stream;

  bool get isConnected => _socket != null;

  Future<void> connect({
    required String host,
    required int port,
  }) async {
    await disconnect();

    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 5),
    );

    _socket = socket;

    socket.listen(
      (Uint8List data) {
        _incomingDataController.add(data);
      },
      onError: (Object error) {
        _incomingDataController.addError(error);
      },
      onDone: () {
        _socket = null;
      },
      cancelOnError: false,
    );
  }

  Future<void> send(Uint8List data) async {
    final socket = _socket;

    if (socket == null) {
      throw StateError('TCP socket is not connected.');
    }

    socket.add(data);
    await socket.flush();
  }

  Future<void> sendAudio(Uint8List audioData) async {
    await send(audioData);
  }

  Future<void> sendText(String text) async {
    final data = Uint8List.fromList(
      text.codeUnits,
    );

    await send(data);
  }

  Future<void> disconnect() async {
    final socket = _socket;

    if (socket != null) {
      await socket.close();
      _socket = null;
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _incomingDataController.close();
  }
}