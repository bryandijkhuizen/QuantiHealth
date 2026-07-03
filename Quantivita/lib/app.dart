import 'package:flutter/material.dart';

import 'theme/quantivita_theme.dart';
import 'views/home/quantivita_home.dart';

class QuantivitaApp extends StatelessWidget {
  const QuantivitaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quantivita',
      debugShowCheckedModeBanner: false,
      theme: QuantivitaTheme.light(),
      darkTheme: QuantivitaTheme.dark(),
      themeMode: ThemeMode.system,
      home: const QuantivitaHome(),
    );
  }
}
