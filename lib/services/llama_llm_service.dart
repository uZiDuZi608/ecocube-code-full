import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';

class LlamaLlmService {
  static const String _modelAsset =
      'assets/models/llm/llama/Llama-3.2-1B-Instruct-Q4_K_M.gguf';

  static const String _modelFileName =
      'Llama-3.2-1B-Instruct-Q4_K_M.gguf';

  LlamaEngine? _engine;
  bool _initialized = false;

  // ============================================================
  // INITIALIZE LOCAL LLAMA
  // ============================================================

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    try {
      print('Initializing LOCAL LlamaDart Llama 3.2 1B...');

      // Create Llama backend.
      final engine = LlamaEngine(
        LlamaBackend(),
      );

      // Copy Flutter asset to a real filesystem location.
      final modelPath = await _getLocalModelPath();

      print('Llama model path: $modelPath');

      // Load GGUF model.
      await engine.loadModelSource(
        ModelSource.parse(modelPath),
      );

      _engine = engine;
      _initialized = true;

      print('LOCAL Llama 3.2 1B READY');
    } catch (e) {
      print('LOCAL Llama initialization failed: $e');

      _engine = null;
      _initialized = false;

      rethrow;
    }
  }

  // ============================================================
  // GET LOCAL MODEL PATH
  // ============================================================

  Future<String> _getLocalModelPath() async {
    final directory = await getApplicationSupportDirectory();

    final modelDirectory = Directory(
      '${directory.path}\\models\\llama',
    );

    if (!await modelDirectory.exists()) {
      await modelDirectory.create(
        recursive: true,
      );
    }

    final modelFile = File(
      '${modelDirectory.path}\\$_modelFileName',
    );

    // If model already exists, don't copy it again.
    if (await modelFile.exists()) {
      final fileSize = await modelFile.length();

      if (fileSize > 100000000) {
        print(
          'Existing Llama model found '
          '(${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB)',
        );

        return modelFile.path;
      }

      // Delete incomplete/corrupt copy.
      await modelFile.delete();
    }

    print('Copying Llama GGUF from Flutter assets...');

    final ByteData byteData = await rootBundle.load(
      _modelAsset,
    );

    final Uint8List bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );

    await modelFile.writeAsBytes(
      bytes,
      flush: true,
    );

    print(
      'Llama model copied successfully '
      '(${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB)',
    );

    return modelFile.path;
  }

  // ============================================================
  // GENERATE RESPONSE
  // ============================================================

  Future<String> generate(
    String text,
  ) async {
    if (!_initialized || _engine == null) {
      throw Exception(
        'Llama has not been initialized.',
      );
    }

    if (text.trim().isEmpty) {
      return '';
    }

    print('--------------------------------');
    print('LOCAL LLAMA');
    print('Prompt: ${text.trim()}');

    final output = StringBuffer();

    await for (final chunk in _engine!.create(
      [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: text.trim(),
        ),
      ],
      params: const GenerationParams(
        maxTokens: 256,
      ),
    )) {
      final content =
          chunk.choices.first.delta.content;

      if (content != null) {
        output.write(content);
      }
    }

    final response = output.toString().trim();

    print('Response: $response');
    print('--------------------------------');

    return response;
  }

  // ============================================================
  // STATUS
  // ============================================================

  bool get isReady => _initialized;

  // ============================================================
  // DISPOSE
  // ============================================================

  Future<void> dispose() async {
    if (_engine != null) {
      await _engine!.dispose();
      _engine = null;
    }

    _initialized = false;

    print('LOCAL LLAMA DISPOSED');
  }
}