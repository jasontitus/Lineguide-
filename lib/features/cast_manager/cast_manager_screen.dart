import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/script_models.dart';
import '../../providers/production_providers.dart';

/// Local cast assignment data — who plays which character.
class CastAssignment {
  final String characterName;
  final String? primaryName; // display name of primary actor
  final String? understudyName;
  final String? primaryUserId;
  final String? understudyUserId;

  const CastAssignment({
    required this.characterName,
    this.primaryName,
    this.understudyName,
    this.primaryUserId,
    this.understudyUserId,
  });

  CastAssignment copyWith({
    String? characterName,
    String? primaryName,
    String? understudyName,
    String? primaryUserId,
    String? understudyUserId,
  }) {
    return CastAssignment(
      characterName: characterName ?? this.characterName,
      primaryName: primaryName ?? this.primaryName,
      understudyName: understudyName ?? this.understudyName,
      primaryUserId: primaryUserId ?? this.primaryUserId,
      understudyUserId: understudyUserId ?? this.understudyUserId,
    );
  }

  bool get hasAssignment => primaryName != null || understudyName != null;
}

/// Provider for cast assignments, keyed by character name.
final castAssignmentsProvider =
    StateNotifierProvider<CastAssignmentsNotifier, Map<String, CastAssignment>>(
        (ref) {
  return CastAssignmentsNotifier();
});

class CastAssignmentsNotifier
    extends StateNotifier<Map<String, CastAssignment>> {
  CastAssignmentsNotifier() : super({});

  void assign(CastAssignment assignment) {
    state = {...state, assignment.characterName: assignment};
  }

  void remove(String characterName) {
    state = Map.from(state)..remove(characterName);
  }

  void initFromScript(ParsedScript script) {
    final map = <String, CastAssignment>{};
    for (final char in script.characters) {
      map[char.name] =
          state[char.name] ?? CastAssignment(characterName: char.name);
    }
    state = map;
  }
}

class CastManagerScreen extends ConsumerStatefulWidget {
  const CastManagerScreen({super.key});

  @override
  ConsumerState<CastManagerScreen> createState() => _CastManagerScreenState();
}

