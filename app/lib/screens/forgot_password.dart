import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../theme.dart';

/// Asks the server for a reset link. There is no email service: the server prints the link in its
/// terminal, and the new password is set on the website's reset page.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.api});
  final FarNotesApi api;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  String? _error;
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final message = await widget.api.forgotPassword(_email.text);
      if (mounted) setState(() => _message = message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Reset your password.',
      copy: 'Enter the email address on your account. A one-time reset link will be printed in the local server terminal.',
      children: [
        TextField(
          controller: _email,
          decoration: const InputDecoration(labelText: 'Email address'),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 14),
        if (_error != null) FormMessage(_error!),
        if (_message != null) FormMessage(_message!, isError: false),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Request reset link')),
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to sign in')),
      ],
    );
  }
}
