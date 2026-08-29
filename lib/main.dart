import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:welwi/theme/app_theme.dart';
import 'package:welwi/providers/calendar_provider.dart';
import 'package:welwi/providers/notes_provider.dart';
import 'package:welwi/screens/welwi/cloud_voice_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const BenwApp());
}

class BenwApp extends StatelessWidget {
  const BenwApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CalendarProvider()),
        ChangeNotifierProvider(create: (_) => NotesProvider()),
      ],
      child: MaterialApp(
        title: 'Welwi',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const CloudVoiceScreen(),
      ),
    );
  }
}
