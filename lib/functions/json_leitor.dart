// Leitura do JSON da telemetria do gêmeo digital (Telemetria_*.json, ver
// functions/telemetria.dart) para o mesmo visualizador dos CSVs: cada pacote
// vira uma linha e cada campo de GPS, IMU e OBD vira uma coluna.
// Dart puro, testado em test/telemetria_test.dart.

import 'dart:convert';

import 'csv_leitor.dart';

/// Colunas da tabela, na ordem em que aparecem. Cada uma diz de onde vem o
/// valor no pacote (bloco e campo) e, se for o caso, como converter.
class _Coluna {
  final String nome;
  final String bloco;
  final List<String> campo;
  final double Function(double)? converter;
  const _Coluna(this.nome, this.bloco, this.campo, [this.converter]);
}

double _msParaKmh(double v) => v * 3.6;

// Os nomes do GPS, da velocidade e da rotação são os mesmos do CSV, para o
// visualizador desenhar o mapa e abrir o gráfico da velocidade.
const _colunas = [
  _Coluna('Latitude (deg)', 'gps', ['latitude']),
  _Coluna('Longitude (deg)', 'gps', ['longitude']),
  _Coluna('Altitude (m)', 'gps', ['altitude']),
  _Coluna('GPS Speed (km/h)', 'gps', ['speed'], _msParaKmh),
  _Coluna('GPS Heading (deg)', 'gps', ['heading']),
  _Coluna('GPS Accuracy (m)', 'gps', ['horizontal_accuracy']),
  _Coluna('GPS Speed Accuracy (m/s)', 'gps', ['speed_accuracy']),
  _Coluna('Vehicle speed (km/h)', 'obd', ['speed'], _msParaKmh),
  _Coluna('Engine RPM (RPM)', 'obd', ['rpm']),
  _Coluna('Throttle position (%)', 'obd', ['throttle_position']),
  _Coluna('Calculated load value (%)', 'obd', ['engine_load']),
  _Coluna('Engine coolant temperature (°C)', 'obd', ['coolant_temperature']),
  _Coluna('Accelerator pedal position D (%)', 'obd', ['accelerator_pedal_position']),
  _Coluna('Accel (Grav) X (m/s²)', 'imu', ['accelerometer', 'x']),
  _Coluna('Accel (Grav) Y (m/s²)', 'imu', ['accelerometer', 'y']),
  _Coluna('Accel (Grav) Z (m/s²)', 'imu', ['accelerometer', 'z']),
  _Coluna('Gyro X (rad/s)', 'imu', ['gyroscope', 'x']),
  _Coluna('Gyro Y (rad/s)', 'imu', ['gyroscope', 'y']),
  _Coluna('Gyro Z (rad/s)', 'imu', ['gyroscope', 'z']),
];

/// Pacotes do arquivo. Aceita a lista JSON completa e também o arquivo de uma
/// coleta interrompida (sem o "]" final), lendo um pacote por linha.
List<Map<String, dynamic>> pacotesTelemetria(String texto) {
  if (texto.startsWith('﻿')) texto = texto.substring(1);
  try {
    final tudo = json.decode(texto);
    if (tudo is List) return tudo.whereType<Map<String, dynamic>>().toList();
    if (tudo is Map<String, dynamic>) return [tudo];
  } catch (_) {
    // arquivo incompleto: segue linha a linha
  }
  final pacotes = <Map<String, dynamic>>[];
  for (var linha in texto.split(RegExp(r'\r?\n'))) {
    linha = linha.trim();
    if (linha.startsWith('[')) linha = linha.substring(1).trim();
    if (linha.startsWith(',')) linha = linha.substring(1).trim();
    if (linha.endsWith(',')) linha = linha.substring(0, linha.length - 1);
    if (linha.endsWith(']')) linha = linha.substring(0, linha.length - 1).trim();
    if (linha.isEmpty) continue;
    try {
      final p = json.decode(linha);
      if (p is Map<String, dynamic>) pacotes.add(p);
    } catch (_) {
      // linha cortada no fim do arquivo
    }
  }
  return pacotes;
}

/// Horário do pacote em ms: a leitura mais recente entre GPS, IMU e OBD.
int? _horario(Map<String, dynamic> p) {
  int? t;
  for (final b in ['gps', 'imu', 'obd']) {
    final bloco = p[b];
    if (bloco is Map && bloco['timestamp'] is num) {
      final v = (bloco['timestamp'] as num).toInt();
      if (t == null || v > t) t = v;
    }
  }
  return t;
}

String _numero(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toStringAsFixed(0);
  return v.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '');
}

/// Converte o texto do JSON da telemetria numa tabela como a do CSV, com as
/// colunas "Tempo (s)" (desde o primeiro pacote), "sequence", os campos de
/// GPS, OBD e IMU e as colunas "session_id" e "vehicle_id".
/// Colunas que não têm nenhum valor na coleta inteira ficam de fora.
TabelaCsv lerJsonTelemetria(String texto) {
  final pacotes = pacotesTelemetria(texto);
  if (pacotes.isEmpty) return const TabelaCsv([], []);

  final horarios = [for (final p in pacotes) _horario(p)];
  final t0 = horarios.whereType<int>().fold<int?>(null, (a, b) => a == null || b < a ? b : a);

  dynamic valor(Map<String, dynamic> p, _Coluna c) {
    dynamic v = p[c.bloco];
    for (final k in c.campo) {
      if (v is! Map) return null;
      v = v[k];
    }
    if (v is! num) return null;
    final d = v.toDouble();
    return c.converter == null ? d : c.converter!(d);
  }

  final usadas = [
    for (final c in _colunas)
      if (pacotes.any((p) => valor(p, c) != null)) c
  ];
  final colunas = [
    'Tempo (s)',
    'sequence',
    for (final c in usadas) c.nome,
    'session_id',
    'vehicle_id',
  ];

  final linhas = <List<String>>[];
  var anterior = 0.0; // pacote sem leitura nenhuma repete o tempo do anterior
  for (var i = 0; i < pacotes.length; i++) {
    final p = pacotes[i];
    final h = horarios[i];
    if (h != null && t0 != null) anterior = (h - t0) / 1000;
    linhas.add([
      anterior.toStringAsFixed(3),
      '${p['sequence'] ?? ''}',
      for (final c in usadas)
        (() {
          final v = valor(p, c);
          return v == null ? '' : _numero(v as double);
        })(),
      '${p['session_id'] ?? ''}',
      '${p['vehicle_id'] ?? ''}',
    ]);
  }
  return TabelaCsv(colunas, linhas);
}
