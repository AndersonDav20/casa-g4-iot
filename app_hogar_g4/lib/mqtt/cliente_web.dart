import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

MqttClient crearCliente(String host, String id) {
  final c = MqttBrowserClient('wss://$host/mqtt', id);
  c.port = 8884;
  c.keepAlivePeriod = 30;
  c.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  return c;
}
