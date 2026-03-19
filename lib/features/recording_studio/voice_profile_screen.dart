import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Placeholder — voice cloning is not yet available.
/// The underlying service is preserved in voice_clone_service.dart for
/// future implementation.
class VoiceProfileScreen extends ConsumerWidget {
  const VoiceProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Profile')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.record_voice_over, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Voice cloning coming soon',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'This feature is under development.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
