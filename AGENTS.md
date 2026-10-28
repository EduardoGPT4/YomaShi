\# Instrucciones de trabajo



\## Objetivo principal



Completa las tareas solicitadas de principio a fin. Prioriza trabajar y entregar resultados funcionales sobre explicar lo que planeas hacer.



\## Forma de actuar



\- Examina el proyecto antes de modificarlo.

\- Deduce la intención usando el código, archivos y contexto disponibles.

\- Toma decisiones razonables por tu cuenta cuando falten detalles menores.

\- Pregunta solamente cuando falte información indispensable o haya varias opciones con consecuencias importantes.

\- No detengas el trabajo para pedir confirmación sobre decisiones reversibles.

\- Si encuentras un error relacionado con la tarea, corrígelo aunque no se mencione explícitamente.

\- No abandones una tarea después de implementar solo una parte.



\## Implementación



\- Conserva la estructura y el estilo existentes.

\- Busca primero si ya existe una función, componente o patrón reutilizable.

\- Evita cambios innecesarios y dependencias nuevas sin una razón concreta.

\- Considera casos límite y posibles efectos en otras partes del sistema.

\- No inventes archivos, APIs, resultados ni comportamientos que no hayas comprobado.



\## Verificación



\- Revisa los archivos modificados.

\- Ejecuta las pruebas, compilación o análisis disponibles.

\- Si una comprobación falla, investiga y corrige la causa.

\- No afirmes que algo funciona si no pudiste verificarlo.

\- Detente cuando la tarea esté completa y suficientemente comprobada.



\## Comunicación



\- Mantén las explicaciones breves y concretas.

\- Durante el trabajo, informa únicamente hallazgos o decisiones relevantes.

\- No describas cada comando ni repitas el contenido de la solicitud.

\- Al terminar, indica:

&#x20; 1. Qué cambiaste.

&#x20; 2. Cómo lo verificaste.

&#x20; 3. Qué limitación real queda, si existe.



\## Preferencias



\- Idioma de respuesta: español.

\- Código, nombres de variables y comentarios: sigue el idioma existente en el proyecto.

\- Evita tutoriales largos salvo que se soliciten.

\- Cuando el usuario reporte un problema, intenta corregirlo directamente.



\### Restricciones técnicas



\- No hay restricciones técnicas.

## Entrega de APK en GitHub

- Publica siempre cada APK final que entregues al usuario en las Releases de https://github.com/EduardoGPT4/YomaShi.
- Entrega el enlace de descarga de GitHub, además de cualquier archivo local. No guardes APK en el historial de Git.
- Usa el APK personal firmado con el certificado existente y verifica versión, firma y pruebas antes de publicarlo. Una firma nueva de un runner de CI no permite actualizar la instalación personal.
- Usa `tools/publish_apk.py` con el APK, sus notas y el commit de código que se compiló. El publicador conserva las credenciales en memoria y verifica tamaño y SHA-256 antes de publicar la Release.
