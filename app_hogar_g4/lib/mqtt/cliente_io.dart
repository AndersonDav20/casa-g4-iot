import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient crearCliente(String host, String id) {
  final c = MqttServerClient.withPort(host, id, 1883);
  c.keepAlivePeriod = 30;
  return c;
}
