import 'package:flutter/material.dart';
import 'package:welwi/screens/calendar/calendar_screen.dart';
import 'package:welwi/screens/notes/notes_screen.dart';
import 'package:welwi/theme/app_theme.dart';

/// A pure data viewer — Notes and Calendar, nothing else. Reached only via
/// the 5-tap gesture on the live companion screen, for a sighted companion
/// or judge to glance at what the voice agent has actually saved. It has no
/// role in actually using the app: no mic, no agent interaction, just a
/// read view of the same Firestore-backed data the agent writes to.
class SightedDataScreen extends StatefulWidget {
  const SightedDataScreen({super.key});

  @override
  State<SightedDataScreen> createState() => _SightedDataScreenState();
}

class _SightedDataScreenState extends State<SightedDataScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => AppColors.dopamineGradientHorizontal.createShader(bounds),
          child: Text(
            _tabIndex == 0 ? 'Notes' : 'Calendar',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
          ),
        ),
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: const [NotesScreen(), CalendarScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.surface,
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.notes_outlined), selectedIcon: Icon(Icons.notes_rounded), label: 'Notes'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month_rounded), label: 'Calendar'),
        ],
      ),
    );
  }
}
