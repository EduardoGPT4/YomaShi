# YomaShi

Aplicación Flutter para explorar, descargar y leer manga desde InManga, MangaDex, zonatmo.org y zonatmo.to, además de una biblioteca local. Se conserva el conector adicional de ManhwaWeb que ya incluía el proyecto.

- Búsqueda con selección de fuentes, resultados y paginación independientes.
- Capítulos por bloques para series largas; continuidad y reanudación desde el lector.
- Descargas verificadas, pausa, prioridad, reintentos limitados, concurrencia y límite de velocidad.
- Servicio de descargas de Android independiente de la pantalla.
- Lector RTL/LTR, doble página con portada separada, webtoon continuo y ajustes por obra.
- Gestión de almacenamiento, importación CBZ/ZIP con cancelación y backups con vista previa.
- Reparación por página y búsqueda del capítulo en otras fuentes con selección explícita.
- Novedades de favoritos y próximos capítulos descargados según red, batería y cuota.
- Marcadores, recorte opcional de márgenes y orientación por obra.
- Copias diarias rotativas, restauración y exportación desde Perfil → Automatización y copias.
- MyAnimeList para manga: búsqueda por nombre, ID o URL; estado y capítulos leídos manuales o sincronización automática opcional por obra.

## MyAnimeList

Desde Perfil → MyAnimeList · Manga conecta la cuenta en el navegador. Para sincronizar un manga concreto, abre su ficha o el menú del lector, busca la obra y confirma el vínculo. Activa «Enviar progreso al terminar capítulos» si quieres sincronización automática. La aplicación conserva los envíos pendientes sin conexión y permite reintentarlos; solo envía capítulos con número entero conocido y no reduce el progreso existente. Las copias guardan los vínculos, pero no las credenciales.

La conexión requiere el servicio de `server/` instalado en el alojamiento privado de YomaTV. `python tools/install_mal_backend.py --web-root RUTA_A_YOMATVWEB` prepara la extensión en su código existente; después se publica con el procedimiento de releases del sitio. Usa el callback registrado del sitio y mantiene el secreto de cliente y los tokens de MAL en el servidor cifrados; Android guarda una credencial de dispositivo cifrada con Android Keystore. No incluyas secretos de configuración ni claves de firma en GitHub. El servidor necesita HTTPS, PHP con OpenSSL y cURL, y acceso a su base de datos. Referencia: [API de MyAnimeList](https://myanimelist.net/apiconfig/references/api/v2).

Documentación:
- [Arquitectura y flujos](ESTRUCTURA.md)
- [Implementación de los 49 puntos del informe](IMPLEMENTACION.md)
- [Mejoras 2.2, validación y APK personal](MEJORAS_2_2.md)
- [MyAnimeList 2.3, sincronización y despliegue](MEJORAS_2_3.md)

## Desarrollo

Entorno de validación: Flutter 3.47.5 estable, Dart 3.13.4, JDK 17. El SDK mínimo de Dart declarado en el proyecto se conserva.

    flutter pub get
    dart format --output=none --set-exit-if-changed lib test integration_test test_driver
    flutter analyze
    flutter test
    flutter build apk --debug

El APK de desarrollo se genera en build/app/outputs/flutter-apk/app-debug.apk. La validación automatizada está en .github/workflows/flutter.yml.

Para uso personal, el APK ARM64 optimizado se compila con `flutter build apk --release --target-platform android-arm64 --split-per-abi --dart-define=YOMASHI_PERSONAL_RELEASE=true`. Este indicador explícito conserva el certificado de depuración existente para permitir actualizar la instalación actual. Conserva ese keystore para futuras actualizaciones. Flutter añade un desplazamiento por ABI al código de versión: el APK ARM64 de 2.3.0+4 utiliza 2004. Las siguientes actualizaciones deben usar el mismo comando y aumentar el número de compilación; evita sustituirlo por un APK universal con un código inferior.

Para otra firma, configura android/key.properties o las variables YOMASHI_KEYSTORE, YOMASHI_STORE_PASSWORD, YOMASHI_KEY_ALIAS y YOMASHI_KEY_PASSWORD. Las credenciales se excluyen del control de versiones. Sin firma ni indicador personal explícito, release falla.

Pruebas físicas: `pwsh -File tools/verify_android.ps1 -Device IDENTIFICADOR -Mode profile`. Se construye una app `app.yomashi.reader.qa`; el script comprueba el identificador del APK antes de instalarlo y usa ese mismo binario en Flutter Drive. No ejecutes `flutter test integration_test` sobre la aplicación personal. No ejecutes compilaciones Flutter simultáneas en este mismo directorio.

Las tareas programadas usan WorkManager cada 12 horas; Android determina cuándo ejecutarlas. Las copias se crean como máximo una vez al día salvo petición manual. Con permiso de archivos se guardan en `/storage/emulated/0/YomaShi/Backups`; sin él se usa almacenamiento privado y conviene exportarlas. Las descargas automáticas empiezan desactivadas y nunca borran mangas para liberar espacio.

## Compatibilidad y datos existentes

Las carpetas antiguas continúan siendo legibles. Perfil → Almacenamiento permite incorporar manifiestos sin cambiar sus rutas. Los archivos cuyo origen no se puede demostrar se conservan como biblioteca local; no se adjudican automáticamente a una fuente ni se consideran descargas verificadas.

Las nuevas descargas usan identificadores estables y manifiestos. Cambiar la carpeta predeterminada afecta a trabajos nuevos. En Descargas puede copiarse un trabajo a otro destino: se pausa, se verifica la copia y se conserva el origen.

En Android el servicio usa foreground dataSync y una notificación con acción de pausa. Android puede imponer límites de ejecución y restricciones del fabricante; al alcanzar el timeout se guarda y pausa la cola. Consulta los [límites oficiales de servicios de Android](https://developer.android.com/develop/background-work/services/fgs/timeout).

Los tests de fuentes usan respuestas locales controladas. Además, se probaron los cuatro sitios reales, descargas, pausa, lectura local, rotación y pantalla apagada en un POCO X6 Pro con Android 16; los resultados y límites están en [PRUEBAS_TELEFONO.md](PRUEBAS_TELEFONO.md). No se ha añadido un servicio equivalente en iOS.
