import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

class SherpaSttService {
  late final sherpa_onnx.OfflineRecognizer _recognizer;

  bool _initialized = false;

  // ============================================================
  // MODEL PATH
  // ============================================================

  static const String _modelDir =
      'assets/models/stt/'
      'sherpa-onnx-nemo-ctc-en-conformer-medium';

  static const String _model =
      '$_modelDir/model.int8.onnx';

  static const String _tokens =
      '$_modelDir/tokens.txt';

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    // ==========================================================
    // NeMo CTC MODEL
    // ==========================================================

    final nemoCtc =
        sherpa_onnx.OfflineNemoEncDecCtcModelConfig(
      model: _model,
    );

    // ==========================================================
    // OFFLINE MODEL CONFIG
    // ==========================================================

    final modelConfig =
        sherpa_onnx.OfflineModelConfig(
      nemoCtc: nemoCtc,
      tokens: _tokens,
      numThreads: 2,
      debug: false,
      provider: 'cpu',
      modelType: 'nemo_ctc',
    );

    // ==========================================================
    // RECOGNIZER CONFIG
    // ==========================================================

    final recognizerConfig =
        sherpa_onnx.OfflineRecognizerConfig(
      model: modelConfig,
      decodingMethod: 'greedy_search',
    );

    // ==========================================================
    // CREATE RECOGNIZER
    // ==========================================================

    _recognizer =
        sherpa_onnx.OfflineRecognizer(
      recognizerConfig,
    );

    _initialized = true;
  }

  // ============================================================
  // RECOGNIZE AUDIO
  // ============================================================

  String recognize(
    List<double> samples,
    int sampleRate,
  ) {
    if (!_initialized) {
      throw StateError(
        'STT has not been initialized.',
      );
    }

    if (samples.isEmpty) {
      return '';
    }

    // ==========================================================
    // CREATE OFFLINE STREAM
    // ==========================================================

    final stream =
        _recognizer.createStream();

    // ==========================================================
    // CONVERT TO Float32List
    // ==========================================================

    final floatSamples =
        Float32List.fromList(samples);

    // ==========================================================
    // FEED AUDIO
    // ==========================================================

    stream.acceptWaveform(
      samples: floatSamples,
      sampleRate: sampleRate,
    );

    // ==========================================================
    // DECODE
    // ==========================================================

    _recognizer.decode(stream);

    // ==========================================================
    // GET RESULT
    // ==========================================================

    final result =
        _recognizer.getResult(stream);

    // ==========================================================
    // FREE STREAM
    // ==========================================================

    stream.free();

    return result.text.trim();
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  void dispose() {
    if (_initialized) {
      _recognizer.free();
      _initialized = false;
    }
  }
}