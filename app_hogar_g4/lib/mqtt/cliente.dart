// Elige el cliente MQTT según la plataforma:
//  - Android / escritorio: TCP 1883
//  - Web (navegador): WebSocket seguro wss://broker.hivemq.com:8884/mqtt
export 'cliente_io.dart' if (dart.library.js_interop) 'cliente_web.dart';
