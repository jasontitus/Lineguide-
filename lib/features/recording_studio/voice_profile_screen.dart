import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/voice_clone_service.dart';
import '../../providers/production_providers.dart';

/// Shows the voice clone profile status for a character and lets
/// the user see how many recordings feed into voice cloning.
class VoiceProfileScreen extends ConsumerWidget {
  const VoiceProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final character = ref.watch(recordingCharacterProvider);
    final recordings = ref.watch(recordingsProvider);
    final voiceClone = VoiceCloneService.instance;

    if (character == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Voice Profile')),
        body: const Center(child: Text('No character selected')),
      );
    }

    // Count recordings for this character
    final charRecordings = recordings.values
        .where((r) => r.character == character)
        .toList();
    final profile = voiceClone.getProfile(character);
    final quality = profile?.quality ?? 0.0;
    final canClone = voiceClone.canClone(character);

    return Scaffold(
      appBar: AppBar(title: Text('$character — Voice Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Voice quality indicator
            Center(
              child: Column(
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: quality,
                          strokeWidth: 8,
                          backgroundColor: Colors.grey[800],
                          color: _qualityColor(quality),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              canClone ? Icons.record_voice_over : Icons.mic,
                              size: 32,
                              color: _qualityColor(quality),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${(quality * 100).toInt()}%',
                              style: TextStyle(
                                color: _qualityColor(quality),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    canClone
                        ? 'Voice Clone Ready'
                        : 'Need More Recordings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${charRecordings.length} recordings available',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // How it works
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('How Voice Cloning Works',
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _stepTile(
                      '1. Record lines',
                      'Record at least 3 lines for this character '
                          '(more = better quality)',
                      charRecordings.length >= 3,
                    ),
                    _stepTile(
                      '2. Build voice profile',
                      'The app analyzes recordings to capture the '
                          'character\'s voice signature',
                      profile != null,
                    ),
                    _stepTile(
                      '3. Generate unrecorded lines',
                      'During rehearsal, unrecorded lines are spoken '
                          'in the character\'s cloned voice',
                      canClone,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Build/refresh profile button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: charRecordings.length >= 3
                    ? () => _buildProfile(context, character, charRecordings)
                    : null,
                icon: Icon(
                    profile != null ? Icons.refresh : Icons.auto_awesome),
                label: Text(
                    profile != null ? 'Refresh Profile' : 'Build Profile'),
              ),
            ),

            if (charRecordings.length < 3) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Record ${3 - charRecordings.length} more '
                  'line${3 - charRecordings.length == 1 ? '' : 's'} to enable voice cloning',
                  style: TextStyle(color: Colors.orange[400], fontSize: 13),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Quality tips
            Text('Tips for Better Voice Cloning',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    )),
            const SizedBox(height: 8),
            _tipTile(Icons.mic, 'Record in a quiet environment'),
            _tipTile(Icons.speed, 'Speak at your natural pace'),
            _tipTile(Icons.playlist_add, 'More recordings = higher quality'),
            _tipTile(Icons.sentiment_satisfied, 'Include varied emotions'),
          ],
        ),
      ),
    );
  }

  Color _qualityColor(double quality) {
    if (quality >= 0.7) return Colors.green;
    if (quality >= 0.4) return Colors.orange;
    return Colors.grey;
  }

  Widget _stepTile(String title, String subtitle, bool done) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        done ? Icons.check_circle : Icons.circle_outlined,
        color: done ? Colors.green : Colors.grey,
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _tipTile(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 12),
          Text(text, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _buildProfile(
    BuildContext context,
    String character,
    List<dynamic> recordings,
  ) async {
    final paths = recordings
        .map((r) => r.localPath as String)
        .toList();

    final voiceClone = VoiceCloneService.instance;
    final profile = await voiceClone.buildProfileFromRecordings(
      character: character,
      recordingPaths: paths,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Voice profile built with ${profile.referenceAudioPaths.length} clips '
            '(${(profile.quality * 100).toInt()}% quality)',
          ),
        ),
      );
    }
  }
}
