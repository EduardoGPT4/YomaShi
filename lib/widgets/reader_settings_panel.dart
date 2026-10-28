import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/reader_settings_enums.dart';
import '../providers/reader_settings_provider.dart';

class ReaderSettingsPanel extends StatelessWidget {
  const ReaderSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<ReaderSettingsProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBrightnessControl(theme, settings),
        _buildSwitchTile(
          theme: theme,
          title: 'Recortar márgenes blancos',
          subtitle:
              'Conserva el archivo original; se aplica solo a imágenes estáticas.',
          value: settings.cropWhite,
          onChanged: settings.setCropWhite,
        ),
        _buildDropdown<String>(
          theme: theme,
          label: 'Orientación de pantalla',
          icon: Icons.screen_rotation,
          value: settings.orientation,
          items: const ['system', 'portrait', 'landscape'],
          itemLabel: (v) => switch (v) {
            'portrait' => 'Vertical',
            'landscape' => 'Horizontal',
            _ => 'Automática',
          },
          onChanged: settings.setOrientation,
        ),
        const SizedBox(height: 12),
        _buildDropdown<ReadingDirection>(
          theme: theme,
          label: 'Direccion de lectura',
          icon: Icons.swap_horiz_rounded,
          value: settings.readingDirection,
          items: ReadingDirection.values,
          itemLabel: (value) => value.label,
          onChanged: settings.setReadingDirection,
        ),
        const SizedBox(height: 10),
        _buildDropdown<PageFitMode>(
          theme: theme,
          label: 'Ajuste de pagina',
          icon: Icons.fit_screen_rounded,
          value: settings.pageFitMode,
          items: PageFitMode.values,
          itemLabel: (value) => value.label,
          onChanged: settings.setPageFitMode,
        ),
        const SizedBox(height: 10),
        _buildDropdown<PageTransitionSpeed>(
          theme: theme,
          label: 'Velocidad de transicion',
          icon: Icons.speed_rounded,
          value: settings.transitionSpeed,
          items: PageTransitionSpeed.values,
          itemLabel: (value) => value.label,
          onChanged: settings.setTransitionSpeed,
        ),
        const SizedBox(height: 8),
        _buildSwitchTile(
          theme: theme,
          title: 'Zoom y movimiento libre',
          subtitle: 'Permite ampliar y desplazar la imagen.',
          value: settings.freeZoom,
          onChanged: settings.setFreeZoom,
        ),
        _buildSwitchTile(
          theme: theme,
          title: 'Mostrar numero de pagina',
          subtitle: 'Indicador en la barra superior del lector.',
          value: settings.showPageNumber,
          onChanged: settings.setShowPageNumber,
        ),
        _buildSwitchTile(
          theme: theme,
          title: 'Toque en los lados',
          subtitle: 'Las zonas laterales siguen la dirección de lectura.',
          value: settings.tapNavigation,
          onChanged: settings.setTapNavigation,
        ),
        _buildSwitchTile(
          theme: theme,
          title: 'Botones de volumen',
          subtitle: 'Subir volumen: siguiente, bajar: anterior.',
          value: settings.volumeNavigation,
          onChanged: settings.setVolumeNavigation,
        ),
        _buildSwitchTile(
          theme: theme,
          title: 'Portada en página separada',
          subtitle: 'En doble página, la primera imagen se muestra sola.',
          value: settings.coverAlone,
          onChanged: settings.setCoverAlone,
        ),
        _buildSwitchTile(
          theme: theme,
          title: 'Webtoon continuo',
          subtitle: 'Desplazamiento vertical sin separar las páginas.',
          value: settings.continuousVertical,
          onChanged: settings.setContinuousVertical,
        ),
        _buildSwitchTile(
          theme: theme,
          title: 'Doble pagina',
          subtitle: settings.verticalMode
              ? 'Solo disponible en modo horizontal.'
              : 'Muestra dos paginas a la vez.',
          value: settings.doublePage && settings.isHorizontal,
          onChanged: settings.isHorizontal ? settings.setDoublePage : null,
        ),
      ],
    );
  }

  Widget _buildBrightnessControl(
    ThemeData theme,
    ReaderSettingsProvider settings,
  ) {
    final brightnessValue = settings.appBrightness;
    final brightnessPercent = (brightnessValue * 100).round();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.brightness_4_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Brillo en app', style: theme.textTheme.titleSmall),
              ),
              Text(
                '$brightnessPercent%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(170),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Slider(
            value: brightnessValue,
            min: 0.0,
            max: 1.0,
            divisions: 100,
            onChanged: settings.setAppBrightness,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required ThemeData theme,
    required String label,
    required IconData icon,
    required T value,
    required List<T> items,
    required String Function(T value) itemLabel,
    required ValueChanged<T> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: _panelDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 4),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              isExpanded: true,
              value: value,
              borderRadius: BorderRadius.circular(12),
              items: items
                  .map(
                    (item) => DropdownMenuItem<T>(
                      value: item,
                      child: Text(itemLabel(item)),
                    ),
                  )
                  .toList(),
              onChanged: (next) {
                if (next != null) {
                  onChanged(next);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.onSurface.withAlpha(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile.adaptive(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          value: value,
          onChanged: onChanged,
          title: Text(title, style: theme.textTheme.titleSmall),
          subtitle: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(160),
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _panelDecoration(ThemeData theme) {
    return BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: theme.colorScheme.onSurface.withAlpha(20)),
    );
  }
}
