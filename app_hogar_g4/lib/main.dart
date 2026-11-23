import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'casa.dart';
import 'tema.dart';

void main() => runApp(const AppHogar());

class AppHogar extends StatefulWidget {
  const AppHogar({super.key});
  @override
  State<AppHogar> createState() => _AppHogarState();
}

class _AppHogarState extends State<AppHogar> {
  final casa = Casa();

  @override
  void initState() {
    super.initState();
    casa.conectar();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Casa G4',
      debugShowCheckedModeBanner: false,
      theme: construirTema(Paleta.claro, Brightness.light),
      darkTheme: construirTema(Paleta.oscuro, Brightness.dark),
      builder: (ctx, child) => TemaPaleta(
        p: Theme.of(ctx).brightness == Brightness.dark
            ? Paleta.oscuro
            : Paleta.claro,
        child: child!,
      ),
      home: Tablero(casa: casa),
    );
  }
}

// =====================================================================
//  Tablero principal
// =====================================================================
class Tablero extends StatefulWidget {
  const Tablero({super.key, required this.casa});
  final Casa casa;
  @override
  State<Tablero> createState() => _TableroState();
}

class _TableroState extends State<Tablero> {
  Casa get casa => widget.casa;

  @override
  void initState() {
    super.initState();
    casa.addListener(_avisarAlerta);
  }

  @override
  void dispose() {
    casa.removeListener(_avisarAlerta);
    super.dispose();
  }

  void _avisarAlerta() {
    final e = casa.alertaNueva;
    if (e == null || !mounted) return;
    casa.alertaVista();
    final p = TemaPaleta.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: p.alarma,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      content: Row(children: [
        Icon(e.tipo == 'intruso' ? Icons.warning_amber_rounded : Icons.thermostat,
            color: Colors.white),
        const SizedBox(width: 12),
        Expanded(
            child: Text(e.mensaje,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600))),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: casa,
          builder: (context, _) => LayoutBuilder(builder: (ctx, c) {
            final ancho = c.maxWidth >= 920;
            final izquierda = <Widget>[
              Habitacion(casa: casa),
              if (casa.estado.alarma) const BannerAlarma(),
              SelectorModo(casa: casa),
              Mediciones(casa: casa),
              Interruptores(casa: casa),
            ];
            final derecha = <Widget>[
              Energia(casa: casa),
              Umbrales(casa: casa),
              Bitacora(casa: casa),
            ];
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: CustomScrollView(slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverToBoxAdapter(child: Encabezado(casa: casa)),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverToBoxAdapter(
                      child: ancho
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 7, child: _columna(izquierda)),
                                const SizedBox(width: 16),
                                Expanded(flex: 5, child: _columna(derecha)),
                              ],
                            )
                          : _columna([...izquierda, ...derecha]),
                    ),
                  ),
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _columna(List<Widget> hijos) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < hijos.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            hijos[i],
          ]
        ],
      );
}

// =====================================================================
//  Piezas reutilizables
// =====================================================================
class Placa extends StatelessWidget {
  const Placa({super.key, required this.child, this.padding = 18, this.radio = 14});
  final Widget child;
  final double padding;
  final double radio;
  @override
  Widget build(BuildContext context) {
    final p = TemaPaleta.of(context);
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: p.placa,
        borderRadius: BorderRadius.circular(radio),
        border: Border.all(color: p.linea),
      ),
      child: child,
    );
  }
}

