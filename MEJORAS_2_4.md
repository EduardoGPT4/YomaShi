# Interfaz 2.4.0

Cambios derivados de las 17 capturas revisadas el 28 de octubre de 2026.

## Cambios

- Descargas: historial con cantidad y rango resumidos, lista de capítulos bajo «Ver detalles» virtualizada y eliminación en el encabezado. Progreso por capítulos completos y pendientes; páginas guardadas identificadas como subtotal conocido. Los errores indican dónde se detuvo la tarea y permiten reintentar pendientes. Los controles de prioridad aparecen cuando son aplicables.
- Perfil: identidad primero y secciones Cuenta, Descargas, Biblioteca, Apariencia, Lector y Ajustes avanzados. Se conservan importación, exportación, copias, diagnóstico, avatar y personalización.
- MyAnimeList: conexión como primer paso; búsqueda y sincronización aparecen tras conectarse. Una autorización pendiente se puede continuar sin generar otra sesión; reiniciarla es una acción explícita. El reintento se oculta cuando no hay envíos pendientes.
- Tema: acento legible en superficies oscuras y fondos seleccionados, manteniendo el acento elegido en botones y calculando su color de texto. Paneles neutros y selección con indicador adicional.
- Lector: ajustes en una hoja sin abandonar el capítulo, grupos Imagen/Lectura/Controles y menú de acciones con etiquetas. Contador de páginas con área mínima de 48 puntos y semántica accesible.
- Capítulos: búsqueda por título/número, salto al actual y lista que se abre con el capítulo seleccionado centrado. La proporción original de las imágenes se conserva.
- Inicio: alcance de búsqueda visible y separado del catálogo elegido; errores por fuente con explicación y reintento en la misma tarjeta. Las tarjetas agrupadas por fuente evitan repetir la etiqueta en cada portada.
- Biblioteca: búsqueda con nombre natural, controles de filtros con etiqueta y cuadrícula de dos columnas en pantallas estrechas. Favoritos con área táctil de 48 puntos y categorías disponibles en un menú visible además del gesto largo.
- Navegación: las pestañas se crean al visitarlas y conservan búsqueda, filtros y desplazamiento. Se excluye el foco de pestañas ocultas y se cierra el teclado al cambiar.
- Automatización: secciones Novedades/Condiciones/Copias, fechas legibles, unidades simplificadas y ubicación de copias seleccionable y copiable.
- Almacenamiento: estado «Calculando…» con guiones hasta disponer de medición, resumen, búsqueda y orden por tamaño/título; explicación y confirmación de actualización de carpetas antiguas.
- Textos: entidades HTML decodificadas sin perder signos literales, tildes y codificación corregidas, y etiqueta «Descargar» coherente. Marcar leído/no leído tiene menú explícito y aviso con «Deshacer» para el estado local.

## Comprobaciones

- `flutter test`: 148 pruebas correctas. Dos comprobaciones opcionales se omiten en la ejecución habitual: API real de MAL y generación de capturas.
- Regresiones nuevas: historial de 500 capítulos, selector de 1.200 capítulos, vistas de 320 puntos con texto ampliado, reintento de pendientes, almacenamiento asíncrono, autorización pendiente reutilizable, identidad de MAL, contraste de acentos y búsqueda conservada entre pestañas.
- Capturas reproducibles sin red ni cuentas reales:

  `flutter test test/ui_preview_test.dart --dart-define=YOMASHI_UI_CAPTURE=true --update-goldens`

  Se guardan en `build/verification/ui-2.4.0/`, excluido de Git. Usan el tema real y fuentes del SDK.

El backend de MyAnimeList conserva su protocolo y despliegue; esta actualización no requiere cambios en el servidor.
