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
  final Set<int> _visited = {YomashiNavIndex.home};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: List.generate(4, (index) {
          if (!_visited.contains(index)) return const SizedBox.shrink();
          return ExcludeFocus(
            excluding: index != _index,
            child: TickerMode(
              enabled: index == _index,
              child: switch (index) {
                YomashiNavIndex.home => const HomeScreen(),
                YomashiNavIndex.offline => const OfflineLibraryScreen(),
                YomashiNavIndex.downloads => const DownloadQueueScreen(),
                _ => const ProfileScreen(),
              },
            ),
          );
        }),
      ),
      bottomNavigationBar: YomashiBottomNavBar(
        currentIndex: _index,
        onTap: (value) {
          if (value == _index) {
            return;
          }
          FocusScope.of(context).unfocus();
          setState(() {
            _visited.add(value);
            _index = value;
          });
        },
      ),
    );
  }
}