class Seccion extends StatelessWidget {
  const Seccion(this.texto, {super.key, this.detalle});
  final String texto;
  final String? detalle;
  @override
  Widget build(BuildContext context) {
    final p = TemaPaleta.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(texto, style: titulo(context, 17)),
          if (detalle != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(detalle!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.tenue, fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }
}

// =====================================================================
//  Encabezado con estado de conexión
// =====================================================================
class Encabezado extends StatelessWidget {
  const Encabezado({super.key, required this.casa});
  final Casa casa;
  @override
  Widget build(BuildContext context) {
    final p = TemaPaleta.of(context);
    final (Color color, String texto) = switch (casa.conexion) {
      Conexion.conectando => (p.foco, 'Conectando con la casa…'),
      Conexion.desconectado => (p.alarma, 'Sin conexión a Internet'),
      Conexion.conectado => casa.dispositivoEnLinea
          ? (p.ahorro, 'En vivo · ESP32 en línea')
          : (p.tenue,
              casa.hayDatos ? 'ESP32 sin señal · último dato guardado' : 'Esperando al ESP32'),
    };
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 10,
      spacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Casa G4', style: titulo(context, 28)),
            const SizedBox(height: 4),
            Text('Hogar inteligente para el ahorro de energía',
                style: TextStyle(color: p.tenue, fontSize: 14)),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _Pulso(color: color, activo: casa.dispositivoEnLinea),
            const SizedBox(width: 8),
            Text(texto,
                style: TextStyle(
                    color: p.tinta, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ],
    );
  }
}

class _Pulso extends StatefulWidget {
  const _Pulso({required this.color, required this.activo});
  final Color color;
  final bool activo;
  @override
  State<_Pulso> createState() => _PulsoState();
}

class _PulsoState extends State<_Pulso> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducido = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _a,
        builder: (_, __) => Stack(alignment: Alignment.center, children: [
          if (widget.activo && !reducido)
            Container(
              width: 6 + 8 * _a.value,
              height: 6 + 8 * _a.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.4 * (1 - _a.value)),
              ),
            ),
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: widget.color),
          ),
        ]),
      ),
    );
  }
}

// =====================================================================
//  Habitación: el foco que se ilumina (pieza principal)
// =====================================================================
class Habitacion extends StatelessWidget {
  const Habitacion({super.key, required this.casa});
  final Casa casa;
  @override
  Widget build(BuildContext context) {
    final p = TemaPaleta.of(context);
    final e = casa.estado;
    final ambiente = e.lux < e.umbralLux ? 'Está oscuro' : 'Hay luz natural';
    return Placa(
      radio: 22,
      padding: 22,
      child: LayoutBuilder(builder: (ctx, c) {
        final compacto = c.maxWidth < 420;
        final foco = SizedBox(
          width: compacto ? 120 : 160,
          height: compacto ? 150 : 190,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: e.luz ? 1 : 0),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOut,
            builder: (_, v, __) => CustomPaint(
              painter: FocoPainter(
                  encendido: v, ambar: p.foco, vidrio: p.linea, rosca: p.tenue),
            ),
          ),
        );
        final texto = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sala de estudio', style: TextStyle(color: p.tenue, fontSize: 14)),
            const SizedBox(height: 6),
            Text(e.luz ? 'Foco encendido' : 'Foco apagado',
                style: titulo(context, compacto ? 26 : 32)),
            const SizedBox(height: 14),
            _Chip(
              icono: e.presencia ? Icons.person : Icons.person_off_outlined,
              texto: e.presencia ? 'Hay alguien en la habitación' : 'Habitación vacía',
              color: e.presencia ? p.ventilador : p.tenue,
            ),
            const SizedBox(height: 8),
            _Chip(
              icono: e.lux < e.umbralLux
                  ? Icons.nightlight_outlined
                  : Icons.wb_sunny_outlined,
              texto: '$ambiente · ${e.lux.round()} lux',
              color: p.tenue,
            ),
          ],
        );
        return compacto
            ? Column(children: [foco, const SizedBox(height: 8), texto])
            : Row(children: [
                foco,
                const SizedBox(width: 20),
                Expanded(child: texto),
              ]);
      }),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icono, required this.texto, required this.color});
  final IconData icono;
  final String texto;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(texto,
                style: TextStyle(
                    color: TemaPaleta.of(context).tinta,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      );
}

