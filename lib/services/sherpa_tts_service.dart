import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

class SherpaTtsService {
  late sherpa_onnx.OfflineTts _tts;

  bool _initialized = false;

  // ============================================================
  // PIPER MODEL
  // ============================================================

  static const String _modelPath =
      'assets/models/tts/vits-piper-en_US-kathleen-low/en_US-kathleen-low.onnx';

  static const String _tokensPath =
      'assets/models/tts/vits-piper-en_US-kathleen-low/tokens.txt';

  static const String _dataDir =
      'assets/models/tts/vits-piper-en_US-kathleen-low/espeak-ng-data';

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final vitsConfig =
        sherpa_onnx.OfflineTtsVitsModelConfig(
      model: _modelPath,
      tokens: _tokensPath,
      dataDir: _dataDir,
    );

    final modelConfig =
        sherpa_onnx.OfflineTtsModelConfig(
      vits: vitsConfig,
    );

    final ttsConfig =
        sherpa_onnx.OfflineTtsConfig(
      model: modelConfig,
    );

    _tts = sherpa_onnx.OfflineTts(
      ttsConfig,
    );

    _initialized = true;
  }

  // ============================================================
  // GENERATE SPEECH
  // ============================================================

  sherpa_onnx.GeneratedAudio? generate(
    String text,
  ) {
    if (!_initialized) {
      throw StateError(
        'TTS has not been initialized.',
      );
    }

    final cleanText = text.trim();

    if (cleanText.isEmpty) {
      return null;
    }

    final audio = _tts.generate(
      text: cleanText,
      sid: 0,
      speed: 1.0,
    );

    return audio;
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  void dispose() {
    if (_initialized) {
      _tts.free();
      _initialized = false;
    }
  }
}