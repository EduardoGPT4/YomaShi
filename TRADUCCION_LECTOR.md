# Traducción de páginas online

En Android, abre un capítulo online y entra en **Más opciones de lectura → Traducir página**. Selecciona el idioma de la imagen y el de destino, pulsa **Traducir con Google** y después **Ver en el lector**. El cambio afecta a la página elegida, no a todo el capítulo automáticamente. En doble página puedes elegir cualquiera de las dos páginas visibles.

La opción no aparece en capítulos locales, descargas ni plataformas distintas de Android. Los capítulos online pueden reutilizar su caché de imágenes habitual.

## Funcionamiento

- Reconocimiento de texto con los modelos incluidos de Google ML Kit para escritura latina, japonesa, china y coreana.
- Traducción en el dispositivo con Google Translate mediante ML Kit. No requiere una clave de API, cuenta de pago ni cambios en el servidor de MyAnimeList.
- Idiomas disponibles: japonés, chino, coreano, inglés, español, portugués, francés, alemán e italiano. El idioma de origen se elige manualmente.
- Los modelos de traducción se descargan la primera vez. De forma predeterminada solo se descargan por Wi-Fi; el usuario puede permitir otras redes. Se pueden borrar desde **Eliminar modelos descargados** sin borrar la biblioteca.
- Las páginas no se envían a un servidor de traducción. La descarga de modelos y el comportamiento del SDK de ML Kit se rigen por la documentación de Google.
- La traducción se pinta en una copia PNG temporal y funciona con los visores existentes, incluidos zoom, doble página y webtoon. No se sobrescribe la imagen original ni se cambian las páginas descargadas.
- **Comparar original y traducción** muestra todos los bloques detectados. Si un texto no cabe de forma legible sobre la imagen, se conserva el dibujo y se indica que ese bloque se puede leer en la comparación.
- La atribución a Google Translate permanece visible mientras se muestra una página traducida. **Ver original** restaura las páginas visibles. Volver a abrir la traducción permite reutilizar su copia durante esa sesión.
- La caché usa la URL y ambos idiomas como clave; mantiene como máximo ocho resultados y aproximadamente 64 MiB por lector. Al cerrar el lector se eliminan las copias temporales creadas por esa sesión.
- Cancelar, cerrar la hoja o cerrar el lector descarta resultados tardíos. Una descarga compartida de modelos puede continuar en el SDK; el resultado cancelado no se aplica al lector.

## Límites

Es una traducción automática de apoyo y puede contener errores. Consulta el original cuando haya dudas. No reconstruye el dibujo bajo las letras: usa fondos blancos dentro de los bloques reconocidos. Las fuentes estilizadas, onomatopeyas y escritura vertical pueden reconocerse mal. Se traduce por bloque, sin el contexto de todo el capítulo.

Para contener el uso de memoria, las imágenes se normalizan a un máximo de 2048 píxeles de ancho, 16384 de alto y unos ocho megapíxeles. No se aceptan originales mayores de 40 MiB ni páginas con más de 128 bloques o 16000 caracteres detectados. Las páginas webtoon muy largas pueden perder precisión al reducirse. La primera descarga requiere conexión; después los modelos permanecen en el dispositivo hasta que se eliminen.

El lector mantiene su número de página al aplicar la traducción. En webtoon vuelve al inicio de esa página; no conserva la posición exacta dentro de la imagen ni el nivel de zoom anterior.

## Verificación

Las pruebas de `test/page_translation_test.dart` usan imágenes de prueba y respuestas del canal nativo controladas: comprueban composición, conservación del original, claves de caché por idioma, cancelación, reintento, ausencia de texto, reducción de imágenes largas, idiomas guardados y controles en pantalla pequeña con texto ampliado.

    flutter analyze
    flutter test test/page_translation_test.dart test/reader_ui_ux_test.dart test/reader_widget_regression_test.dart
    flutter test

La prueba `integration_test/translation_device_test.dart` utiliza OCR y traducción reales de ML Kit en Android. Genera una página de prueba en inglés, la traduce a español, compara la imagen original, comprueba la caché y una página sin texto, aplica y restaura la traducción en el lector desde la página 2 de 3 y elimina los modelos descargados. Solo sustituye las páginas del catálogo por una muestra local; no simula las respuestas nativas de reconocimiento ni traducción. Comprueba el identificador `app.yomashi.reader.qa` antes de preparar sus datos.

Para ejecutar la prueba nativa, compila en modo profile con `--target=integration_test/translation_device_test.dart --dart-define=YOMASHI_QA=true`. Verifica con `aapt dump badging` que el APK tiene el identificador de QA y pásalo a `flutter drive --profile --no-dds --driver=test_driver/integration_test.dart --target=integration_test/translation_device_test.dart --use-application-binary=build/app/outputs/flutter-apk/app-profile.apk -d DISPOSITIVO`. El informe se guarda en `build/integration_reports/`; usa un dispositivo o emulador de pruebas con Internet para descargar los modelos.

La batería completa pasó con 177 pruebas correctas y dos omitidas, y el análisis de Dart no encontró incidencias. La prueba nativa completa pasó en un emulador Android 15 (API 35): reconoció y tradujo tres bloques de inglés a español, aplicó y restauró la imagen conservando la página 2/3, verificó la caché y una página sin texto, conservó los bytes originales y eliminó los modelos descargados. El informe de esta ejecución está en `build/integration_reports/translation-2.6.0.json`. No se ha probado la calidad de reconocimiento de mangas reales ni de texto japonés vertical en un teléfono durante este cambio.

El APK personal usa la firma existente y se compila en ARM64 con `--release --target-platform android-arm64 --split-per-abi --dart-define=YOMASHI_PERSONAL_RELEASE=true`. La versión 2.6.0+10 tiene código de versión ARM64 2010. Las dependencias de OCR y traducción aumentan su tamaño respecto a 2.5.0.

## Referencias

- [Reconocimiento de texto en Android](https://developers.google.com/ml-kit/vision/text-recognition/v2/android).
- [Traducción y gestión de modelos en Android](https://developers.google.com/ml-kit/language/translation/android).
- [ML Kit y privacidad](https://developers.google.com/ml-kit/terms).
- [ML Kit: condiciones y atribución de Google Translate](https://developers.google.com/ml-kit/language/translation/translation-terms).

La imagen de Google utilizada en la atribución procede del [recurso oficial de marca](https://www.gstatic.com/images/branding/googlelogo/1x/googlelogo_color_42x16dp.png); no se ha modificado.