/// Dibuja un foco: vidrio, filamento y rosca. `encendido` va de 0 a 1.
class FocoPainter extends CustomPainter {
  FocoPainter({
    required this.encendido,
    required this.ambar,
    required this.vidrio,
    required this.rosca,
  });
  final double encendido;
  final Color ambar, vidrio, rosca;

  @override
  void paint(Canvas canvas, Size s) {
    final cx = s.width / 2;
    final r = s.width * 0.36;
    final cy = r + s.height * 0.08;
    // Halo de luz
    if (encendido > 0) {
      final halo = Paint()
        ..shader = RadialGradient(colors: [
          ambar.withValues(alpha: 0.55 * encendido),
          ambar.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 2.1));
      canvas.drawCircle(Offset(cx, cy), r * 2.1, halo);
    }
    // Vidrio (círculo + cuello)
    final cuelloY = cy + r * 0.95;
    final cuerpo = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r))
      ..moveTo(cx - r * 0.62, cy + r * 0.78)
      ..quadraticBezierTo(cx - r * 0.42, cuelloY + r * 0.2, cx - r * 0.4, cuelloY + r * 0.42)
      ..lineTo(cx + r * 0.4, cuelloY + r * 0.42)
      ..quadraticBezierTo(cx + r * 0.42, cuelloY + r * 0.2, cx + r * 0.62, cy + r * 0.78)
      ..close();
    final relleno = Color.lerp(vidrio.withValues(alpha: 0.35), ambar, encendido)!;
    canvas.drawPath(cuerpo, Paint()..color = relleno);
    canvas.drawPath(
        cuerpo,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Color.lerp(rosca, ambar, encendido)!);
    // Filamento
    final fil = Path()
      ..moveTo(cx - r * 0.25, cuelloY + r * 0.3)
      ..lineTo(cx - r * 0.25, cy + r * 0.1)
      ..cubicTo(cx - r * 0.25, cy - r * 0.3, cx + r * 0.25, cy - r * 0.3, cx + r * 0.25, cy + r * 0.1)
      ..lineTo(cx + r * 0.25, cuelloY + r * 0.3);
    canvas.drawPath(
        fil,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(rosca, Colors.white, encendido)!);
    // Rosca
    final top = cuelloY + r * 0.45;
    final rp = Paint()..color = rosca;
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(cx - r * 0.42, top + i * r * 0.2, r * 0.84, r * 0.14),
              const Radius.circular(3)),
          rp);
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - r * 0.2, top + 3 * r * 0.2, r * 0.4, r * 0.14),
            const Radius.circular(4)),
        rp);
  }

  @override
  bool shouldRepaint(FocoPainter o) => o.encendido != encendido || o.ambar != ambar;
}

// =====================================================================
//  Alarma y modos
// =====================================================================
class BannerAlarma extends StatelessWidget {
  const BannerAlarma({super.key});
  @override
  Widget build(BuildContext context) {
    final p = TemaPaleta.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: p.alarma, borderRadius: BorderRadius.circular(14)),
      child: const Row(children: [
        Icon(Icons.campaign, color: Colors.white, size: 28),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Alarma sonando: se detectó movimiento con la casa vacía',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      ]),
    );
  }
}

