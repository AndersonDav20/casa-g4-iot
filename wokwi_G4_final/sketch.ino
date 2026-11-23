/*
 * ================================================================
 *  SISTEMA IoT DE HOGAR INTELIGENTE PARA EL AHORRO DE ENERGÍA
 *  Curso: Tópicos Especiales de Internet de las Cosas — Grupo G4
 * ================================================================
 *  Microcontrolador : ESP32 DevKit V1 (programado con Arduino IDE)
 *  Sensores         : PIR HC-SR501 (movimiento)
 *                     LDR / fotorresistor (luminosidad, en lux)
 *                     DHT22 (temperatura y humedad)
 *  Actuadores       : Relé 1 -> iluminación de la habitación
 *                     Relé 2 -> ventilador
 *                     Buzzer -> alarma de intrusión
 *  Interfaz local   : Pantalla OLED SSD1306 128x64 + pulsador
 *  Plataforma IoT   : Blynk IoT (dashboard web + app móvil)
 *  Conectividad     : Wi-Fi 802.11 (TCP/IP) -> Blynk Cloud
 *
 *  Modos de operación
 *   - AUTOMÁTICO : la luz se enciende solo si hay presencia y poca luz
 *                  natural; el ventilador, si hay presencia y calor.
 *                  Si no hay movimiento durante TIEMPO_SIN_PRESENCIA,
 *                  todo se apaga (esto es lo que ahorra energía).
 *   - MANUAL     : la luz y el ventilador se controlan desde Blynk
 *                  o con el pulsador físico.
 *   - SEGURIDAD  : (casa vacía) cualquier movimiento activa la alarma,
 *                  enciende la luz como disuasión y envía notificación.
 *
 *  El sistema sigue funcionando en local aunque se pierda Internet.
 * ================================================================
 */
// ---------- 1. Credenciales de Blynk (copiar desde Blynk.Console) ----------
// Deben ir ANTES de incluir la librería de Blynk.
#define BLYNK_TEMPLATE_ID   "TMPLxxxxxxxxx"
#define BLYNK_TEMPLATE_NAME "Hogar Inteligente G4"
#define BLYNK_AUTH_TOKEN    "PEGAR_AQUI_EL_AUTH_TOKEN"
#define BLYNK_PRINT Serial          // mensajes de Blynk en el monitor serie
#include <WiFi.h>
#include <WiFiClient.h>
#include <BlynkSimpleEsp32.h>
#include <DHT.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <PubSubClient.h>
#include <math.h>
// Blynk solo se usa si se pegó un token real; si no, el sistema trabaja con MQTT + app propia
const bool BLYNK_ACTIVO = strcmp(BLYNK_AUTH_TOKEN, "PEGAR_AQUI_EL_AUTH_TOKEN") != 0;
// ---------- 1b. MQTT: enlace con la app móvil / web del grupo (Flutter) ----------
// Broker público HiveMQ. ESP32 usa TCP 1883; la app usa WebSocket seguro (wss 8884).
const char MQTT_HOST[]   = "broker.hivemq.com";
const int  MQTT_PORT     = 1883;
const char T_ESTADO[]    = "unfv-tei-g4/hogar/estado";   // ESP32 -> app (JSON, retenido)
const char T_EVENTO[]    = "unfv-tei-g4/hogar/evento";   // ESP32 -> app (alertas)
const char T_ONLINE[]    = "unfv-tei-g4/hogar/online";   // "1" / "0" (última voluntad)
const char T_CMD[]       = "unfv-tei-g4/hogar/cmd";      // app -> ESP32 ("luz=1", "umbLux=300"...)
WiFiClient netMqtt;
PubSubClient mqtt(netMqtt);
// ---------- 2. Red Wi-Fi ----------
// En Wokwi se usa la red virtual "Wokwi-GUEST" (sin contraseña).
// En un ESP32 físico, reemplazar por la red de la casa.
const char WIFI_SSID[] = "Wokwi-GUEST";
const char WIFI_PASS[] = "";
const int  WIFI_CANAL  = 6;         // en Wokwi, fijar el canal acelera la conexión
// ---------- 3. Pines ----------
const int PIN_PIR      = 27;        // salida digital del sensor PIR
const int PIN_LDR      = 34;        // salida analógica (AO) del módulo LDR (ADC1)
const int PIN_DHT      = 4;         // dato del DHT22
const int PIN_RELE_LUZ = 26;        // IN del relé de iluminación
const int PIN_RELE_VEN = 25;        // IN del relé del ventilador
const int PIN_BUZZER   = 13;        // buzzer de alarma
const int PIN_BOTON    = 14;        // pulsador manual (a GND, con pull-up interno)
const int PIN_LED_NET  = 2;         // LED integrado: indica conexión con Blynk
// Relé activo en ALTO (por defecto en Wokwi y en la mayoría de módulos con transistor NPN).
// Si en tu simulación o módulo físico el foco funciona "al revés", cambia esto a false.
const bool RELE_ACTIVO_EN_ALTO = true;
// OLED por I2C: SDA = GPIO21, SCL = GPIO22 (pines I2C por defecto del ESP32)
// ---------- 4. Pines virtuales de Blynk (datastreams) ----------
// V0 Temperatura (°C)     V1 Humedad (%)          V2 Luminosidad (lux)
// V3 Presencia (0/1)      V4 Luz (switch)         V5 Ventilador (switch)
// V6 Modo automático      V7 Modo seguridad       V8 Energía consumida (Wh)
// V9 Ahorro energético %  V10 Umbral de luz (lux) V11 Umbral temperatura (°C)
// ---------- 5. Parámetros del sistema ----------
const unsigned long TIEMPO_SIN_PRESENCIA = 20000UL; // ms sin movimiento para "habitación vacía"
                                                    // (20 s para la demo; en una casa real: 5 min)
