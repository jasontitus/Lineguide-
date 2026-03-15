import 'package:flutter/material.dart';

import '../../data/services/stt_service.dart';

class ParakeetDebugScreen extends StatefulWidget {
  const ParakeetDebugScreen({super.key});

  @override
  State<ParakeetDebugScreen> createState() => _ParakeetDebugScreenState();
}

class _ParakeetDebugScreenState extends State<ParakeetDebugScreen> {
  final _stt = SttService.instance;

  // ── Free speech test ─────────────────────────────────
  bool _freeRecording = false;
  String _freeText = '';

  // ── Line accuracy test ───────────────────────────────
  bool _lineRecording = false;
  String _lineRecognized = '';
  double? _liveScore;
  final _lineController = TextEditingController(
    text: 'To be or not to be, that is the question. '
        'Whether tis nobler in the mind to suffer '
        'the slings and arrows of outrageous fortune.',
  );

  // ── Log ──────────────────────────────────────────────
  String _statusLog = '';

  @override
  void dispose() {
    _lineController.dispose();
    _stt.stop(discard: true);
    super.dispose();
  }

  void _log(String msg) {
    setState(() {
      _statusLog =
          '${DateTime.now().toString().substring(11, 19)} $msg\n$_statusLog';
    });
  }

  // ── Free Speech ──────────────────────────────────────

