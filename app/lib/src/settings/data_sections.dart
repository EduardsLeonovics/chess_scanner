import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_info.dart';
import '../diagnostics/crash_log.dart';
import '../puzzles/puzzle.dart';
import '../puzzles/puzzle_store.dart';

const _ink = Color(0xFF29313B);
const _muted = Color(0xFF8A919B);
const _line = Color(0xFFE6E8EB);
const _danger = Color(0xFFC62828);

/// A section title in the style of "Accounts" / "Customization".
class SettingsHeading extends StatelessWidget {
  const SettingsHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 36, bottom: 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
      ),
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _danger),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colour = onTap == null ? _muted : (destructive ? _danger : _ink);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: colour),
      title: Text(title, style: TextStyle(color: colour)),
      subtitle: Text(subtitle, style: const TextStyle(color: _muted)),
      onTap: onTap,
    );
  }
}

/// Reset puzzle progress or delete every puzzle.
class PuzzleDataSection extends ConsumerWidget {
  const PuzzleDataSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(puzzleLibraryProvider);
    final notifier = ref.read(puzzleLibraryProvider.notifier);
    final attempted = library.puzzles.where((p) => p.result != PuzzleResult.unsolved).length;
    final count = library.puzzles.length;

    return Column(
      children: [
        _ActionRow(
          icon: Icons.restart_alt,
          title: 'Reset puzzle progress',
          subtitle: attempted == 0
              ? 'No puzzles attempted yet'
              : 'Mark all $count puzzles as unsolved again',
          onTap: attempted == 0
              ? null
              : () async {
                  final ok = await _confirm(
                    context,
                    title: 'Reset puzzle progress?',
                    message: 'All $count puzzles will be marked unsolved. The puzzles themselves are kept.',
                    action: 'Reset',
                  );
                  if (ok) notifier.resetProgress();
                },
        ),
        _ActionRow(
          icon: Icons.delete_outline,
          title: 'Delete all puzzles',
          subtitle: count == 0
              ? 'No puzzles yet'
              : 'Remove $count puzzles and re-analyze your games from scratch next time',
          destructive: true,
          onTap: count == 0
              ? null
              : () async {
                  final ok = await _confirm(
                    context,
                    title: 'Delete all puzzles?',
                    message: 'All $count puzzles and the record of which games were analyzed will be '
                        'deleted. This can\'t be undone.',
                    action: 'Delete',
                  );
                  if (ok) {
                    ref.read(puzzleGeneratorProvider.notifier).cancel();
                    notifier.deleteAll();
                  }
                },
        ),
      ],
    );
  }
}

/// Saved crash reports: send or delete them.
class CrashReportsSection extends ConsumerWidget {
  const CrashReportsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(crashLogProvider);
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final count = log.reports.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count == 0
                  ? 'No crashes recorded. If something goes wrong, the details are saved on '
                      'this phone and you\'ll be asked whether to send them.'
                  : '$count crash report${count == 1 ? '' : 's'} saved on this phone. '
                      'Nothing is sent unless you choose to.',
              style: const TextStyle(color: _muted),
            ),
            if (count > 0)
              Builder(
                builder: (buttonContext) => _ActionRow(
                  icon: Icons.send_outlined,
                  title: 'Send crash reports',
                  subtitle: 'Opens the share sheet so you can review and send them',
                  onTap: () => log.share(origin: shareOrigin(buttonContext)),
                ),
              ),
            if (count > 0)
              _ActionRow(
                icon: Icons.delete_outline,
                title: 'Delete crash reports',
                subtitle: 'Remove the saved reports from this phone',
                destructive: true,
                onTap: log.clear,
              ),
          ],
        );
      },
    );
  }
}

/// Version, licence and source code: the GPL's "appropriate legal notices".
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data == null ? '' : ' ${snapshot.data!.version}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppInfo.name}$version is free software under the GNU GPL v3. '
              'Not affiliated with or endorsed by Lichess or Chess.com.',
              style: const TextStyle(color: _muted),
            ),
            _ActionRow(
              icon: Icons.code,
              title: 'Source code',
              subtitle: '${AppInfo.sourceUrl}\nTap to copy the link',
              onTap: () {
                Clipboard.setData(const ClipboardData(text: AppInfo.sourceUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link copied')),
                );
              },
            ),
            _ActionRow(
              icon: Icons.description_outlined,
              title: 'Open-source licences',
              subtitle: 'Stockfish, chessground, dartchess and the other parts ChessGeek is built on',
              onTap: () => showLicensePage(
                context: context,
                applicationName: AppInfo.name,
                applicationVersion: snapshot.data?.version,
                applicationLegalese: AppInfo.legalese,
              ),
            ),
            const Divider(color: _line),
          ],
        );
      },
    );
  }
}
