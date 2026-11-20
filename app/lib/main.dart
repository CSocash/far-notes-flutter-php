import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'screens/login.dart';
import 'screens/tracker.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FarNotesApp(api: FarNotesApi()));
}

class FarNotesApp extends StatelessWidget {
  const FarNotesApp({super.key, required this.api});
  final FarNotesApi api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FAR Notes',
      debugShowCheckedModeBanner: false,
      theme: farNotesTheme(),
      home: StartScreen(api: api),
    );
  }
}

/// Opens the tracker when a saved sign-in is still valid, otherwise the sign-in screen.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key, required this.api});
  final FarNotesApi api;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    String? username;
    try {
      await widget.api.loadToken();
      username = await widget.api.currentUsername();
    } catch (_) {
      username = null; // server unreachable: show sign-in, which reports the error on submit
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) =>
          username == null ? LoginScreen(api: widget.api) : TrackerScreen(api: widget.api, username: username),
    ));
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