  Future<void> _startFreeRecording() async {
    // Auto-init if needed
    if (!_stt.isAvailable) {
      _log('STT not initialized — calling init()...');
      final ok = await _stt.init();
      _log('Init result: $ok, engine: ${_stt.activeEngine.name}');
      setState(() {});
      if (!ok) {
        _log('ERROR: No STT engine available. Is the Parakeet model downloaded?');
        return;
      }
    }

    setState(() {
      _freeRecording = true;
      _freeText = '';
    });
    _log('Recording (engine: ${_stt.activeEngine.name}, mlxReady: ${_stt.isMlxReady})');

    await _stt.listen(
      onResult: (recognized) {
        if (!mounted) return;
        setState(() => _freeText = recognized);
        _log('Text: "${recognized.length > 50 ? '${recognized.substring(0, 50)}...' : recognized}"');
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _freeRecording = false);
        _log('Done');
      },
      continuous: true,
      listenFor: const Duration(seconds: 120),
    );
  }

  Future<void> _stopFreeRecording() async {
    _log('Stopping...');
    await _stt.stop();
    setState(() => _freeRecording = false);
  }

  // ── Line Accuracy ────────────────────────────────────

  Future<void> _startLineRecording() async {
    // Auto-init if needed
    if (!_stt.isAvailable) {
      _log('STT not initialized — calling init()...');
      final ok = await _stt.init();
      _log('Init result: $ok, engine: ${_stt.activeEngine.name}');
      setState(() {});
      if (!ok) {
        _log('ERROR: No STT engine available.');
        return;
      }
    }

    setState(() {
      _lineRecording = true;
      _lineRecognized = '';
      _liveScore = null;
    });

    // Build vocabulary hints from the expected text
    final expectedText = _lineController.text.trim();
    final vocabHints = expectedText.split(RegExp(r'\s+')).toList();
    _log('Line test: recording (${vocabHints.length} hint words, engine: ${_stt.activeEngine.name})');

    await _stt.listen(
      onResult: (recognized) {
        if (!mounted) return;
        final score =
            SttService.matchScore(expectedText, recognized);
        setState(() {
          _lineRecognized = recognized;
          _liveScore = score;
        });
        _log('Score: ${(score * 100).toInt()}%');
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _lineRecording = false);
        if (_lineRecognized.isNotEmpty) {
          final finalScore =
              SttService.matchScore(expectedText, _lineRecognized);
          _log('Final: ${(finalScore * 100).toInt()}%');
        } else {
          _log('Line test: no speech detected');
        }
      },
      continuous: true,
      listenFor: const Duration(seconds: 120),
      vocabularyHints: vocabHints,
    );
  }

  Future<void> _stopLineRecording() async {
    _log('Stopping...');
    await _stt.stop();
    setState(() => _lineRecording = false);
  }

  // ── Build ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final anyRecording = _freeRecording || _lineRecording;

    return Scaffold(
      appBar: AppBar(
        title: const Text('STT Debug'),
        actions: [
          TextButton(
            onPressed: () async {
              _log('Initializing STT...');
              final ok = await _stt.init();
              _log('Init: engine=${_stt.activeEngine.name}, ok=$ok');
              setState(() {});
            },
            child: const Text('Init'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusBar(theme),
          const SizedBox(height: 16),

          // ── Free Speech Test ─────────────────────────
          Text('Free Speech Test', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Speak anything — words appear in real-time.',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 8),

          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 80),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
              border: _freeRecording
                  ? Border.all(color: Colors.red, width: 2)
                  : null,
            ),
            child: Text(
              _freeText.isEmpty
                  ? (_freeRecording
                      ? 'Listening... (text will appear as chunks complete)'
                      : 'Tap Record to start')
                  : _freeText,
              style: TextStyle(
                fontSize: 16,
                color: _freeText.isEmpty ? Colors.grey : Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: anyRecording
                      ? (_freeRecording ? _stopFreeRecording : null)
                      : _startFreeRecording,
                  icon: Icon(_freeRecording ? Icons.stop : Icons.mic),
                  label: Text(_freeRecording ? 'Stop' : 'Record'),
                  style: _freeRecording
                      ? FilledButton.styleFrom(backgroundColor: Colors.red)
                      : null,
                ),
              ),
              if (_freeText.isNotEmpty && !_freeRecording) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() => _freeText = ''),
                  child: const Text('Clear'),
                ),
              ],
            ],
          ),
          if (_freeRecording)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(),
            ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // ── Line Accuracy Test ───────────────────────
          Text('Line Accuracy Test', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Speak the line below — live score with vocabulary hints.',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _lineController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Expected line',
              isDense: true,
            ),
            maxLines: 3,
            enabled: !_lineRecording,
          ),
          const SizedBox(height: 8),

          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 80),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
              border: _lineRecording
                  ? Border.all(color: Colors.red, width: 2)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_liveScore != null) ...[
                  _buildScoreBar(_liveScore!),
                  const SizedBox(height: 8),
                ],
                if (_lineRecognized.isNotEmpty)
                  _buildWordComparison(
                      _lineController.text, _lineRecognized)
                else
                  Text(
                    _lineRecording
                        ? 'Listening... (score appears as chunks complete)'
                        : 'Tap Record to start',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: anyRecording
                      ? (_lineRecording ? _stopLineRecording : null)
                      : _startLineRecording,
                  icon: Icon(_lineRecording ? Icons.stop : Icons.mic),
                  label: Text(_lineRecording ? 'Stop' : 'Record'),
                  style: _lineRecording
                      ? FilledButton.styleFrom(backgroundColor: Colors.red)
                      : null,
                ),
              ),
              if (_lineRecognized.isNotEmpty && !_lineRecording) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _lineRecognized = '';
                    _liveScore = null;
                  }),
                  child: const Text('Clear'),
                ),
              ],
            ],
          ),
          if (_lineRecording)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(),
            ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),

          // ── Log ──────────────────────────────────────
          Text('Log', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Container(
            height: 160,
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(4),
            ),
            child: SingleChildScrollView(
              child: Text(
                _statusLog.isEmpty ? 'No actions yet' : _statusLog,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.greenAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Widgets ──────────────────────────────────────────

  Widget _buildStatusBar(ThemeData theme) {
    final engineColor =
        _stt.activeEngine == SttEngine.apple ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.hearing, size: 16, color: engineColor),
          const SizedBox(width: 6),
          Text(
            _stt.activeEngine.name.toUpperCase(),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: engineColor),
          ),
          const SizedBox(width: 12),
          _chip('Hints', true),
          const SizedBox(width: 6),
          _chip('Available', _stt.isAvailable),
          const Spacer(),
          if (_freeRecording || _lineRecording)
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool ok) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ok ? Colors.green.withAlpha(40) : Colors.red.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: ok ? Colors.green : Colors.red,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildScoreBar(double score) {
    final percent = (score * 100).toInt();
    final color = score >= 0.8
        ? Colors.green
        : score >= 0.5
            ? Colors.orange
            : Colors.red;
    return Row(
      children: [
        Text(
          '$percent%',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score,
              minHeight: 8,
              backgroundColor: Colors.grey[800],
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  static String _normalizeWord(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();

  Widget _buildWordComparison(String expected, String spoken) {
    final expectedWords = _normalizeWord(expected).split(RegExp(r'\s+'));
    final spokenRaw = spoken.split(RegExp(r'\s+'));

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: spokenRaw.map((word) {
        final normalizedWord = _normalizeWord(word);
        final matched = expectedWords.contains(normalizedWord);
        return Text(
          word,
          style: TextStyle(
            fontSize: 16,
            color: matched ? Colors.greenAccent : Colors.redAccent,
            fontWeight: matched ? FontWeight.normal : FontWeight.bold,
          ),
        );
      }).toList(),
    );
  }
}
