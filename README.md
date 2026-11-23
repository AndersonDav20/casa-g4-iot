# Casa G4: sistema IoT de hogar inteligente para el ahorro de energía

Proyecto del curso Tópicos Especiales de Internet de las Cosas (UNFV, 2026-2), grupo G4.

Un ESP32 enciende la luz y el ventilador de una habitación solo cuando hay alguien y hace falta, y los apaga 20 s después de la última detección. Lee un sensor PIR, un LDR y un DHT22, decide en el propio dispositivo y publica su estado por MQTT en el broker público de HiveMQ. La app Casa G4 (Flutter, Android y web) muestra los datos en vivo y permite controlar la casa desde el celular. El prototipo corre en el simulador Wokwi.

## Contenido

| Carpeta | Qué hay |
|---|---|
| `wokwi_G4_final/` | Firmware (`sketch.ino`), circuito (`diagram.json`) y librerías (`libraries.txt`) para Wokwi |
| `app_hogar_g4/` | Código fuente de la app Casa G4 en Flutter |
| `entregables/` | APK de la app, figuras del informe, capturas de las pruebas y registro MQTT |
| `Informe técnico final G4 - Hogar inteligente IoT.docx` | Informe técnico |

## Cómo probarlo

1. En [wokwi.com](https://wokwi.com) crear un proyecto ESP32, pegar `sketch.ino` y `diagram.json` y agregar las librerías de `libraries.txt`.
2. Iniciar la simulación y esperar `[MQTT] Conectado` en el monitor serie.
3. Instalar `entregables/CasaG4.apk` en un celular Android y abrir la app. Debe decir "En vivo · ESP32 en línea".

Temas MQTT: `unfv-tei-g4/hogar/estado`, `evento`, `online` y `cmd`.

## Integrantes

Ayala García, Yeremi Israel · Hancco Modragon, Anderson David · Miraval Verástegui, Christopher Jair · Sandoval Sulca, Jeremy Juan José · Soto López, Yesenia Andrea · Wong Gamarra, Adriano Nicolás