class SelectorModo extends StatelessWidget {
  const SelectorModo({super.key, required this.casa});
  final Casa casa;
  static const _ayuda = {
    Modo.automatico: 'El foco y el ventilador se prenden solo si hay alguien y hace falta.',
    Modo.manual: 'Tú decides desde aquí o con el pulsador. Nada se apaga solo.',
    Modo.seguridad: 'Casa vacía: si alguien entra, suena la sirena y te llega una alerta.',
  };
  @override
  Widget build(BuildContext context) {
    final p = TemaPaleta.of(context);
    final modo = casa.estado.modo;
    // En celulares angostos se ocultan los íconos para que el texto no se parta
    final angosto = MediaQuery.of(context).size.width < 520;
    return Placa(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Seccion('Modo de la casa'),
          SegmentedButton<Modo>(
            showSelectedIcon: false,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((s) =>
                  s.contains(WidgetState.selected)
                      ? (modo == Modo.seguridad ? p.alarma : p.tinta)
                      : Colors.transparent),
              foregroundColor: WidgetStateProperty.resolveWith((s) =>
                  s.contains(WidgetState.selected) ? p.placa : p.tinta),
              side: WidgetStatePropertyAll(BorderSide(color: p.linea)),
            ),
            segments: [
              ButtonSegment(
                  value: Modo.automatico,
                  icon: angosto ? null : const Icon(Icons.auto_mode, size: 18),
                  label: const Text('Auto', maxLines: 1, softWrap: false)),
              ButtonSegment(
                  value: Modo.manual,
                  icon: angosto ? null : const Icon(Icons.touch_app_outlined, size: 18),
                  label: const Text('Manual', maxLines: 1, softWrap: false)),
              ButtonSegment(
                  value: Modo.seguridad,
                  icon: angosto ? null : const Icon(Icons.shield_outlined, size: 18),
                  label: const Text('Seguridad', maxLines: 1, softWrap: false)),
            ],
            selected: {modo},
            onSelectionChanged: (s) => casa.ponerModo(s.first),
          ),
          const SizedBox(height: 12),
          Text(_ayuda[modo]!, style: TextStyle(color: p.tenue, fontSize: 13.5)),
        ],
      ),
    );
  }
}

// =====================================================================
//  Mediciones con mini gráfico
// =====================================================================
class Mediciones extends StatelessWidget {
  const Mediciones({super.key, required this.casa});
  final Casa casa;
  @override
  Widget build(BuildContext context) {
    final p = TemaPaleta.of(context);
    final e = casa.estado;
    final items = [
      _Medida('Temperatura', e.temperatura?.toStringAsFixed(1) ?? '--', '°C',
          casa.histTemp, p.alarma),
      _Medida('Humedad', e.humedad?.toStringAsFixed(0) ?? '--', '%',
          casa.histHum, p.ventilador),
      _Medida('Luz ambiente', e.lux.round().toString(), 'lux', casa.histLux,
          p.foco),
    ];
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth < 460 ? 1 : 3;
      final w = (c.maxWidth - 12 * (cols - 1)) / cols;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final m in items) SizedBox(width: w, child: m)],
      );
    });
  }
}

class _Medida extends StatelessWidget {
  const _Medida(this.nombre, this.valor, this.unidad, this.hist, this.color);
  final String nombre, valor, unidad;
  final List<double> hist;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final p = TemaPaleta.of(context);
    return Placa(
      padding: 16,
      radio: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nombre, style: TextStyle(color: p.tenue, fontSize: 13)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(valor, style: cifra(context, 30)),
              const SizedBox(width: 4),
              Text(unidad, style: TextStyle(color: p.tenue, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            width: double.infinity,
            child: CustomPaint(
                painter: Sparkline(hist, color: color, rejilla: p.linea)),
          ),
        ],
      ),
    );
  }
}

class Sparkline extends CustomPainter {
  Sparkline(this.datos, {required this.color, required this.rejilla});
  final List<double> datos;
  final Color color, rejilla;
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawLine(Offset(0, s.height - 0.5), Offset(s.width, s.height - 0.5),
        Paint()..color = rejilla);
    if (datos.length < 2) return;
    var lo = datos.reduce(math.min), hi = datos.reduce(math.max);
    if (hi - lo < 1e-6) {
      lo -= 1;
      hi += 1;
    }
    Offset pt(int i) => Offset(
          i / (datos.length - 1) * s.width,
          s.height - 3 - (datos[i] - lo) / (hi - lo) * (s.height - 6),
        );
    final linea = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < datos.length; i++) {
      linea.lineTo(pt(i).dx, pt(i).dy);
    }
    final area = Path.from(linea)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.14));
    canvas.drawPath(
        linea,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = color);
    canvas.drawCircle(pt(datos.length - 1), 3.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(Sparkline o) => true;
}

