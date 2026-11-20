import 'package:material_ui/material_ui.dart';

// The website's colors (styles.css).
const ink = Color(0xFF18251F);
const muted = Color(0xFF718078);
const line = Color(0xFFE8ECE7);
const canvas = Color(0xFFF5F7F3);
const green = Color(0xFF315D46);
const greenSoft = Color(0xFFE8F0E9);
const amber = Color(0xFFD8A45B);
const errorRed = Color(0xFFB3261E);

ThemeData farNotesTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: green, primary: green, surface: Colors.white);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    appBarTheme: const AppBarTheme(backgroundColor: canvas, foregroundColor: ink, elevation: 0, scrolledUnderElevation: 0),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderSide: BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: line)),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(side: BorderSide(color: line), borderRadius: BorderRadius.all(Radius.circular(10))),
    ),
  );
}

/// "FAR NOTES / `suffix`" with the aircraft mark, as on the website's pages.
class Brand extends StatelessWidget {
  const Brand({super.key, required this.suffix});
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ExcludeSemantics(child: Image.asset('assets/aircraft-front-view.png', width: 28, height: 28)),
      const SizedBox(width: 10),
      Text('FAR NOTES / $suffix', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1.4, color: ink)),
    ]);
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 19, height: 1, color: amber),
      const SizedBox(width: 10),
      Text(text, style: const TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
    ]);
  }
}

/// The card layout shared by the sign-in, create-account and forgot-password screens.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.title, required this.copy, required this.children, this.footer});
  final String title;
  final String copy;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Brand(suffix: 'FAA REGS'),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Eyebrow('YOUR PERSONAL STUDY LOG'),
                      const SizedBox(height: 12),
                      Semantics(header: true, child: Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: ink))),
                      const SizedBox(height: 8),
                      Text(copy, style: const TextStyle(color: muted, height: 1.5)),
                      const SizedBox(height: 20),
                      ...children,
                    ]),
                  ),
                ),
                if (footer != null) ...[
                  const SizedBox(height: 16),
                  Text(footer!, style: const TextStyle(color: muted, fontSize: 12)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class FormMessage extends StatelessWidget {
  const FormMessage(this.text, {super.key, this.isError = true});
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        child: Text(text, style: TextStyle(color: isError ? errorRed : green, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
