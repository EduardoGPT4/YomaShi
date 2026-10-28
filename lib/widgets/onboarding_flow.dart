import 'package:flutter/material.dart';

import '../utils/preferences.dart';

class OnboardingFlow {
  static Future<void> showIfNeeded(BuildContext context) async {
    final completed = await PreferencesService.getOnboardingCompleted();
    if (!context.mounted || completed) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return const _OnboardingDialog();
      },
    );
  }
}

class _OnboardingDialog extends StatefulWidget {
  const _OnboardingDialog();

  @override
  State<_OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<_OnboardingDialog> {
  final PageController _controller = PageController();
  int _page = 0;

  static const _pages = <_OnboardingPageData>[
    _OnboardingPageData(
      icon: Icons.folder_open_rounded,
      title: 'Biblioteca offline',
      body:
          'Al iniciar, YomaShi crea la carpeta YomaShi en la raíz del teléfono '
          '(/storage/emulated/0/YomaShi). Formato: Manga/Nombre/Capitulo 001/001.jpg',
    ),
    _OnboardingPageData(
      icon: Icons.public_rounded,
      title: 'Fuentes y online',
      body:
          'Elige la fuente en Fuentes, explora en Online y descarga mangas a la carpeta Manga/.',
    ),
    _OnboardingPageData(
      icon: Icons.favorite_rounded,
      title: 'Favoritos y categorias',
      body:
          'Marca mangas con el corazon. Mantén presionado para asignar categorias personalizadas.',
    ),
    _OnboardingPageData(
      icon: Icons.download_rounded,
      title: 'Descargas y offline',
      body:
          'La pestaña Descargas muestra la cola. Offline reúne solo lo local y descargado.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await PreferencesService.setOnboardingCompleted(true);
    await PreferencesService.setWelcomeNoticeSeen(true);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _next() async {
    if (_page >= _pages.length - 1) {
      await _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      content: SizedBox(
        width: 360,
        height: 320,
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        page.icon,
                        size: 48,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        page.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        page.body,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.45,
                          color: theme.colorScheme.onSurface.withAlpha(190),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (index) {
                final active = index == _page;
                return Container(
                  width: active ? 18 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: active
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withAlpha(50),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _finish, child: const Text('Saltar')),
        FilledButton(
          onPressed: _next,
          child: Text(_page >= _pages.length - 1 ? 'Empezar' : 'Siguiente'),
        ),
      ],
    );
  }
}

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String body;

  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.body,
  });
}
