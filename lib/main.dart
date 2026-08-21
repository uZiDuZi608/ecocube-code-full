import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';

import 'services/sherpa_tts_service.dart';
import 'services/sherpa_stt_service.dart';
import 'services/llama_llm_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local Sherpa-ONNX native bindings.
  sherpa_onnx.initBindings();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ============================================================
  // LOCAL TTS
  // ============================================================

  final SherpaTtsService _sherpaTtsService =
      SherpaTtsService();

  // ============================================================
  // LOCAL STT
  // ============================================================

  final SherpaSttService _sherpaSttService =
      SherpaSttService();

  // ============================================================
  // LOCAL LLM - LLAMADART / LLAMA 3.2 1B
  // ============================================================

  final LlamaLlmService _llamaLlmService =
      LlamaLlmService();

  // ============================================================
  // AUDIO
  // ============================================================

  final AudioPlayer _audioPlayer = AudioPlayer();

  final AudioRecorder _audioRecorder =
      AudioRecorder();

  StreamSubscription<Uint8List>?
      _recordingSubscription;

  // ============================================================
  // TEXT
  // ============================================================

  final TextEditingController _textController =
      TextEditingController();

  // ============================================================
  // AUDIO SAMPLES
  // ============================================================

  final List<double> _audioSamples = [];

  // ============================================================
  // STATUS
  // ============================================================

  bool _ttsReady = false;
  bool _sttReady = false;
  bool _llamaReady = false;

  bool _isRecording = false;
  bool _isRecognizing = false;
  bool _isThinking = false;
  bool _isSpeaking = false;

  String _status =
      'Loading EchoCube local AI...';

  String _recognizedText = '';
  String _llmResponse = '';

  // ============================================================
  // INITIALIZATION
  // ============================================================

  @override
  void initState() {
    super.initState();

    _audioPlayer.setVolume(1.0);

    _initializeModels();
  }

  Future<void> _initializeModels() async {
    try {
      // --------------------------------------------------------
      // TTS
      // --------------------------------------------------------

      if (!mounted) return;

      setState(() {
        _status =
            'Loading local Piper TTS...';
      });

      await _sherpaTtsService.initialize();

      if (!mounted) return;

      setState(() {
        _ttsReady = true;
        _status =
            'TTS ready.\n'
            'Loading local STT...';
      });

      // --------------------------------------------------------
      // STT
      // --------------------------------------------------------

      await _sherpaSttService.initialize();

      if (!mounted) return;

      setState(() {
        _sttReady = true;
        _status =
            'STT ready.\n'
            'Loading local Llama 3.2 1B...';
      });

      // --------------------------------------------------------
      // LOCAL LLAMA
      // --------------------------------------------------------

      await _llamaLlmService.initialize();

      if (!mounted) return;

      setState(() {
        _llamaReady = true;

        _status =
            'EchoCube ready!\n'
            'TTS + STT + Llama 3.2 1B';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _llamaReady = false;

        _status =
            'Initialization error:\n$e';
      });
    }
  }

  // ============================================================
  // START RECORDING
  // ============================================================

  Future<void> _startRecording() async {
    if (!_sttReady) {
      setState(() {
        _status =
            'STT is still loading...';
      });

      return;
    }

    if (_isRecording ||
        _isRecognizing ||
        _isThinking ||
        _isSpeaking) {
      return;
    }

    try {
      final hasPermission =
          await _audioRecorder.hasPermission();

      if (!hasPermission) {
        if (!mounted) return;

        setState(() {
          _status =
              'Microphone permission denied.';
        });

        return;
      }

      // Reset previous audio.
      _audioSamples.clear();

      if (mounted) {
        setState(() {
          _recognizedText = '';
          _llmResponse = '';
        });
      }

      // --------------------------------------------------------
      // 16 kHz / MONO / PCM 16-BIT
      // --------------------------------------------------------

      final stream =
          await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _recordingSubscription =
          stream.listen(
        (Uint8List data) {
          _processMicrophoneData(data);
        },
        onError: (Object error) {
          if (!mounted) return;

          setState(() {
            _status =
                'Microphone error:\n$error';
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _isRecording = true;

        _status =
            '🎤 Listening...\n'
            'Speak now.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isRecording = false;

        _status =
            'Microphone error:\n$e';
      });
    }
  }

  // ============================================================
  // PROCESS MICROPHONE DATA
  // ============================================================

  void _processMicrophoneData(
    Uint8List data,
  ) {
    final byteData =
        ByteData.sublistView(data);

    for (
      int i = 0;
      i + 1 < data.length;
      i += 2
    ) {
      final sample =
          byteData.getInt16(
        i,
        Endian.little,
      );

      _audioSamples.add(
        sample / 32768.0,
      );
    }
  }

  // ============================================================
  // STOP RECORDING
  // ============================================================

  Future<void> _stopRecording() async {
    if (!_isRecording) {
      return;
    }

    try {
      await _audioRecorder.stop();

      await _recordingSubscription?.cancel();

      _recordingSubscription = null;

      if (!mounted) return;

      setState(() {
        _isRecording = false;
        _isRecognizing = true;

        _status =
            '🎤 Recording stopped.\n'
            '🧠 Recognizing speech...';
      });

      // --------------------------------------------------------
      // CHECK AUDIO
      // --------------------------------------------------------

      if (_audioSamples.isEmpty) {
        if (!mounted) return;

        setState(() {
          _isRecognizing = false;

          _status =
              'No microphone audio received.';
        });

        return;
      }

      // --------------------------------------------------------
      // STT
      // --------------------------------------------------------

      final text =
          _sherpaSttService.recognize(
        _audioSamples,
        16000,
      );

      if (!mounted) return;

      setState(() {
        _isRecognizing = false;

        _recognizedText =
            text.isEmpty
                ? '(No speech recognized)'
                : text;
      });

      if (text.trim().isEmpty) {
        if (!mounted) return;

        setState(() {
          _status =
              'No speech recognized.';
        });

        return;
      }

      // --------------------------------------------------------
      // SEND STT TEXT TO LOCAL LLAMA
      // --------------------------------------------------------

      await _sendToLlama(text);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isRecording = false;
        _isRecognizing = false;

        _status =
            'STT error:\n$e';
      });
    }
  }

  // ============================================================
  // SEND TEXT TO LOCAL LLAMA
  // ============================================================

  Future<void> _sendToLlama(
    String text,
  ) async {
    if (!_llamaReady) {
      if (!mounted) return;

      setState(() {
        _status =
            'Llama is not ready yet.\n'
            'Please wait for initialization.';
      });

      return;
    }

    try {
      if (!mounted) return;

      setState(() {
        _isThinking = true;

        _status =
            '🤖 Llama 3.2 1B is thinking...';
      });

      final response =
          await _llamaLlmService.generate(
        text,
      );

      if (!mounted) return;

      setState(() {
        _isThinking = false;

        _llmResponse = response;

        _status =
            '🤖 Llama response received.\n'
            '🔊 Preparing Piper TTS...';
      });

      // --------------------------------------------------------
      // SPEAK LLAMA RESPONSE
      // --------------------------------------------------------

      await _speakResponse(response);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isThinking = false;

        _status =
            'Llama error:\n$e';
      });
    }
  }

  // ============================================================
  // SPEAK LLAMA RESPONSE
  // ============================================================

  Future<void> _speakResponse(
    String text,
  ) async {
    if (!_ttsReady) {
      if (!mounted) return;

      setState(() {
        _status =
            'TTS is not ready.';
      });

      return;
    }

    try {
      if (!mounted) return;

      setState(() {
        _isSpeaking = true;

        _status =
            '🔊 Generating Piper speech...';
      });

      await _audioPlayer.stop();

      await _audioPlayer.setVolume(1.0);

      // --------------------------------------------------------
      // EXISTING PIPER / SHERPA TTS
      // --------------------------------------------------------

      final audio =
          _sherpaTtsService.generate(
        text,
      );

      if (audio == null) {
        if (!mounted) return;

        setState(() {
          _isSpeaking = false;

          _status =
              'TTS generated no audio.';
        });

        return;
      }

      // --------------------------------------------------------
      // CREATE WAV
      // --------------------------------------------------------

      final wavBytes =
          _createWavFile(
        audio.samples,
        audio.sampleRate,
      );

      // --------------------------------------------------------
      // PLAY AUDIO
      // --------------------------------------------------------

      await _audioPlayer.play(
        BytesSource(wavBytes),
      );

      if (!mounted) return;

      setState(() {
        _isSpeaking = false;

        _status =
            '✅ EchoCube finished speaking.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSpeaking = false;

        _status =
            'TTS error:\n$e';
      });
    }
  }

  // ============================================================
  // MANUAL TEXT → LLAMA → TTS
  // ============================================================

  Future<void> _sendTypedText() async {
    final text =
        _textController.text.trim();

    if (text.isEmpty) {
      setState(() {
        _status =
            'Please enter a message.';
      });

      return;
    }

    _textController.clear();

    await _sendToLlama(text);
  }

  // ============================================================
  // CREATE WAV
  // ============================================================

  Uint8List _createWavFile(
    List<double> samples,
    int sampleRate,
  ) {
    final pcmData =
        Int16List(samples.length);

    for (
      int i = 0;
      i < samples.length;
      i++
    ) {
      double sample = samples[i];

      if (sample > 1.0) {
        sample = 1.0;
      }

      if (sample < -1.0) {
        sample = -1.0;
      }

      pcmData[i] =
          (sample * 32767).round();
    }

    final pcmBytes =
        pcmData.buffer.asUint8List();

    const numChannels = 1;
    const bitsPerSample = 16;

    final byteRate =
        sampleRate *
        numChannels *
        bitsPerSample ~/
        8;

    final blockAlign =
        numChannels *
        bitsPerSample ~/
        8;

    final fileSize =
        36 + pcmBytes.length;

    final data =
        ByteData(
      44 + pcmBytes.length,
    );

    _writeString(
      data,
      0,
      'RIFF',
    );

    data.setUint32(
      4,
      fileSize,
      Endian.little,
    );

    _writeString(
      data,
      8,
      'WAVE',
    );

    _writeString(
      data,
      12,
      'fmt ',
    );

    data.setUint32(
      16,
      16,
      Endian.little,
    );

    data.setUint16(
      20,
      1,
      Endian.little,
    );

    data.setUint16(
      22,
      numChannels,
      Endian.little,
    );

    data.setUint32(
      24,
      sampleRate,
      Endian.little,
    );

    data.setUint32(
      28,
      byteRate,
      Endian.little,
    );

    data.setUint16(
      32,
      blockAlign,
      Endian.little,
    );

    data.setUint16(
      34,
      bitsPerSample,
      Endian.little,
    );

    _writeString(
      data,
      36,
      'data',
    );

    data.setUint32(
      40,
      pcmBytes.length,
      Endian.little,
    );

    final output =
        data.buffer.asUint8List();

    output.setRange(
      44,
      44 + pcmBytes.length,
      pcmBytes,
    );

    return output;
  }

  // ============================================================
  // WRITE WAV STRING
  // ============================================================

  void _writeString(
    ByteData data,
    int offset,
    String value,
  ) {
    for (
      int i = 0;
      i < value.length;
      i++
    ) {
      data.setUint8(
        offset + i,
        value.codeUnitAt(i),
      );
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _recordingSubscription?.cancel();

    _audioRecorder.dispose();

    _audioPlayer.dispose();

    _textController.dispose();

    _sherpaTtsService.dispose();

    _sherpaSttService.dispose();

    _llamaLlmService.dispose();

    super.dispose();
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'EchoCube Local AI',
        ),
      ),

      body: SingleChildScrollView(
        padding:
            const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,

          children: [
            // ==================================================
            // SYSTEM STATUS
            // ==================================================

            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(16),

                child: Column(
                  children: [
                    const Text(
                      'EchoCube',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    Text(
                      _status,
                      textAlign:
                          TextAlign.center,
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    Text(
                      'TTS: '
                      '${_ttsReady ? "READY" : "LOADING"}\n'
                      'STT: '
                      '${_sttReady ? "READY" : "LOADING"}\n'
                      'Llama 3.2 1B: '
                      '${_llamaReady ? "READY" : "LOADING"}',
                      textAlign:
                          TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            // ==================================================
            // VOICE ASSISTANT BUTTON
            // ==================================================

            ElevatedButton.icon(
              onPressed:
                  (!_isRecording &&
                          !_isRecognizing &&
                          !_isThinking &&
                          !_isSpeaking &&
                          _llamaReady)
                      ? _startRecording
                      : null,

              icon: const Icon(
                Icons.mic,
              ),

              label: Text(
                _isRecording
                    ? 'Listening...'
                    : _isThinking
                        ? 'Llama Thinking...'
                        : _isSpeaking
                            ? 'Speaking...'
                            : 'Talk to EchoCube',
              ),

              style:
                  ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(
                  vertical: 20,
                ),
              ),
            ),

            const SizedBox(
              height: 10,
            ),

            // ==================================================
            // STOP RECORDING
            // ==================================================

            ElevatedButton.icon(
              onPressed:
                  _isRecording
                      ? _stopRecording
                      : null,

              icon: const Icon(
                Icons.stop,
              ),

              label: const Text(
                'Stop Recording',
              ),
            ),

            const SizedBox(
              height: 25,
            ),

            // ==================================================
            // RECOGNIZED SPEECH
            // ==================================================

            const Text(
              'Recognized Speech',
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            Container(
              padding:
                  const EdgeInsets.all(16),

              decoration:
                  BoxDecoration(
                border:
                    Border.all(
                  color: Colors.grey,
                ),

                borderRadius:
                    BorderRadius.circular(8),
              ),

              child: Text(
                _recognizedText.isEmpty
                    ? 'Your speech will appear here...'
                    : _recognizedText,

                style:
                    const TextStyle(
                  fontSize: 17,
                ),
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            // ==================================================
            // LLAMA RESPONSE
            // ==================================================

            const Text(
              'Llama 3.2 1B Response',
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            Container(
              padding:
                  const EdgeInsets.all(16),

              decoration:
                  BoxDecoration(
                border:
                    Border.all(
                  color: Colors.grey,
                ),

                borderRadius:
                    BorderRadius.circular(8),
              ),

              child: Text(
                _llmResponse.isEmpty
                    ? 'Llama response will appear here...'
                    : _llmResponse,

                style:
                    const TextStyle(
                  fontSize: 17,
                ),
              ),
            ),

            const SizedBox(
              height: 25,
            ),

            // ==================================================
            // TEXT TEST
            // ==================================================

            const Text(
              'Text → Llama → Voice',
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            TextField(
              controller:
                  _textController,

              maxLines: 3,

              decoration:
                  const InputDecoration(
                border:
                    OutlineInputBorder(),

                hintText:
                    'Type a message for EchoCube...',
              ),
            ),

            const SizedBox(
              height: 10,
            ),

            ElevatedButton.icon(
              onPressed:
                  (!_isThinking &&
                          !_isSpeaking &&
                          _llamaReady)
                      ? _sendTypedText
                      : null,

              icon: const Icon(
                Icons.send,
              ),

              label: const Text(
                'Ask Llama',
              ),
            ),

            const SizedBox(
              height: 25,
            ),

            // ==================================================
            // LOCAL / OFFLINE COMPONENTS
            // ==================================================

            const Text(
              'Local / Offline Components',
              textAlign:
                  TextAlign.center,

              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            const Text(
              'STT: Sherpa-ONNX NeMo Conformer Medium\n'
              'LLM: LlamaDart — Llama 3.2 1B Q4_K_M\n'
              'TTS: Sherpa-ONNX Piper Kathleen Low\n'
              'Audio: 16 kHz • Mono • PCM 16-bit',
              textAlign:
                  TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