// =====================================================================
//  Interruptores (placas de pared)
// =====================================================================
class Interruptores extends StatelessWidget {
  const Interruptores({super.key, required this.casa});
  final Casa casa;
  @override
  Widget build(BuildContext context) {
    final p = TemaPaleta.of(context);
    final e = casa.estado;
    final nota = e.seguridad
        ? 'Bloqueado en modo seguridad'
        : (e.auto ? 'Si lo tocas, la casa pasa a manual' : 'Control manual');
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth < 460 ? 1 : 2;
      final w = (c.maxWidth - 12 * (cols - 1)) / cols;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(
          width: w,
          child: _Interruptor(
            nombre: 'Foco',
            detalle: '60 W · relé 1',
            icono: Icons.lightbulb_outline,
            encendido: e.luz,
            color: p.foco,
            nota: nota,
            habilitado: !e.seguridad && casa.conexion == Conexion.conectado,
            alCambiar: casa.ponerLuz,
          ),
        ),
        SizedBox(
          width: w,
          child: _Interruptor(
            nombre: 'Ventilador',
            detalle: '45 W · relé 2',
            icono: Icons.mode_fan_off_outlined,
            iconoOn: Icons.air,
            encendido: e.ventilador,
            color: p.ventilador,
            nota: nota,
            habilitado: !e.seguridad && casa.conexion == Conexion.conectado,
            alCambiar: casa.ponerVentilador,
          ),
        ),
      ]);
    });
  }
}

class _Interruptor extends StatelessWidget {
  const _Interruptor({
    required this.nombre,
    required this.detalle,
    required this.icono,
    this.iconoOn,
    required this.encendido,
    required this.color,
    required this.nota,
    required this.habilitado,
    required this.alCambiar,
  });
  final String nombre, detalle, nota;
  final IconData icono;
  final IconData? iconoOn;
  final bool encendido, habilitado;
  final Color color;
  final ValueChanged<bool> alCambiar;

  @override
  Widget build(BuildContext context) {
    final p = TemaPaleta.of(context);
    return Placa(
      padding: 16,
      radio: 12,
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: encendido ? color.withValues(alpha: 0.18) : p.muro,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(encendido ? (iconoOn ?? icono) : icono,
              color: encendido ? color : p.tenue),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nombre, style: titulo(context, 16)),
              const SizedBox(height: 2),
              Text('$detalle\n$nota',
                  style: TextStyle(color: p.tenue, fontSize: 12.5, height: 1.35)),
            ],
          ),
        ),
        Switch(
          value: encendido,
          activeColor: Colors.white,
          activeTrackColor: color,
          onChanged: habilitado ? alCambiar : null,
        ),
      ]),
    );
  }
}

