import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obdapp/functions/telemetria.dart';

void main() {
  test('pacote segue a estrutura da especificação, em unidades SI', () {
    final m = MontadorTelemetria(sessionId: 'session_001', vehicleId: 'vehicle_001');
    var p = m.pacote();
    expect(p['sequence'], 1);
    expect(p['gps'], isNull);
    expect(p['imu'], isNull);
    expect(p['obd'], isNull);

    m.gps = const LeituraGps(
      timestamp: 1794950000125,
      latitude: -22.58912,
      longitude: -43.28431,
      altitude: 24.0,
      speed: 15.2,
      heading: 120.5,
      horizontalAccuracy: 3.0,
      speedAccuracy: 0.5,
    );
    m.acelerometro = const LeituraEixos(1794950000110, Eixos(0.45, 1.20, 9.81));
    m.giroscopio = const LeituraEixos(1794950000120, Eixos(0.01, 0.02, 0.18));
    m.registrarObd(0x0D, 54, 1794950000100); // 54 km/h
    m.registrarObd(0x0C, 3200, 1794950000115);
    m.registrarObd(0x11, 35, 1794950000105);

    p = json.decode(json.encode(m.pacote())) as Map<String, dynamic>;
    expect(p.keys, containsAll(['session_id', 'vehicle_id', 'sequence', 'gps', 'imu', 'obd']));
    expect(p['sequence'], 2);
    expect(p['gps']['heading'], 120.5);
    expect(p['gps']['horizontal_accuracy'], 3.0);
    expect(p['imu']['timestamp'], 1794950000120);
    expect(p['imu']['accelerometer']['z'], 9.81);
    expect(p['imu']['gyroscope']['z'], 0.18);
    expect(p['obd']['timestamp'], 1794950000115);
    expect(p['obd']['speed'], closeTo(15.0, 1e-9)); // m/s
    expect(p['obd']['rpm'], 3200);
    expect(p['obd']['throttle_position'], 35);
  });

  test('endpoint do WebSocket', () {
    expect(ClienteTelemetriaWs.endpoint('ws://192.168.0.10:8000/', 'session_001').toString(),
        'ws://192.168.0.10:8000/ws/vehicle/session_001');
    expect(ClienteTelemetriaWs.endpoint('192.168.0.10:8000', 's').toString(),
        'ws://192.168.0.10:8000/ws/vehicle/s');
    expect(ClienteTelemetriaWs.endpoint('wss://servidor.com', 's').toString(),
        'wss://servidor.com/ws/vehicle/s');
  });

  test('arquivo JSON é uma lista válida', () async {
    final pasta = await Directory.systemTemp.createTemp('telemetria');
    final log = await JsonTelemetriaLogger.criar(pasta, 't.json');
    final m = MontadorTelemetria(sessionId: 's', vehicleId: 'v');
    for (var i = 0; i < 3; i++) {
      log.gravar(json.encode(m.pacote()));
    }
    await log.fechar();
    final lista = json.decode(await log.arquivo.readAsString()) as List;
    expect(lista.length, 3);
    expect(lista.last['sequence'], 3);
    await pasta.delete(recursive: true);
  });

  test('WebSocket envia em ordem, guarda na fila sem servidor e mede latência', () async {
    final recebidos = <Map<String, dynamic>>[];
    final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servidor.listen((req) async {
      expect(req.uri.path, '/ws/vehicle/sessao_teste');
      final ws = await WebSocketTransformer.upgrade(req);
      ws.listen((msg) {
        final m = json.decode(msg as String) as Map<String, dynamic>;
        recebidos.add(m);
        ws.add(json.encode({'type': 'ack', 'sequence': m['sequence']}));
      });
    });
    final cliente = ClienteTelemetriaWs(
        ClienteTelemetriaWs.endpoint('ws://127.0.0.1:${servidor.port}', 'sessao_teste'));
    final m = MontadorTelemetria(sessionId: 'sessao_teste', vehicleId: 'v');
    // antes de conectar: vai para a fila
    for (var i = 0; i < 3; i++) {
      final p = m.pacote();
      cliente.enviar(json.encode(p), p['sequence'] as int);
    }
    expect(cliente.naFila, 3);
    cliente.iniciar();
    for (var i = 0; i < 50 && recebidos.length < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(recebidos.map((r) => r['sequence']), [1, 2, 3]);
    expect(cliente.naFila, 0);
    expect(cliente.estado, EstadoWs.conectado);
    final p = m.pacote();
    cliente.enviar(json.encode(p), p['sequence'] as int);
    for (var i = 0; i < 50 && cliente.latenciaMs == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(cliente.latenciaMs, isNotNull);
    await cliente.parar();
    await servidor.close(force: true);
  });

  test('session_id', () {
    expect(novoSessionId(DateTime(2026, 11, 19, 11, 37, 5)), 'session_20261119_113705');
  });
}
