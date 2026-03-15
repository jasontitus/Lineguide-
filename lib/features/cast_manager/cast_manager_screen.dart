import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/cast_member_model.dart';
import '../../data/models/script_models.dart';
import '../../data/services/supabase_service.dart';
import '../../providers/production_providers.dart';

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
      final production = ref.read(currentProductionProvider);
      if (production != null) {
        ref.read(castMembersProvider.notifier).loadForProduction(production.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final script = ref.watch(currentScriptProvider);
    final production = ref.watch(currentProductionProvider);
    final castMembers = ref.watch(castMembersProvider);
    final recordings = ref.watch(recordingsProvider);

    if (script == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cast Manager')),
        body: const Center(child: Text('No script loaded')),
      );
    }

    final joinCode = production?.joinCode;
    final joinedCount =
        castMembers.where((m) => m.hasJoined && m.role != CastRole.organizer).length;
    final totalRecordedLines = recordings.length;
    final totalLines = script.lines
        .where((l) => l.lineType == LineType.dialogue)
        .length;
    final progressPct =
        totalLines > 0 ? (totalRecordedLines / totalLines * 100).round() : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cast & Roles'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.record_voice_over),
            tooltip: 'Voice settings',
            onPressed: () => context.push('/voice-config'),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share cast list',
            onPressed: () => _shareCastList(script, castMembers),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Join code banner ──
          if (joinCode != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Join Code',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer
                                    .withValues(alpha: 0.7),
                              ),
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          joinCode,
                          style:
                              Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 4,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy code',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: joinCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Join code copied'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.share),
                    tooltip: 'Share code',
                    onPressed: () => _shareJoinCode(joinCode),
                  ),
                ],
              ),
            ),
          // ── Summary bar ──
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.people,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$joinedCount of ${script.characters.length} actors joined'
                        ' · $totalRecordedLines/$totalLines lines recorded ($progressPct%)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                if (totalLines > 0) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: totalRecordedLines / totalLines,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Character list ──
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: script.characters.length,
              itemBuilder: (context, index) {
                final char = script.characters[index];
                final color = AppTheme.colorForCharacter(char.colorIndex);
                final primary = ref
                    .read(castMembersProvider.notifier)
                    .primaryFor(char.name);
                final understudy = ref
                    .read(castMembersProvider.notifier)
                    .understudyFor(char.name);

                // Recording progress for this character
                final charLines = script.linesForCharacter(char.name);
                final recordedCount = charLines
                    .where((l) => recordings.containsKey(l.id))
                    .length;
                final recordProgress = charLines.isEmpty
                    ? 0.0
                    : recordedCount / charLines.length;

                return _buildCharacterCard(
                  context,
                  char,
                  primary,
                  understudy,
                  color,
                  recordProgress,
                  recordedCount,
                  charLines.length,
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
    CastMemberModel? primary,
    CastMemberModel? understudy,
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
              member: primary,
              color: color,
              onAssign: () => _assignRole(char.name, CastRole.primary),
            ),
            const SizedBox(height: 8),
            // Understudy assignment
            _buildRoleRow(
              context,
              label: 'Understudy',
              member: understudy,
              color: color.withValues(alpha: 0.6),
              onAssign: () => _assignRole(char.name, CastRole.understudy),
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
    required CastMemberModel? member,
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
        if (member != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  member.displayName.isNotEmpty
                      ? member.displayName
                      : 'Unnamed',
                  style: TextStyle(color: color, fontSize: 13),
                ),
                const SizedBox(width: 6),
                _statusBadge(member),
              ],
            ),
          ),
          const Spacer(),
          // Nudge button if invited but not joined
          if (!member.hasJoined)
            IconButton(
              icon: Icon(Icons.notifications_active,
                  size: 16, color: Colors.orange[600]),
              tooltip: 'Send reminder',
              onPressed: () => _nudge(member),
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: Colors.grey[600]),
            onPressed: () => _unassignRole(member),
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

  Widget _statusBadge(CastMemberModel member) {
    final joined = member.hasJoined;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: (joined ? Colors.green : Colors.orange).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        joined ? 'Joined' : 'Invited',
        style: TextStyle(
          fontSize: 10,
          color: joined ? Colors.green : Colors.orange,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _assignRole(String characterName, CastRole role) {
    final nameController = TextEditingController();
    final contactController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Assign ${role.name} for $characterName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Actor name',
                border: OutlineInputBorder(),
                hintText: 'Enter actor name',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contactController,
              decoration: const InputDecoration(
                labelText: 'Email or phone (optional)',
                border: OutlineInputBorder(),
                hintText: 'For sending join code',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              final production = ref.read(currentProductionProvider);
              if (production == null) return;

              final contact = contactController.text.trim();
              final member = CastMemberModel(
                id: const Uuid().v4(),
                productionId: production.id,
                characterName: characterName,
                displayName: name,
                contactInfo: contact.isNotEmpty ? contact : null,
                role: role,
                invitedAt: DateTime.now(),
              );

              await ref.read(castMembersProvider.notifier).save(member);

              // Also save to Supabase if signed in
              final supa = SupabaseService.instance;
              if (supa.isSignedIn) {
                try {
                  await supa.createCastInvitation(
                    productionId: production.id,
                    characterName: characterName,
                    displayName: name,
                    contactInfo: contact.isNotEmpty ? contact : null,
                    role: role.toSupabaseString(),
                  );
                } catch (e) {
                  debugPrint('Supabase cast invitation failed: $e');
                }
              }

              if (context.mounted) Navigator.pop(context);

              // Show join code in snackbar
              if (production.joinCode != null && mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Assigned $name. Share join code: ${production.joinCode}',
                    ),
                    action: SnackBarAction(
                      label: 'Share',
                      onPressed: () => _shareJoinCode(production.joinCode!),
                    ),
                  ),
                );
              }
            },
            child: const Text('Assign'),
          ),
        ],
      ),
    );
  }

  void _unassignRole(CastMemberModel member) {
    ref.read(castMembersProvider.notifier).remove(member.id);
  }

  void _inviteActor(String characterName) {
    final production = ref.read(currentProductionProvider);
    final productionTitle = production?.title ?? 'a production';
    final joinCode = production?.joinCode;

    final shareText = joinCode != null
        ? 'You\'ve been invited to join "$productionTitle" as $characterName '
            'on LineGuide! Open the app and enter join code: $joinCode'
        : 'You\'ve been invited to join "$productionTitle" as $characterName '
            'on LineGuide! Download the app to get started.';

    Share.share(shareText, subject: 'LineGuide Invitation');
  }

  void _shareJoinCode(String code) {
    final production = ref.read(currentProductionProvider);
    final title = production?.title ?? 'a production';

    Share.share(
      'Join "$title" on LineGuide!\n\nOpen the app and enter code: $code',
      subject: 'LineGuide Join Code',
    );
  }

  void _nudge(CastMemberModel member) {
    final production = ref.read(currentProductionProvider);
    final title = production?.title ?? 'the production';
    final code = production?.joinCode ?? '';

    final text =
        'Reminder: You\'re invited to play ${member.characterName} in "$title" '
        'on LineGuide. Open the app and enter code: $code';

    Share.share(text, subject: 'LineGuide Reminder');
  }

  void _shareCastList(ParsedScript script, List<CastMemberModel> members) {
    final production = ref.read(currentProductionProvider);
    final buffer = StringBuffer();
    buffer.writeln('Cast List: ${production?.title ?? script.title}');
    if (production?.joinCode != null) {
      buffer.writeln('Join Code: ${production!.joinCode}');
    }
    buffer.writeln('=' * 30);
    buffer.writeln();

    for (final char in script.characters) {
      buffer.writeln(char.name);
      final primary = members
          .where(
              (m) => m.characterName == char.name && m.role == CastRole.primary)
          .toList();
      if (primary.isNotEmpty) {
        buffer.writeln('  Primary: ${primary.first.displayName}'
            '${primary.first.hasJoined ? " (joined)" : " (invited)"}');
      } else {
        buffer.writeln('  Primary: (unassigned)');
      }
      final understudies = members
          .where((m) =>
              m.characterName == char.name && m.role == CastRole.understudy)
          .toList();
      if (understudies.isNotEmpty) {
        buffer.writeln('  Understudy: ${understudies.first.displayName}'
            '${understudies.first.hasJoined ? " (joined)" : " (invited)"}');
      }
      buffer.writeln('  Lines: ${char.lineCount}');
      buffer.writeln();
    }

    Share.share(buffer.toString(), subject: 'Cast List');
  }
}
