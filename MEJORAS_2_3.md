# YomaShi 2.3.0 — MyAnimeList para manga

## Uso

- Perfil → MyAnimeList · Manga → Conectar cuenta. La autorización se abre en el navegador; comprueba el código y vuelve a YomaShi al terminar.
- Busca por nombre, ID numérico o enlace `https://myanimelist.net/manga/ID/Titulo`.
- Selecciona un resultado para editar capítulos leídos y estado: leyendo, completado, en pausa, abandonado o por leer.
- Desde la ficha de una obra o el menú del lector puedes confirmar su vínculo con un resultado MAL y activar el envío automático al terminar capítulos.
- Los envíos automáticos conservan el mayor progreso existente. Se conservan los estados completado, en pausa y abandonado. Una obra se completa automáticamente solo cuando MAL confirma que terminó y se alcanza su total conocido.
- Los especiales fraccionarios y los capítulos sin número confirmado se omiten. En ediciones con numeraciones distintas, usa la actualización manual.
- La lectura local se guarda aunque la red falle. Los trabajos pendientes usan reintentos limitados y pueden reenviarse manualmente desde la pantalla MAL. No se envían trabajos de otra cuenta ni de un vínculo reemplazado.
- Desmarcar un capítulo local no reduce el contador remoto; puedes corregirlo manualmente en MAL.
- Las copias v4 incluyen vínculos por cuenta. La restauración sigue aceptando las versiones 1, 2 y 3. Las credenciales no se exportan.

## Servidor y despliegue

Esta extensión utiliza la aplicación OAuth de tipo web ya configurada en el alojamiento de YomaTV y su callback `https://hk-br035.gt.tc/seasonav1/mal-callback.php`.

Android solo recibe una credencial de dispositivo. Se cifra con AES-GCM y una clave de Android Keystore; la sustitución condicional impide que respuestas de sesiones antiguas borren una conexión nueva. El servidor conserva cifrados los tokens MAL y protege el secreto de cliente en su configuración privada existente. OAuth usa PKCE y estado ligado a la sesión del navegador, con caducidad y uso único.

Instalar en el código del sitio existente:

```sh
python tools/install_mal_backend.py --web-root RUTA_A_YOMATVWEB
python test/backend/test_myanimelist.py
```

El instalador es idempotente. Añade las rutas de manga al adaptador MAL, extiende las listas de rutas públicas del publicador e incorpora los endpoints y la tabla privada `sa1_yomashi_devices`. El callback distingue los estados de YomaShi mediante el prefijo `ys_` y conserva el flujo de anime del sitio.

Publicar después con el procedimiento existente del sitio: copia de seguridad cifrada y verificada, release inmutable, validación de salud y cambio atómico de versión. No subir configuraciones privadas ni claves de firma al repositorio.

El 27 de octubre de 2026 el despliegue quedó pendiente porque el certificado de `ftpupload.net:21` venció a las 17:59:59, hora de Ciudad de México. La conexión se rechazó antes del login. El proveedor debe renovar el certificado antes de repetir la copia y publicación; la implementación local no desactiva TLS.

## Verificación

Las pruebas de Flutter cubren búsquedas por nombre/ID/URL, estados, validación, cola sin conexión, reintentos, alias de capítulos locales y remotos, cambio de cuenta, respuestas antiguas, envíos concurrentes, capítulos especiales y backups sin credenciales. Las pruebas HTTP ejecutan los endpoints PHP con un proveedor MAL local: sesión, CSRF, PKCE, callback, cifrado, tokens de renovación rotativos, actualizaciones PATCH y límites de progreso. No modifican ninguna cuenta MAL real.

La prueba real de autorización y escritura en una cuenta queda pendiente hasta publicar el servicio web y autorizar la cuenta desde el APK.

Referencias oficiales: [OAuth de MyAnimeList](https://myanimelist.net/apiconfig/references/authorization), [API v2](https://myanimelist.net/apiconfig/references/api/v2).
