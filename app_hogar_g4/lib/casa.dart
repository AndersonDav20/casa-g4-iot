import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';

import 'mqtt/cliente.dart';

/// Temas MQTT acordados con el firmware del ESP32 (sketch.ino).
class Temas {
  static const host = 'broker.hivemq.com';
  static const base = 'unfv-tei-g4/hogar';
  static const estado = '$base/estado';
  static const evento = '$base/evento';
  static const online = '$base/online';
  static const cmd = '$base/cmd';
}

enum Conexion { conectando, conectado, desconectado }

enum Modo { automatico, manual, seguridad }

class Evento {
  Evento(this.tipo, this.mensaje) : hora = DateTime.now();
  final String tipo; // intruso, temp_alta, comando, sistema
  final String mensaje;
  final DateTime hora;
}

/// Estado de la casa tal como lo reporta el ESP32.
class EstadoCasa {
  double? temperatura;
  double? humedad;
  double lux = 0;
  bool presencia = false;
  bool luz = false;
  bool ventilador = false;
  bool auto = true;
  bool seguridad = false;
  bool alarma = false;
  double energiaWh = 0;
  double ahorro = 0;
  int umbralLux = 200;
  double umbralTemp = 28;
  int encendidoSeg = 0;

  Modo get modo =>
      seguridad ? Modo.seguridad : (auto ? Modo.automatico : Modo.manual);

  void desdeJson(Map<String, dynamic> j) {
    double? d(String k) => j[k] == null ? null : (j[k] as num).toDouble();
    bool b(String k) => (j[k] ?? 0) == 1 || j[k] == true;
    temperatura = d('t');
    humedad = d('h');
    lux = d('lux') ?? lux;
    presencia = b('pres');
    luz = b('luz');
    ventilador = b('ven');
    auto = b('auto');
    seguridad = b('seg');
    alarma = b('alarma');
    energiaWh = d('wh') ?? energiaWh;
    ahorro = d('ahorro') ?? ahorro;
    umbralLux = (j['uL'] as num?)?.toInt() ?? umbralLux;
    umbralTemp = d('uT') ?? umbralTemp;
    encendidoSeg = (j['up'] as num?)?.toInt() ?? encendidoSeg;
  }
}

/// Servicio único: conecta al broker, mantiene el estado y envía comandos.
class Casa extends ChangeNotifier {
  final estado = EstadoCasa();
  final eventos = <Evento>[];
  final histTemp = <double>[];
  final histLux = <double>[];
  final histHum = <double>[];
  Conexion conexion = Conexion.desconectado;
  bool dispositivoEnLinea = false;
  bool hayDatos = false;
  DateTime? ultimoDato;
  Evento? alertaNueva;

  MqttClient? _c;
  Timer? _reintento;
  Timer? _vigia;
  static const _maxHist = 90;

  Future<void> conectar() async {
    _reintento?.cancel();
    conexion = Conexion.conectando;
    notifyListeners();
    final id = 'app-g4-${Random().nextInt(0x7fffffff).toRadixString(16)}';
    final c = crearCliente(Temas.host, id);
    c.logging(on: false);
    c.autoReconnect = true;
    c.onConnected = () {
      conexion = Conexion.conectado;
      notifyListeners();
    };
    c.onAutoReconnected = () {
      conexion = Conexion.conectado;
      notifyListeners();
    };
    c.onDisconnected = () {
      conexion = Conexion.desconectado;
      notifyListeners();
    };
    c.connectionMessage = MqttConnectMessage().withClientIdentifier(id).startClean();
    _c = c;
    try {
      await c.connect();
    } catch (_) {
      c.disconnect();
    }
    if (c.connectionStatus?.state != MqttConnectionState.connected) {
      conexion = Conexion.desconectado;
      notifyListeners();
      _reintento = Timer(const Duration(seconds: 5), conectar);
      return;
    }
    conexion = Conexion.conectado;
    c.subscribe('${Temas.base}/#', MqttQos.atMostOnce);
    c.updates?.listen(_alRecibir);
    _vigia ??= Timer.periodic(const Duration(seconds: 2), (_) => _vigilar());
    _registrar('sistema', 'App conectada al broker MQTT');
  }

