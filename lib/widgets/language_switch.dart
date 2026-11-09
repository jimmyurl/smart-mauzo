import 'package:flutter/material.dart';
import '../services/app_language.dart';

/// English | Kiswahili picker. The choice is saved on the phone and the whole app
/// switches immediately.
class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLanguage.notifier,
      builder: (context, lang, _) => SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'en', label: Text('English')),
          ButtonSegment(value: 'sw', label: Text('Kiswahili')),
        ],
        selected: {lang},
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        onSelectionChanged: (s) => AppLanguage.set(s.first),
      ),
    );
  }
}