class _CastManagerScreenState extends ConsumerState<CastManagerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final script = ref.read(currentScriptProvider);
      if (script != null) {
        ref.read(castAssignmentsProvider.notifier).initFromScript(script);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final script = ref.watch(currentScriptProvider);
    final assignments = ref.watch(castAssignmentsProvider);
    final recordings = ref.watch(recordingsProvider);

    if (script == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cast Manager')),
        body: const Center(child: Text('No script loaded')),
      );
    }

    final assignedCount =
        assignments.values.where((a) => a.hasAssignment).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cast & Roles'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share cast list',
            onPressed: () => _shareCastList(script, assignments),
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(Icons.people, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${script.characters.length} characters',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '$assignedCount assigned',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (assignedCount == script.characters.length)
                  Chip(
                    label: const Text('Cast Complete'),
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    avatar: const Icon(Icons.check, size: 16),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Character list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: script.characters.length,
              itemBuilder: (context, index) {
                final char = script.characters[index];
                final assignment = assignments[char.name] ??
                    CastAssignment(characterName: char.name);
                final color = AppTheme.colorForCharacter(char.colorIndex);

                // Recording progress for this character
                final charLines = script.linesForCharacter(char.name);
                final recordedCount = charLines
                    .where((l) => recordings.containsKey(l.id))
                    .length;
                final recordProgress = charLines.isEmpty
                    ? 0.0
                    : recordedCount / charLines.length;

                return _buildCharacterCard(
                  context, char, assignment, color, recordProgress,
                  recordedCount, charLines.length,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterCard(
    BuildContext context,
    ScriptCharacter char,
    CastAssignment assignment,
    Color color,
    double recordProgress,
    int recordedCount,
    int totalLines,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Character header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color,
                  radius: 20,
                  child: Text(
                    char.name[0],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        char.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        '${char.lineCount} lines',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // Invite button
                IconButton(
                  icon: const Icon(Icons.person_add_outlined),
                  tooltip: 'Invite actor',
                  onPressed: () => _inviteActor(char.name),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Primary assignment
            _buildRoleRow(
              context,
              label: 'Primary',
              assignedName: assignment.primaryName,
              color: color,
              onAssign: () => _assignRole(char.name, 'primary'),
            ),
            const SizedBox(height: 8),
            // Understudy assignment
            _buildRoleRow(
              context,
              label: 'Understudy',
              assignedName: assignment.understudyName,
              color: color.withValues(alpha: 0.6),
              onAssign: () => _assignRole(char.name, 'understudy'),
            ),
            // Recording progress
            if (totalLines > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: recordProgress,
                      backgroundColor: color.withValues(alpha: 0.1),
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$recordedCount/$totalLines',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.mic, size: 14, color: Colors.grey[600]),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRoleRow(
    BuildContext context, {
    required String label,
    required String? assignedName,
    required Color color,
    required VoidCallback onAssign,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
        ),
        if (assignedName != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              assignedName,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: Colors.grey[600]),
            onPressed: () => _unassignRole(
                assignedName, label == 'Primary' ? 'primary' : 'understudy'),
            visualDensity: VisualDensity.compact,
          ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: onAssign,
            icon: const Icon(Icons.add, size: 16),
            label: Text('Assign $label'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  void _assignRole(String characterName, String role) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Assign $role for $characterName'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Actor name',
            border: OutlineInputBorder(),
            hintText: 'Enter actor name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;

              final current = ref.read(castAssignmentsProvider)[characterName] ??
                  CastAssignment(characterName: characterName);

              final updated = role == 'primary'
                  ? current.copyWith(primaryName: name)
                  : current.copyWith(understudyName: name);

              ref.read(castAssignmentsProvider.notifier).assign(updated);
              Navigator.pop(context);
            },
            child: const Text('Assign'),
          ),
        ],
      ),
    );
  }

  void _unassignRole(String actorName, String role) {
    // Find the assignment with this actor and clear it
    final assignments = ref.read(castAssignmentsProvider);
    for (final entry in assignments.entries) {
      final a = entry.value;
      if (role == 'primary' && a.primaryName == actorName) {
        ref.read(castAssignmentsProvider.notifier).assign(
              a.copyWith(primaryName: null),
            );
        break;
      }
      if (role == 'understudy' && a.understudyName == actorName) {
        ref.read(castAssignmentsProvider.notifier).assign(
              a.copyWith(understudyName: null),
            );
        break;
      }
    }
  }

  void _inviteActor(String characterName) {
    final production = ref.read(currentProductionProvider);
    final productionTitle = production?.title ?? 'a production';

    // Generate share text with deep link placeholder
    final shareText =
        'You\'ve been invited to join "$productionTitle" as $characterName '
        'on LineGuide! Download the app to get started.';

    Share.share(shareText, subject: 'LineGuide Invitation');
  }

  void _shareCastList(
      ParsedScript script, Map<String, CastAssignment> assignments) {
    final buffer = StringBuffer();
    buffer.writeln('Cast List: ${script.title}');
    buffer.writeln('=' * 30);
    buffer.writeln();

    for (final char in script.characters) {
      final a = assignments[char.name];
      buffer.writeln(char.name);
      if (a?.primaryName != null) {
        buffer.writeln('  Primary: ${a!.primaryName}');
      } else {
        buffer.writeln('  Primary: (unassigned)');
      }
      if (a?.understudyName != null) {
        buffer.writeln('  Understudy: ${a!.understudyName}');
      }
      buffer.writeln('  Lines: ${char.lineCount}');
      buffer.writeln();
    }

    Share.share(buffer.toString(), subject: 'Cast List');
  }
}