  void _vigilar() {
    // Si el ESP32 deja de mandar latidos más de 10 s, lo marcamos fuera de línea.
    if (ultimoDato != null &&
        DateTime.now().difference(ultimoDato!) > const Duration(seconds: 10) &&
        dispositivoEnLinea) {
      dispositivoEnLinea = false;
      notifyListeners();
    }
  }

  void _alRecibir(List<MqttReceivedMessage<MqttMessage>> msgs) {
    for (final m in msgs) {
      final p = m.payload as MqttPublishMessage;
      final texto = utf8.decode(p.payload.message);
      switch (m.topic) {
        case Temas.estado:
          try {
            estado.desdeJson(jsonDecode(texto) as Map<String, dynamic>);
          } catch (_) {
            continue;
          }
          hayDatos = true;
          // Un mensaje retenido viejo no prueba que el ESP32 esté vivo.
          if (!p.header!.retain) {
            ultimoDato = DateTime.now();
            dispositivoEnLinea = true;
          }
          _agregar(histTemp, estado.temperatura);
          _agregar(histLux, estado.lux);
          _agregar(histHum, estado.humedad);
        case Temas.online:
          // "0" = el broker avisó que el ESP32 se desconectó (última voluntad).
          if (texto == '0') dispositivoEnLinea = false;
        case Temas.evento:
          try {
            final j = jsonDecode(texto) as Map<String, dynamic>;
            final e = _registrar(j['tipo'] as String, _mensajeEvento(j));
            alertaNueva = e;
          } catch (_) {}
      }
    }
    notifyListeners();
  }

  String _mensajeEvento(Map<String, dynamic> j) => switch (j['tipo']) {
        'intruso' => 'Movimiento detectado con el modo seguridad activo',
        'temp_alta' => j['msg'] as String? ?? 'Temperatura alta',
        _ => j['msg'] as String? ?? '',
      };

  void _agregar(List<double> l, double? v) {
    if (v == null) return;
    l.add(v);
    if (l.length > _maxHist) l.removeAt(0);
  }

  Evento _registrar(String tipo, String msg) {
    final e = Evento(tipo, msg);
    eventos.insert(0, e);
    if (eventos.length > 40) eventos.removeLast();
    return e;
  }

  void _enviar(String comando, String descripcion) {
    final c = _c;
    if (c == null || c.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    final b = MqttClientPayloadBuilder()..addString(comando);
    c.publishMessage(Temas.cmd, MqttQos.atLeastOnce, b.payload!);
    _registrar('comando', descripcion);
    notifyListeners();
  }

  // ---- Acciones del usuario ----
  void ponerLuz(bool on) {
    estado.luz = on;
    if (estado.auto) estado.auto = false;
    _enviar('luz=${on ? 1 : 0}', on ? 'Encendiste el foco' : 'Apagaste el foco');
  }

  void ponerVentilador(bool on) {
    estado.ventilador = on;
    if (estado.auto) estado.auto = false;
    _enviar('ven=${on ? 1 : 0}',
        on ? 'Encendiste el ventilador' : 'Apagaste el ventilador');
  }

  void ponerModo(Modo m) {
    switch (m) {
      case Modo.automatico:
        if (estado.seguridad) _enviar('seg=0', 'Desactivaste el modo seguridad');
        _enviar('auto=1', 'Modo automático');
      case Modo.manual:
        if (estado.seguridad) _enviar('seg=0', 'Desactivaste el modo seguridad');
        _enviar('auto=0', 'Modo manual');
      case Modo.seguridad:
        _enviar('seg=1', 'Activaste el modo seguridad');
    }
    estado.seguridad = m == Modo.seguridad;
    estado.auto = m != Modo.manual;
    notifyListeners();
  }

  void ponerUmbralLux(int v) =>
      _enviar('umbLux=$v', 'Umbral de oscuridad: $v lux');

  void ponerUmbralTemp(double v) => _enviar(
      'umbTemp=${v.toStringAsFixed(1)}',
      'Umbral del ventilador: ${v.toStringAsFixed(1)} °C');

  void alertaVista() => alertaNueva = null;

  @override
  void dispose() {
    _reintento?.cancel();
    _vigia?.cancel();
    _c?.disconnect();
    super.dispose();
  }
}
