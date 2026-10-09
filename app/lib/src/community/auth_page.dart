import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_info.dart';
import 'community_models.dart';
import 'community_repository.dart';

/// Sign in, or create a ChessHive account. Pops with true once signed in.
class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key, this.createAccount = false});

  /// Open on "Create account" rather than "Sign in".
  final bool createAccount;

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  late bool _creating = widget.createAccount;
  bool _busy = false;
  String? _error;

  /// After sign-up when the email must be confirmed first.
  bool _checkEmail = false;

  bool _closed = false;

  /// Pops once, however the user got signed in.
  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final repo = ref.read(communityProvider);
    if (repo == null || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_creating) {
        final signedIn = await repo.signUp(
          email: _email.text,
          password: _password.text,
          username: _username.text.trim(),
        );
        if (!mounted) return;
        if (!signedIn) {
          setState(() => _checkEmail = true);
          return;
        }
      } else {
        await repo.signIn(login: _email.text, password: _password.text);
      }
      _close();
    } on CommunityException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final repo = ref.read(communityProvider);
    final email = _email.text.trim();
    if (repo == null) return;
    if (!email.contains('@')) {
      setState(() => _error = 'Enter your email above, then tap "Forgot password?" again.');
      return;
    }
    try {
      await repo.sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('We sent a link to $email to set a new password.')),
      );
    } on CommunityException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Also signed in by a password-reset or confirmation link opened while
    // this page is up; the Community tab then asks for a new password.
    ref.listen(communityUserProvider, (previous, next) {
      if (next.value != null) _close();
    });
    final theme = Theme.of(context);
    if (_checkEmail) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confirm your email')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.mark_email_read_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                'We sent a confirmation link to ${_email.text.trim()}. Open it on this '
                'phone to finish creating your account, then sign in.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => setState(() {
                  _checkEmail = false;
                  _creating = false;
                }),
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_creating ? 'Create account' : 'Sign in')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Sign in')),
                ButtonSegment(value: true, label: Text('Create account')),
              ],
              selected: {_creating},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                _creating = s.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 24),
            if (_creating) ...[
              TextFormField(
                controller: _username,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixText: '@',
                  helperText: 'Shown on your posts. 3–20 letters, digits or _.',
                ),
                autocorrect: false,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    usernamePattern.hasMatch(v?.trim() ?? '') ? null : 'Use 3–20 letters, digits or _.',
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _email,
              decoration: InputDecoration(labelText: _creating ? 'Email' : 'Email or username'),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: _creating
                  ? const [AutofillHints.email]
                  : const [AutofillHints.email, AutofillHints.username],
              textInputAction: TextInputAction.next,
              validator: (v) {
                final text = v?.trim() ?? '';
                if (_creating) return text.contains('@') ? null : 'Enter your email.';
                return text.isNotEmpty ? null : 'Enter your email or username.';
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: _creating ? 'At least 6 characters.' : null,
              ),
              obscureText: true,
              autofillHints: [_creating ? AutofillHints.newPassword : AutofillHints.password],
              onFieldSubmitted: (_) => _submit(),
              validator: (v) => (v?.length ?? 0) >= 6 ? null : 'At least 6 characters.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_creating ? 'Create account' : 'Sign in'),
            ),
            if (!_creating)
              TextButton(onPressed: _busy ? null : _forgotPassword, child: const Text('Forgot password?')),
            if (_creating) ...[
              const SizedBox(height: 16),
              Text(
                'Your username, posts and comments are visible to other ChessHive users. '
                'Be kind: posts that are reported for abuse are removed.\n\n'
                'By creating an account you agree to the Terms of Use '
                '(${AppInfo.termsUrl}) and the Privacy Policy (${AppInfo.privacyUrl}).',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Makes sure the user is signed in, opening [AuthPage] if not. True when
/// signed in afterwards.
Future<bool> ensureSignedIn(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(communityProvider);
  if (repo == null) return false;
  if (repo.user != null) return true;
  final signedIn = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const AuthPage()),
  );
  return signedIn == true && repo.user != null;
}
