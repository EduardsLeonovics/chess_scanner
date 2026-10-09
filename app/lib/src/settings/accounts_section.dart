import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/accounts.dart';
import '../accounts/game_sources.dart';
import '../backup/library_backup.dart';
import '../community/auth_page.dart';
import '../community/community_repository.dart';
import '../puzzles/puzzle_store.dart';

const _ink = Color(0xFF29313B);
const _muted = Color(0xFF8A919B);
const _line = Color(0xFFE6E8EB);

/// "Connect to Lichess" / "Connect to Chess.com", or the connected username
/// with a disconnect button. Connecting needs a ChessHive account, which
/// keeps the games' analysis (see `backup/library_backup.dart`).
class AccountsSection extends ConsumerWidget {
  const AccountsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final signedIn = ref.watch(signedInProvider);
    final hasServer = ref.watch(communityProvider) != null;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: _muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final site in ChessSite.values)
          if (signedIn || accounts.of(site) != null) ...[
            _AccountTile(site: site, username: accounts.of(site)),
            const SizedBox(height: 10),
          ],
        if (!signedIn && hasServer) ...[
          FilledButton.icon(
            onPressed: () => ensureSignedIn(context, ref),
            icon: const Icon(Icons.person_outline),
            label: const Text('Sign in to connect your accounts'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (accounts.any) ...[
          Text(
            ref.watch(puzzleLibraryProvider).gameCountLabel,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: _ink),
          ),
          const SizedBox(height: 6),
        ],
        if (signedIn)
          if (_backupLabel(ref.watch(libraryBackupProvider)) case final label?) ...[
            Text(label, style: muted),
            const SizedBox(height: 6),
          ],
        Text(
          switch ((signedIn, hasServer)) {
            (true, _) => 'Used to turn mistakes from your own games into puzzles. '
                'Only your public games are read — no password needed.',
            (false, true) => 'Connect Lichess or Chess.com with a free ChessHive account. '
                'Your analyzed games and puzzles are saved to it, so they come back '
                'after a reinstall or on a new phone.',
            (false, false) => 'Connecting accounts needs the ChessHive server, which this '
                'version of the app doesn\'t have.',
          },
          style: muted,
        ),
      ],
    );
  }

  static String? _backupLabel(BackupStatus status) => switch (status) {
        BackupStatus.off => null,
        BackupStatus.syncing => 'Saving to your ChessHive account…',
        BackupStatus.saved => 'Saved to your ChessHive account.',
        BackupStatus.failed => 'Not saved to your ChessHive account yet. '
            'It\'s tried again on the next change.',
      };
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.site, required this.username});

  final ChessSite site;
  final String? username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = username;
    if (name == null) {
      return OutlinedButton.icon(
        onPressed: () async {
          final verified = await showDialog<String>(
            context: context,
            builder: (_) => _ConnectDialog(site: site),
          );
          if (verified != null) {
            await ref.read(accountsProvider.notifier).set(site, verified);
          }
        },
        icon: const Icon(Icons.link),
        label: Text('Connect to ${site.label}'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: _line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF15781B), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${site.label} · ', style: const TextStyle(color: _muted)),
                TextSpan(
                  text: name,
                  style: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
                ),
              ]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => ref.read(accountsProvider.notifier).set(site, null),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }
}

/// Asks for the username and checks it exists before closing with it.
class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog({required this.site});

  final ChessSite site;

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  final _controller = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final name = await verifyAccount(widget.site, _controller.text);
      if (mounted) Navigator.of(context).pop(name);
    } on GameSourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Connect to ${widget.site.label}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter your ${widget.site.label} username.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_checking,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: 'Username',
              border: const OutlineInputBorder(),
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _checking ? null : _submit,
          child: _checking
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Connect'),
        ),
      ],
    );
  }
}
