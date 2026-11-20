import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../theme.dart';
import 'create_account.dart';
import 'forgot_password.dart';
import 'tracker.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api});
  final FarNotesApi api;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your username or email and your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final username = await widget.api.signIn(_username.text, _password.text);
      if (!mounted) return;
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => TrackerScreen(api: widget.api, username: username)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      _passwordFocus.requestFocus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Welcome back.',
      copy: 'Sign in to continue your FAA regulations study log.',
      footer: 'Always verify current regulations with official FAA sources.',
      children: [
        // Test ids: Android exposes them as resource-id and iOS as the element's name; a text box's label
        // is only a hint on Android, which Appium can't search by.
        Semantics(
          identifier: 'username',
          child: TextField(
            controller: _username,
            decoration: const InputDecoration(labelText: 'Username or email'),
            autocorrect: false,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
        ),
        const SizedBox(height: 14),
        Semantics(
          identifier: 'password',
          child: TextField(
            controller: _password,
            focusNode: _passwordFocus,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(height: 14),
        if (_error != null) FormMessage(_error!),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Sign in')),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ForgotPasswordScreen(api: widget.api))),
          child: const Text('Forgot password?'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreateAccountScreen(api: widget.api))),
          child: const Text('Create an account'),
        ),
      ],
    );
  }
}
