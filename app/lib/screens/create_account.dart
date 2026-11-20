import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../theme.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key, required this.api});
  final FarNotesApi api;

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _created = false;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // The server checks everything again; this only saves a round trip for the common mistakes.
  String? _localCheck() {
    if (_username.text.trim().isEmpty || _email.text.trim().isEmpty || _password.text.isEmpty) {
      return 'Fill in all three fields.';
    }
    if (_password.text.runes.length < 15) return 'Password must be at least 15 characters.';
    return null;
  }

  Future<void> _submit() async {
    final problem = _localCheck();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.register(_username.text, _email.text, _password.text);
      if (mounted) setState(() => _created = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Create your account.',
      copy: 'Create a separate study log with a username, email address, and a strong password.',
      footer: 'Your account has a separate study log. Passwords are stored as salted hashes.',
      children: _created
          ? [
              const FormMessage('Account created successfully. Return to the sign-in screen to sign in.', isError: false),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to sign in')),
            ]
          : [
              TextField(
                controller: _username,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  helperText: 'Use 1-64 letters, numbers, periods, underscores, or hyphens.',
                  helperMaxLines: 2,
                ),
                autocorrect: false,
                maxLength: 64,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email address'),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  helperText: 'Use at least 15 characters. A long passphrase is a good choice.',
                  helperMaxLines: 2,
                ),
                obscureText: true,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 14),
              if (_error != null) FormMessage(_error!),
              FilledButton(onPressed: _busy ? null : _submit, child: const Text('Create account')),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to sign in')),
            ],
    );
  }
}