const unsigned long INTERVALO_SENSORES   = 2000UL;  // el DHT22 necesita >= 2 s entre lecturas
const unsigned long INTERVALO_RESPALDO   = 60000UL; // envío completo de respaldo aunque nada cambie
// Envío por cambio: una medición se manda al instante solo si cambió de verdad
const float CAMBIO_TEMP = 0.5;                      // °C
const float CAMBIO_HUM  = 2.0;                      // % de humedad
const float CAMBIO_LUX  = 0.10;                     // 10 % del último valor enviado (mínimo 5 lux)
const unsigned long INTERVALO_ENERGIA    = 30000UL; // envío de energía y ahorro
const unsigned long PAUSA_EVENTOS        = 60000UL; // mínimo entre notificaciones del mismo tipo
const float HISTERESIS_TEMP = 0.5;                  // °C, evita que el ventilador "tiemble"
const float TEMP_ALERTA     = 35.0;                 // °C, envía evento de temperatura alta
const float POTENCIA_LUZ_W  = 60.0;                 // carga de iluminación de la habitación (W)
const float POTENCIA_VEN_W  = 45.0;                 // ventilador de pie típico (W)
// Constantes del fotorresistor de Wokwi (módulo con resistencia de 10 kΩ)
const float LDR_GAMMA = 0.7;
const float LDR_RL10  = 50.0;       // kΩ a 10 lux
const float VREF      = 3.3;
// ---------- 6. Objetos ----------
DHT dht(PIN_DHT, DHT22);
Adafruit_SSD1306 oled(128, 64, &Wire, -1);
BlynkTimer timer;
// ---------- 7. Estado del sistema ----------
float temperatura = NAN, humedad = NAN, lux = 0;
bool  presencia = false;            // hubo movimiento en los últimos TIEMPO_SIN_PRESENCIA ms
bool  pirAnterior = false;
unsigned long ultimoMovimiento = 0;
bool modoAuto      = true;
bool modoSeguridad = false;
bool luzEncendida  = false;
bool venEncendido  = false;
bool luzManual     = false;         // lo que pidió el usuario en modo manual
bool venManual     = false;
int   umbralLux  = 200;             // por debajo de esto se considera "oscuro"
float umbralTemp = 28.0;            // por encima se enciende el ventilador
bool  alarmaActiva = false;
unsigned long inicioAlarma = 0;
unsigned long ultimoEventoIntruso = 0, ultimoEventoTemp = 0;
// Energía: tiempo encendido de cada carga y tiempo total en marcha
unsigned long msLuzOn = 0, msVenOn = 0, ultimoConteo = 0, inicioSistema = 0;
// Último valor enviado a Blynk (para no reenviar lo mismo)
int  enviadoPresencia = -1, enviadoLuz = -1, enviadoVen = -1;
float enviadoTemp = NAN, enviadoHum = NAN, enviadoLux = NAN;
bool oledOk = false;
// Prototipos (Arduino IDE los genera solo, pero así queda explícito)
void dispararAlarma();
void decidirActuadores();
void publicarEvento(const char* tipo, const char* msg);
void escribirRele(int pin, bool encender);
// ================================================================
//  Lectura de sensores
// ================================================================
float leerLux() {
  int adc = analogRead(PIN_LDR);                  // 0..4095 (12 bits)
  float v = adc / 4095.0 * VREF;
  if (v >= VREF - 0.001) return 0.1;              // oscuridad total
  if (v <= 0.001)        return 100000.0;         // saturado
  float r = 10000.0 * v / (VREF - v);             // resistencia del LDR (Ω)
  return pow(LDR_RL10 * 1e3 * pow(10, LDR_GAMMA) / r, 1.0 / LDR_GAMMA);
}
void leerSensores() {
  float t = dht.readTemperature();                // °C
  float h = dht.readHumidity();                   // %
  if (!isnan(t) && !isnan(h)) {
    temperatura = t;
    humedad     = h;
  } else {
    Serial.println("[DHT22] Error de lectura");   // se conserva el último valor válido
  }
  lux = leerLux();
}
void leerPIR() {
  bool pir = digitalRead(PIN_PIR) == HIGH;
  unsigned long ahora = millis();
  if (pir) ultimoMovimiento = ahora;
  bool flancoSubida = pir && !pirAnterior;
  pirAnterior = pir;
  presencia = (ultimoMovimiento != 0) && (ahora - ultimoMovimiento < TIEMPO_SIN_PRESENCIA);
  if (flancoSubida && modoSeguridad) dispararAlarma();
}
// ================================================================
//  Lógica de control
// ================================================================
void dispararAlarma() {
  alarmaActiva = true;
  inicioAlarma = millis();
  Serial.println("[SEGURIDAD] ¡Movimiento detectado con la casa vacía!");
  publicarEvento("intruso", "Se detecto movimiento con el modo seguridad activo");
  if (Blynk.connected() && (ultimoEventoIntruso == 0 || millis() - ultimoEventoIntruso > PAUSA_EVENTOS)) {
    Blynk.logEvent("intruso", "Se detectó movimiento con el modo seguridad activo");
    ultimoEventoIntruso = millis();
  }
}
void actualizarAlarma() {
  static int frecuenciaActual = 0;                // solo se llama a tone() si cambia
  int frecuencia = 0;
  if (alarmaActiva) {
    unsigned long t = millis() - inicioAlarma;
    if (t > 10000UL || !modoSeguridad) alarmaActiva = false;   // suena 10 s como máximo
    else frecuencia = ((t / 250) % 2) ? 1800 : 1200;           // sirena de dos tonos
  }
  if (frecuencia == frecuenciaActual) return;
  frecuenciaActual = frecuencia;
  if (frecuencia == 0) noTone(PIN_BUZZER);
  else tone(PIN_BUZZER, frecuencia);
}
void escribirRele(int pin, bool encender) {
  digitalWrite(pin, (encender == RELE_ACTIVO_EN_ALTO) ? HIGH : LOW);
}
void decidirActuadores() {
  if (modoSeguridad) {
    luzEncendida = alarmaActiva;                  // la luz disuade al intruso
    venEncendido = false;
  } else if (modoAuto) {
    bool oscuro = lux < umbralLux;
    luzEncendida = presencia && oscuro;
    if (isnan(temperatura) || !presencia) {
      venEncendido = false;
    } else if (temperatura > umbralTemp + HISTERESIS_TEMP) {
      venEncendido = true;
    } else if (temperatura < umbralTemp - HISTERESIS_TEMP) {
      venEncendido = false;
    }                                             // dentro de la banda: mantiene estado
  } else {
    luzEncendida = luzManual;
    venEncendido = venManual;
  }
  escribirRele(PIN_RELE_LUZ, luzEncendida);
  escribirRele(PIN_RELE_VEN, venEncendido);
}
void contarEnergia() {
  unsigned long ahora = millis();
  unsigned long dt = ahora - ultimoConteo;
  ultimoConteo = ahora;
  if (luzEncendida) msLuzOn += dt;
  if (venEncendido) msVenOn += dt;
}
float energiaWh() {
  return (POTENCIA_LUZ_W * msLuzOn + POTENCIA_VEN_W * msVenOn) / 3600000.0;
}
// Ahorro frente a dejar la luz encendida todo el tiempo (caso típico de olvido)
float ahorroPorcentaje() {
  unsigned long total = millis() - inicioSistema;
  if (total == 0) return 0;
  return 100.0 * (1.0 - (float)msLuzOn / (float)total);
}
void revisarTemperaturaAlta() {
  if (!isnan(temperatura) && temperatura >= TEMP_ALERTA && (Blynk.connected() || mqtt.connected())
      && (ultimoEventoTemp == 0 || millis() - ultimoEventoTemp > PAUSA_EVENTOS * 5)) {
    String msg = String("Temperatura alta: ") + String(temperatura, 1) + " C";
    if (Blynk.connected()) Blynk.logEvent("temp_alta", msg.c_str());
    publicarEvento("temp_alta", msg.c_str());
    ultimoEventoTemp = millis();
  }
}
// ================================================================
//  Pulsador físico (con antirrebote)
//   - Pulsación corta  : prende/apaga el foco y pasa a modo MANUAL
//   - Pulsación larga  : (mantener 2 s) vuelve a modo AUTOMÁTICO
// ================================================================
const unsigned long PULSACION_LARGA = 2000UL;     // ms
void leerBoton() {
  static bool estadoEstable = HIGH, lecturaAnterior = HIGH;
  static unsigned long tCambio = 0, tPresion = 0;
  static bool largaHecha = false;
  bool lectura = digitalRead(PIN_BOTON);
  if (lectura != lecturaAnterior) { tCambio = millis(); lecturaAnterior = lectura; }
  if (millis() - tCambio > 40 && lectura != estadoEstable) {
    estadoEstable = lectura;
    if (estadoEstable == LOW) {                   // se acaba de presionar
      tPresion = millis();
      largaHecha = false;
    } else if (!largaHecha) {                     // se soltó antes de 2 s: pulsación corta
      modoAuto = false;
      luzManual = !luzEncendida;
      venManual = venEncendido;
      Serial.printf("[BOTÓN] Luz %s (modo manual)\n", luzManual ? "ON" : "OFF");
      if (Blynk.connected()) Blynk.virtualWrite(V6, 0);
    }
  }
  // Sigue presionado 2 s: pulsación larga -> volver a automático
  if (estadoEstable == LOW && !largaHecha && millis() - tPresion >= PULSACION_LARGA) {
    largaHecha = true;
    modoAuto = true;
    Serial.println("[BOTÓN] Pulsación larga: modo AUTOMÁTICO");
    if (Blynk.connected()) Blynk.virtualWrite(V6, 1);
  }
}
// ================================================================
//  Comunicación con Blynk
// ================================================================
BLYNK_CONNECTED() {
  Serial.println("[BLYNK] Conectado a Blynk Cloud");
  // Recupera del servidor los ajustes guardados en el dashboard
  Blynk.syncVirtual(V6, V7, V10, V11);
  enviadoPresencia = enviadoLuz = enviadoVen = -1;   // fuerza reenvío de estados
  enviadoTemp = enviadoHum = enviadoLux = NAN;       // y de mediciones
}
// Si el usuario toca un switch estando en automático, el sistema pasa a manual
void pasarAManual() {
  if (!modoAuto) return;
  modoAuto = false;
  luzManual = luzEncendida;
  venManual = venEncendido;
  Blynk.virtualWrite(V6, 0);
  Serial.println("[BLYNK] Control desde la app: modo MANUAL");
}
BLYNK_WRITE(V4) { pasarAManual(); luzManual = param.asInt(); decidirActuadores(); }
BLYNK_WRITE(V5) { pasarAManual(); venManual = param.asInt(); decidirActuadores(); }
BLYNK_WRITE(V6) {
  modoAuto = param.asInt();
  if (!modoAuto) { luzManual = luzEncendida; venManual = venEncendido; }
  Serial.printf("[BLYNK] Modo %s\n", modoAuto ? "AUTOMÁTICO" : "MANUAL");
}
BLYNK_WRITE(V7) {
  modoSeguridad = param.asInt();
  if (!modoSeguridad) alarmaActiva = false;
  Serial.printf("[BLYNK] Modo seguridad %s\n", modoSeguridad ? "ACTIVADO" : "desactivado");
}
BLYNK_WRITE(V10) { umbralLux  = param.asInt(); }
BLYNK_WRITE(V11) { umbralTemp = param.asFloat(); }
// Estados discretos: se envían apenas cambian
void enviarEstados() {
  if (!Blynk.connected()) return;
  if (presencia != enviadoPresencia) { Blynk.virtualWrite(V3, (int)presencia);    enviadoPresencia = presencia; }
  if (luzEncendida != enviadoLuz)    { Blynk.virtualWrite(V4, (int)luzEncendida); enviadoLuz = luzEncendida; }
  if (venEncendido != enviadoVen)    { Blynk.virtualWrite(V5, (int)venEncendido); enviadoVen = venEncendido; }
}
// ¿El valor cambió lo suficiente como para avisar a la nube?
bool cambioSignificativo(float actual, float anterior, float umbral, bool relativo) {
  if (isnan(actual))   return false;              // lectura inválida: no se envía
  if (isnan(anterior)) return true;               // nunca se envió: enviar
  float diferencia = fabsf(actual - anterior);
  if (relativo) return diferencia >= fmaxf(umbral * anterior, 5.0f);
  return diferencia >= umbral;
}
// Mediciones: al instante si cambian, o todas juntas cada INTERVALO_RESPALDO
void enviarMediciones(bool forzar) {
  if (!Blynk.connected()) return;
  bool envio = false;
  if (!isnan(temperatura) && (forzar || cambioSignificativo(temperatura, enviadoTemp, CAMBIO_TEMP, false))) {
    Blynk.virtualWrite(V0, temperatura); enviadoTemp = temperatura; envio = true;
  }
  if (!isnan(humedad) && (forzar || cambioSignificativo(humedad, enviadoHum, CAMBIO_HUM, false))) {
    Blynk.virtualWrite(V1, humedad); enviadoHum = humedad; envio = true;
  }
  if (forzar || cambioSignificativo(lux, enviadoLux, CAMBIO_LUX, true)) {
    Blynk.virtualWrite(V2, (int)round(lux)); enviadoLux = lux; envio = true;
  }
  if (envio) {
    Serial.printf("[ENVÍO %s] T=%.1f°C  H=%.0f%%  Luz=%.0f lux\n",
                  forzar ? "respaldo" : "cambio", temperatura, humedad, lux);
  }
}
void enviarRespaldo() { enviarMediciones(true); }
void tareaSensores() {
  leerSensores();
  revisarTemperaturaAlta();
  enviarMediciones(false);                        // envía solo lo que cambió
}
void enviarEnergia() {
  if (!Blynk.connected()) return;
  Blynk.virtualWrite(V8, energiaWh());
  Blynk.virtualWrite(V9, ahorroPorcentaje());
}
void mantenerConexion() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WIFI] Sin conexión, reintentando...");
    WiFi.disconnect();
    WiFi.begin(WIFI_SSID, WIFI_PASS, WIFI_CANAL);
  } else if (BLYNK_ACTIVO && !Blynk.connected()) {
    Serial.println("[BLYNK] Conectando...");
    Blynk.connect(3000);                          // espera como máximo 3 s
  }
  digitalWrite(PIN_LED_NET, (Blynk.connected() || mqtt.connected()) ? HIGH : LOW);
}
// ================================================================
//  MQTT: comunicación con la app del grupo (Flutter, Android + web)
// ================================================================
void publicarEvento(const char* tipo, const char* msg) {
  if (!mqtt.connected()) return;
  char buf[160];
  snprintf(buf, sizeof(buf), "{\"tipo\":\"%s\",\"msg\":\"%s\",\"ms\":%lu}", tipo, msg, millis());
  mqtt.publish(T_EVENTO, buf);
}
// Estado completo en JSON; la app lo dibuja tal cual
String estadoJSON() {
  char t[12], h[12];
  if (isnan(temperatura)) strcpy(t, "null"); else snprintf(t, sizeof(t), "%.1f", temperatura);
  if (isnan(humedad))     strcpy(h, "null"); else snprintf(h, sizeof(h), "%.0f", humedad);
  char buf[320];
  snprintf(buf, sizeof(buf),
    "{\"t\":%s,\"h\":%s,\"lux\":%.0f,\"pres\":%d,\"luz\":%d,\"ven\":%d,\"auto\":%d,\"seg\":%d,"
    "\"alarma\":%d,\"uL\":%d,\"uT\":%.1f,\"wh\":%.3f,\"ahorro\":%.1f,\"up\":%lu}",
    t, h, lux, presencia, luzEncendida, venEncendido, modoAuto, modoSeguridad,
    alarmaActiva, umbralLux, umbralTemp, energiaWh(), ahorroPorcentaje(), millis() / 1000);
  return String(buf);
}
// Publica al instante si cambió un estado o una medición (no la energía, que cambia siempre),
// y cada 2 s como latido con la energía y el ahorro actualizados. Máximo ~5 mensajes/s.
void publicarEstado() {
  static String anterior = "";
  static unsigned long ultimo = 0;
  if (!mqtt.connected()) return;
  String actual = estadoJSON();
  String clave = actual.substring(0, actual.indexOf(",\"wh\""));
  bool cambio = clave != anterior && millis() - ultimo > 200UL;
  if (cambio || millis() - ultimo > 2000UL) {
    mqtt.publish(T_ESTADO, actual.c_str(), true);   // retenido: la app lo ve apenas abre
    anterior = clave;
    ultimo = millis();
  }
}
// Comandos de la app: "clave=valor"
void alRecibirMQTT(char* topic, byte* payload, unsigned int len) {
  String cmd;
  for (unsigned int i = 0; i < len; i++) cmd += (char)payload[i];
  int eq = cmd.indexOf('=');
  if (eq < 0) return;
  String k = cmd.substring(0, eq);
  float v = cmd.substring(eq + 1).toFloat();
  Serial.printf("[APP] Comando %s\n", cmd.c_str());
  if (k == "luz" || k == "ven") {
    if (modoAuto) { modoAuto = false; luzManual = luzEncendida; venManual = venEncendido; }
    if (k == "luz") luzManual = v > 0.5; else venManual = v > 0.5;
  } else if (k == "auto") {
    modoAuto = v > 0.5;
    if (!modoAuto) { luzManual = luzEncendida; venManual = venEncendido; }
  } else if (k == "seg") {
    modoSeguridad = v > 0.5;
    if (!modoSeguridad) alarmaActiva = false;
  } else if (k == "umbLux") {
    umbralLux = constrain((int)v, 1, 5000);
  } else if (k == "umbTemp") {
    umbralTemp = constrain(v, 10.0f, 45.0f);
  }
  decidirActuadores();
  publicarEstado();
}
void mantenerMQTT() {
  static unsigned long ultimoIntento = 0;
  if (WiFi.status() != WL_CONNECTED || mqtt.connected()) return;
  if (ultimoIntento != 0 && millis() - ultimoIntento < 5000UL) return;
  ultimoIntento = millis();
  String id = "g4-hogar-" + String((uint32_t)ESP.getEfuseMac(), HEX);
  Serial.print("[MQTT] Conectando a "); Serial.println(MQTT_HOST);
  if (mqtt.connect(id.c_str(), T_ONLINE, 0, true, "0")) {
    mqtt.publish(T_ONLINE, "1", true);
    mqtt.subscribe(T_CMD);
    Serial.println("[MQTT] Conectado: la app ya puede ver y controlar la casa");
  } else {
    Serial.printf("[MQTT] Falló (estado %d), reintento en 5 s\n", mqtt.state());
  }
}
// ================================================================
//  Pantalla OLED
// ================================================================
void actualizarOLED() {
  if (!oledOk) return;
  oled.clearDisplay();
  oled.setTextSize(1);
  oled.setTextColor(SSD1306_WHITE);
  oled.setCursor(0, 0);
  oled.print(modoSeguridad ? "SEGURIDAD" : (modoAuto ? "AUTOMATICO" : "MANUAL"));
  oled.setCursor(92, 0);
  oled.print((Blynk.connected() || mqtt.connected()) ? "Cloud" : (WiFi.status() == WL_CONNECTED ? "WiFi" : "Local"));
  oled.drawLine(0, 10, 127, 10, SSD1306_WHITE);
  oled.setCursor(0, 14);
  if (isnan(temperatura)) oled.print("T: --.- C  H: -- %");
  else oled.printf("T:%.1fC  H:%.0f%%", temperatura, humedad);
  oled.setCursor(0, 25);
  oled.printf("Luz amb: %.0f lux", lux);
  oled.setCursor(0, 36);
  oled.printf("Presencia: %s", presencia ? "SI" : "NO");
  oled.setCursor(0, 47);
  oled.printf("Foco:%s  Vent:%s", luzEncendida ? "ON " : "OFF", venEncendido ? "ON" : "OFF");
  oled.setCursor(0, 56);
  if (alarmaActiva) oled.print("!! ALARMA INTRUSO !!");
  else oled.printf("Ahorro: %.0f%%", ahorroPorcentaje());
  oled.display();
}
// ================================================================
//  setup() y loop()
// ================================================================
void setup() {
  Serial.begin(115200);
  Serial.println("\n=== Hogar Inteligente IoT - Grupo G4 ===");
  pinMode(PIN_PIR, INPUT);
  pinMode(PIN_BOTON, INPUT_PULLUP);
  pinMode(PIN_RELE_LUZ, OUTPUT);
  pinMode(PIN_RELE_VEN, OUTPUT);
  pinMode(PIN_BUZZER, OUTPUT);
  pinMode(PIN_LED_NET, OUTPUT);
  escribirRele(PIN_RELE_LUZ, false);
  escribirRele(PIN_RELE_VEN, false);
  analogReadResolution(12);
  dht.begin();
  oledOk = oled.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  if (oledOk) {
    oled.clearDisplay();
    oled.setTextSize(1);
    oled.setTextColor(SSD1306_WHITE);
    oled.setCursor(0, 20);
    oled.println("Hogar Inteligente G4");
    oled.println("Conectando WiFi...");
    oled.display();
  } else {
    Serial.println("[OLED] No se encontró la pantalla");
  }
  // Wi-Fi sin bloquear: si no hay red, el sistema funciona en modo local
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS, WIFI_CANAL);
  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 10000UL) {
    delay(250);
    Serial.print(".");
  }
  Serial.println(WiFi.status() == WL_CONNECTED ? "\n[WIFI] Conectado" : "\n[WIFI] Sin red: modo local");
  Blynk.config(BLYNK_AUTH_TOKEN);                 // no bloquea, a diferencia de Blynk.begin()
  if (BLYNK_ACTIVO && WiFi.status() == WL_CONNECTED) Blynk.connect(5000);
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(alRecibirMQTT);
  mqtt.setBufferSize(512);
  mantenerMQTT();
  inicioSistema = ultimoConteo = millis();
  leerSensores();
  timer.setInterval(INTERVALO_SENSORES, tareaSensores);
  timer.setInterval(INTERVALO_RESPALDO, enviarRespaldo);
  timer.setInterval(INTERVALO_ENERGIA, enviarEnergia);
  timer.setInterval(500L, actualizarOLED);
  timer.setInterval(10000L, mantenerConexion);
}
void loop() {
  if (Blynk.connected()) Blynk.run();
  timer.run();
  leerPIR();
  leerBoton();
  actualizarAlarma();
  decidirActuadores();
  contarEnergia();
  enviarEstados();
  mantenerMQTT();
  mqtt.loop();
  publicarEstado();
}
