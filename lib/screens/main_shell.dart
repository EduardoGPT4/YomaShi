import 'package:flutter/material.dart';

import '../widgets/bottom_nav_bar.dart';
import 'download_queue_screen.dart';
import 'home_screen.dart';
import 'offline_library_screen.dart';
import 'profile_screen.dart';

/// Shell principal: Inicio · Offline · Descargas · Perfil.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = YomashiNavIndex.home;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_index) {
        YomashiNavIndex.home => const HomeScreen(),
        YomashiNavIndex.offline => const OfflineLibraryScreen(),
        YomashiNavIndex.downloads => const DownloadQueueScreen(),
        _ => const ProfileScreen(),
      },
      bottomNavigationBar: YomashiBottomNavBar(
        currentIndex: _index,
        onTap: (value) {
          if (value == _index) {
            return;
          }
          setState(() => _index = value);
        },
      ),
    );
  }
}
