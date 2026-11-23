import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tokens de diseño: "tablero de la casa".
/// Muro de yeso frío, placas de interruptor blancas, tinta pizarra.
/// Un solo acento con presencia: el ámbar del foco encendido.
class Paleta {
  const Paleta({
    required this.muro,
    required this.placa,
    required this.tinta,
    required this.tenue,
    required this.linea,
    required this.foco,
    required this.ventilador,
    required this.ahorro,
    required this.alarma,
  });
  final Color muro, placa, tinta, tenue, linea, foco, ventilador, ahorro, alarma;

  static const claro = Paleta(
    muro: Color(0xFFE6EAE8),
    placa: Color(0xFFFBFCFB),
    tinta: Color(0xFF1E2A2F),
    tenue: Color(0xFF65767C),
    linea: Color(0xFFD3DAD7),
    foco: Color(0xFFF2A900),
    ventilador: Color(0xFF2B6FD6),
    ahorro: Color(0xFF23895C),
    alarma: Color(0xFFD23A3F),
  );

  static const oscuro = Paleta(
    muro: Color(0xFF141B1E),
    placa: Color(0xFF1E272B),
    tinta: Color(0xFFE5ECEA),
    tenue: Color(0xFF93A3A8),
    linea: Color(0xFF2E3A3F),
    foco: Color(0xFFFFBE2E),
    ventilador: Color(0xFF6AA3FF),
    ahorro: Color(0xFF4CC38E),
    alarma: Color(0xFFFF6B6F),
  );
}

class TemaPaleta extends InheritedWidget {
  const TemaPaleta({super.key, required this.p, required super.child});
  final Paleta p;
  static Paleta of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<TemaPaleta>()!.p;
  @override
  bool updateShouldNotify(TemaPaleta old) => old.p != p;
}

ThemeData construirTema(Paleta p, Brightness b) {
  final base = ThemeData(brightness: b, useMaterial3: true);
  final cuerpo = GoogleFonts.publicSansTextTheme(base.textTheme)
      .apply(bodyColor: p.tinta, displayColor: p.tinta);
  return base.copyWith(
    scaffoldBackgroundColor: p.muro,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.foco,
      brightness: b,
      surface: p.placa,
    ),
    textTheme: cuerpo,
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      inactiveTrackColor: p.linea,
      overlayShape: SliderComponentShape.noOverlay,
    ),
  );
}

/// Cifras grandes: Archivo, con números tabulares.
TextStyle cifra(BuildContext c, double size, {Color? color, FontWeight? w}) =>
    GoogleFonts.archivo(
      fontSize: size,
      fontWeight: w ?? FontWeight.w600,
      color: color ?? TemaPaleta.of(c).tinta,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.0,
      letterSpacing: -0.5,
    );

TextStyle titulo(BuildContext c, double size) => GoogleFonts.archivo(
      fontSize: size,
      fontWeight: FontWeight.w700,
      color: TemaPaleta.of(c).tinta,
      letterSpacing: -0.3,
    );
