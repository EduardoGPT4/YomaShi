# YomaShi

[Descargar el último APK](https://github.com/EduardoGPT4/YomaShi/releases/latest)

Aplicación Flutter para explorar, descargar y leer manga desde InManga, MangaDex, zonatmo.org y zonatmo.to, además de una biblioteca local. Se conserva el conector adicional de ManhwaWeb que ya incluía el proyecto.

- Búsqueda con selección de fuentes, resultados y paginación independientes.
- MangaDex: 42 idiomas seleccionables en Fuentes → MangaDex → Elegir idiomas, con búsqueda por nombre o código y selección múltiple guardada para catálogo, búsquedas y capítulos. Incluye variantes de español, portugués y chino.
- Biblioteca unificada: descargados, favoritos online y lecturas recientes, con búsqueda y filtros. Guardar con el corazón no descarga páginas.
- Continuar leyendo destacado, estados en portadas y resumen de descargas desde otras pestañas.
- Perfil separado de Ajustes, con búsqueda de configuración y consejos contextuales descartables.
- Interfaz con contraste adaptado al acento, acciones visibles y búsqueda conservada entre pestañas.
- Historial de descargas compacto con detalles y progreso por capítulos completos y pendientes.
- Capítulos por bloques para series largas; continuidad y reanudación desde el lector.
- Descargas verificadas, pausa, prioridad, reintentos limitados, concurrencia y límite de velocidad.
- Servicio de descargas de Android independiente de la pantalla.
- Lector RTL/LTR, doble página con portada separada, webtoon continuo y ajustes por obra.
- Previsualización de página al arrastrar; salto al soltar, regreso tras saltos grandes y tarjeta de fin de capítulo.
- Ajustes desde el lector y selector de capítulos con búsqueda y salto al actual.
- Gestión de almacenamiento, importación CBZ/ZIP con cancelación y backups con vista previa.
- Reparación por página y búsqueda del capítulo en otras fuentes con selección explícita.
- Novedades de favoritos y próximos capítulos descargados según red, batería y cuota.
- Marcadores, recorte opcional de márgenes y orientación por obra.
- Copias diarias rotativas, restauración y exportación desde Perfil → Ajustes → Biblioteca → Automatización y copias.
- MyAnimeList para manga: búsqueda por nombre, ID o URL; estado y capítulos leídos manuales o sincronización automática opcional por obra.
- Traducción manual de imágenes en el lector online de Android: idiomas seleccionables, comparación de texto y regreso al original. Usa Google Translate mediante ML Kit en el teléfono. [Uso y límites](docs/reader/TRADUCCION_LECTOR.md).

## MyAnimeList

Desde Perfil → MyAnimeList · Manga conecta la cuenta en el navegador. Para sincronizar un manga concreto, abre su ficha o el menú del lector, busca la obra y confirma el vínculo. Activa «Enviar progreso al terminar capítulos» si quieres sincronización automática. La aplicación conserva los envíos pendientes sin conexión y permite reintentarlos; solo envía capítulos con número entero conocido y no reduce el progreso existente. La ficha muestra la última confirmación conocida de capítulos y estado, cuándo se consultó y los envíos pendientes. «Consultar estado en MAL» consulta la cuenta sin modificar tu progreso local. Las copias guardan los vínculos, pero no las credenciales ni esta caché de estado.

El perfil muestra automáticamente el nombre, `@usuario` y foto de la cuenta MAL conectada. La imagen usa la caché de la app; si no está disponible, muestra la foto local o el icono de perfil. Al desconectar se recuperan el nombre y la foto locales anteriores. Las sesiones ya conectadas reciben la imagen al actualizar su estado, sin volver a autorizar.

La conexión requiere el servicio de `server/` instalado en el alojamiento privado de YomaTV. `python tools/install_mal_backend.py --web-root RUTA_A_YOMATVWEB` prepara la extensión en su código existente; después se publica con el procedimiento de releases del sitio. Usa el callback registrado del sitio y mantiene el secreto de cliente y los tokens de MAL en el servidor cifrados; Android guarda una credencial de dispositivo cifrada con Android Keystore. No incluyas secretos de configuración ni claves de firma en GitHub. El servidor necesita HTTPS, PHP con OpenSSL y cURL, y acceso a su base de datos. Referencia: [API de MyAnimeList](https://myanimelist.net/apiconfig/references/api/v2).

Documentación:
- [Índice y organización del repositorio](docs/README.md)
- [Arquitectura y flujos](docs/architecture/ESTRUCTURA.md)
- [Implementación de los 49 puntos del informe](docs/releases/IMPLEMENTACION.md)
- [Mejoras 2.2, validación y APK personal](docs/releases/MEJORAS_2_2.md)
- [MyAnimeList 2.3, sincronización y despliegue](docs/releases/MEJORAS_2_3.md)
- [Interfaz 2.4, accesibilidad y comprobaciones](docs/releases/MEJORAS_2_4.md)
- [Experiencia 2.5, biblioteca unificada y controles](docs/releases/MEJORAS_2_5.md)
- [Traducción de imágenes online, uso y verificación](docs/reader/TRADUCCION_LECTOR.md)

## Organización del proyecto

El código de la app está en `lib/`; la documentación, en `docs/`; y las pruebas locales se agrupan en `test/unit/`, `test/services/` y `test/widgets/`. Las pruebas opcionales con servicios reales están en `test/live/` y las del servidor en `test/backend/`. [Guía de pruebas](test/README.md).

Las herramientas de mantenimiento permanecen en `tools/`. Los registros históricos, notas, parches y copias de diagnóstico están ordenados en `build/reports/`. Flutter conserva sus salidas en `build/app/outputs/`.

## Desarrollo

Entorno de validación: Flutter 3.47.5 estable, Dart 3.13.4, JDK 17. El SDK mínimo de Dart declarado en el proyecto se conserva.

    flutter pub get
    dart format --output=none --set-exit-if-changed lib test integration_test test_driver
    flutter analyze
    flutter test
    flutter build apk --debug

El APK de desarrollo se genera en build/app/outputs/flutter-apk/app-debug.apk. La validación automatizada está en .github/workflows/flutter.yml.

Para uso personal, el APK ARM64 optimizado se compila con `flutter build apk --release --target-platform android-arm64 --split-per-abi --dart-define=YOMASHI_PERSONAL_RELEASE=true`. Este indicador explícito conserva el certificado de depuración existente para permitir actualizar la instalación actual. Conserva ese keystore para futuras actualizaciones. Flutter añade un desplazamiento por ABI al código de versión: el APK ARM64 de 2.5.0+9 utiliza 2009. Las siguientes actualizaciones deben usar el mismo comando y aumentar el número de compilación; evita sustituirlo por un APK universal con un código inferior.

Para otra firma, configura android/key.properties o las variables YOMASHI_KEYSTORE, YOMASHI_STORE_PASSWORD, YOMASHI_KEY_ALIAS y YOMASHI_KEY_PASSWORD. Las credenciales se excluyen del control de versiones. Sin firma ni indicador personal explícito, release falla.

Los APK finales se publican como archivos de GitHub Releases junto con su SHA-256. Después de verificar el APK personal, usa `python tools/publish_apk.py --apk build/app/outputs/flutter-apk/YomaShi-VERSION-arm64.apk --notes-file NOTAS.md --target COMMIT`. El script utiliza la sesión de Git Credential Manager, sube los archivos a una Release en borrador, verifica su contenido y la publica. No reemplaza archivos ya publicados con contenido diferente. Las claves de firma y las credenciales de GitHub no se guardan en el repositorio.

Pruebas físicas: `pwsh -File tools/verify_android.ps1 -Device IDENTIFICADOR -Mode profile`. Se construye una app `app.yomashi.reader.qa`; el script comprueba el identificador del APK antes de instalarlo y usa ese mismo binario en Flutter Drive. No ejecutes `flutter test integration_test` sobre la aplicación personal. No ejecutes compilaciones Flutter simultáneas en este mismo directorio.

Las tareas programadas usan WorkManager cada 12 horas; Android determina cuándo ejecutarlas. Las copias se crean como máximo una vez al día salvo petición manual. Con permiso de archivos se guardan en `/storage/emulated/0/YomaShi/Backups`; sin él se usa almacenamiento privado y conviene exportarlas. Las descargas automáticas empiezan desactivadas y nunca borran mangas para liberar espacio.

## Compatibilidad y datos existentes

Las carpetas antiguas continúan siendo legibles. Perfil → Ajustes → Biblioteca → Almacenamiento permite incorporar manifiestos sin cambiar sus rutas. Los archivos cuyo origen no se puede demostrar se conservan como biblioteca local; no se adjudican automáticamente a una fuente ni se consideran descargas verificadas.

Las nuevas descargas usan identificadores estables y manifiestos. Cambiar la carpeta predeterminada afecta a trabajos nuevos. En Descargas puede copiarse un trabajo a otro destino: se pausa, se verifica la copia y se conserva el origen.

En Android el servicio usa foreground dataSync y una notificación con acción de pausa. Android puede imponer límites de ejecución y restricciones del fabricante; al alcanzar el timeout se guarda y pausa la cola. Consulta los [límites oficiales de servicios de Android](https://developer.android.com/develop/background-work/services/fgs/timeout).

Los tests de fuentes usan respuestas locales controladas. Además, se probaron los cuatro sitios reales, descargas, pausa, lectura local, rotación y pantalla apagada en un POCO X6 Pro con Android 16; los resultados y límites están en [PRUEBAS_TELEFONO.md](docs/testing/PRUEBAS_TELEFONO.md). No se ha añadido un servicio equivalente en iOS.