// =====================================================================
//  Energía y ahorro
// =====================================================================
class Energia extends StatelessWidget {
  const Energia({super.key, required this.casa});
  final Casa casa;
  @override
  Widget build(BuildContext context) {
    final p = TemaPaleta.of(context);
    final e = casa.estado;
    final ahorro = e.ahorro.clamp(0, 100).toDouble();
    final minutos = e.encendidoSeg ~/ 60;
    return Placa(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Seccion('Energía',
              detalle: 'desde que se encendió el ESP32 · $minutos min'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(ahorro.toStringAsFixed(0), style: cifra(context, 56, color: p.ahorro)),
              Text(' %', style: cifra(context, 24, color: p.ahorro)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('de ahorro frente a dejar el foco siempre prendido',
                    style: TextStyle(color: p.tenue, fontSize: 13.5)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 10,
              child: Stack(children: [
                Container(color: p.linea),
                FractionallySizedBox(
                  widthFactor: ahorro / 100,
                  child: Container(color: p.ahorro),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _Dato('Consumo estimado', '${e.energiaWh.toStringAsFixed(2)} Wh')),
            Expanded(
                child: _Dato('Foco ahora', e.luz ? '60 W' : '0 W')),
            Expanded(
                child: _Dato('Ventilador ahora', e.ventilador ? '45 W' : '0 W')),
          ]),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.nombre, this.valor);
  final String nombre, valor;
  @override
  Widget build(BuildContext context) {
    final p = TemaPaleta.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(nombre, style: TextStyle(color: p.tenue, fontSize: 12)),
        const SizedBox(height: 4),
        Text(valor, style: cifra(context, 17)),
      ],
    );
  }
}

// =====================================================================
//  Umbrales configurables
// =====================================================================
class Umbrales extends StatefulWidget {
  const Umbrales({super.key, required this.casa});
  final Casa casa;
  @override
  State<Umbrales> createState() => _UmbralesState();
}

class _UmbralesState extends State<Umbrales> {
  double? _lux, _temp; // valor mientras se arrastra

  @override
  Widget build(BuildContext context) {
    final p = TemaPaleta.of(context);
    final e = widget.casa.estado;
    final lux = _lux ?? e.umbralLux.toDouble().clamp(10, 1000);
    final temp = _temp ?? e.umbralTemp.clamp(20, 40);
    final ok = widget.casa.conexion == Conexion.conectado;
    return Placa(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Seccion('Ajustes del modo automático'),
          _fila(context, 'Considerar oscuro debajo de', '${lux.round()} lux'),
          Slider(
            value: lux.toDouble(),
            min: 10,
            max: 1000,
            divisions: 99,
            activeColor: p.foco,
            onChanged: ok ? (v) => setState(() => _lux = v) : null,
            onChangeEnd: (v) {
              widget.casa.ponerUmbralLux(v.round());
              setState(() => _lux = null);
            },
          ),
          const SizedBox(height: 10),
          _fila(context, 'Prender ventilador sobre', '${temp.toStringAsFixed(1)} °C'),
          Slider(
            value: temp.toDouble(),
            min: 20,
            max: 40,
            divisions: 40,
            activeColor: p.ventilador,
            onChanged: ok ? (v) => setState(() => _temp = v) : null,
            onChangeEnd: (v) {
              widget.casa.ponerUmbralTemp(v);
              setState(() => _temp = null);
            },
          ),
        ],
      ),
    );
  }

  Widget _fila(BuildContext c, String a, String b) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Expanded(
              child: Text(a,
                  style: TextStyle(color: TemaPaleta.of(c).tinta, fontSize: 14))),
          Text(b, style: cifra(c, 16)),
        ]),
      );
}

// =====================================================================
//  Bitácora de eventos
// =====================================================================
class Bitacora extends StatelessWidget {
  const Bitacora({super.key, required this.casa});
  final Casa casa;
  @override
  Widget build(BuildContext context) {
    final p = TemaPaleta.of(context);
    final ev = casa.eventos.take(8).toList();
    return Placa(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Seccion('Actividad reciente'),
          if (ev.isEmpty)
            Text('Aquí aparecerán las alertas y lo que hagas desde la app.',
                style: TextStyle(color: p.tenue, fontSize: 13.5)),
          for (final e in ev)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (e.tipo) {
                      'intruso' => Icons.warning_amber_rounded,
                      'temp_alta' => Icons.thermostat,
                      'comando' => Icons.phone_android,
                      _ => Icons.wifi_tethering,
                    },
                    size: 18,
                    color: (e.tipo == 'intruso' || e.tipo == 'temp_alta')
                        ? p.alarma
                        : p.tenue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(e.mensaje,
                          style: TextStyle(color: p.tinta, fontSize: 13.5))),
                  Text(
                    '${e.hora.hour.toString().padLeft(2, '0')}:${e.hora.minute.toString().padLeft(2, '0')}:${e.hora.second.toString().padLeft(2, '0')}',
                    style: cifra(context, 12.5, color: p.tenue, w: FontWeight.w500),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
