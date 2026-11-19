// Telemetria para o gêmeo digital (Fase 0 e Fase 1 da especificação do
// projeto): pacotes JSON com GPS, IMU (acelerômetro e giroscópio) e OBD-II,
// cada leitura com o seu próprio horário de aquisição.
//
// Os pacotes seguem a estrutura da seção 4.1 da especificação:
//
//   {
//     "session_id": "session_20261119_113700",
//     "vehicle_id": "9BHBG51CAJP000000",
//     "sequence": 1250,
//     "gps": { "timestamp", "latitude", "longitude", "altitude", "speed",
//              "heading", "horizontal_accuracy", "speed_accuracy" },
//     "imu": { "timestamp", "accelerometer": {x, y, z}, "gyroscope": {x, y, z} },
//     "obd": { "timestamp", "speed", "rpm", "throttle_position", ... }
//   }
//
// Unidades (já padronizadas no app, seção 5.1):
//  * timestamps em milissegundos desde 01/01/1970 (UTC)
//  * velocidades em m/s (GPS e OBD)
//  * acelerômetro em m/s², com a gravidade (o celular parado mede ~9,81 no
//    eixo que aponta para cima); a compensação da gravidade e a mudança para o
//    referencial do veículo ficam no backend (seção 5.2)
//  * giroscópio em rad/s
//  * ângulos (heading) em graus, 0 = norte, sentido horário, como o GPS informa
//  * posições do acelerador e carga em %, rotação em rpm, temperatura em °C
// Um bloco sem leitura ainda (ex.: GPS sem sinal) vai como null.
//
// Os pacotes são gravados num arquivo .json (uma lista JSON) e, se ativado,
// enviados por WebSocket para ws://servidor:8000/ws/vehicle/{session_id}.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------------------
// Leituras
// ---------------------------------------------------------------------------

class LeituraGps {
  final int timestamp;
  final double latitude, longitude, altitude, speed, heading, horizontalAccuracy, speedAccuracy;
  const LeituraGps({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speed,
    required this.heading,
    required this.horizontalAccuracy,
    required this.speedAccuracy,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'speed': speed,
        'heading': heading,
        'horizontal_accuracy': horizontalAccuracy,
        'speed_accuracy': speedAccuracy,
      };
}

class Eixos {
  final double x, y, z;
  const Eixos(this.x, this.y, this.z);
  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'z': z};
}

class LeituraEixos {
  final int timestamp;
  final Eixos valor;
  const LeituraEixos(this.timestamp, this.valor);
}

/// PIDs do OBD usados na telemetria (seção 3.1), com o nome do campo no JSON
/// e a conversão para a unidade padronizada.
class PidTelemetria {
  final int pid;
  final String campo;
  final double Function(double) converter;
  const PidTelemetria(this.pid, this.campo, this.converter);
}

double _igual(double v) => v;
double _kmhParaMs(double v) => v / 3.6;

const pidsTelemetria = [
  PidTelemetria(0x0D, 'speed', _kmhParaMs), // velocidade, m/s
  PidTelemetria(0x0C, 'rpm', _igual), // rotação, rpm
  PidTelemetria(0x11, 'throttle_position', _igual), // borboleta, %
  PidTelemetria(0x04, 'engine_load', _igual), // carga calculada, %
  PidTelemetria(0x05, 'coolant_temperature', _igual), // temperatura do motor, °C
  PidTelemetria(0x49, 'accelerator_pedal_position', _igual), // pedal D, %
];

class LeituraObd {
  final int timestamp;
  final double valor;
  const LeituraObd(this.timestamp, this.valor);
}

/// Junta as últimas leituras de cada sensor e monta os pacotes.
class MontadorTelemetria {
  final String sessionId;
  final String vehicleId;
  int _sequencia = 0;

  LeituraGps? gps;
  LeituraEixos? acelerometro;
  LeituraEixos? giroscopio;
  final Map<int, LeituraObd> obd = {};

  MontadorTelemetria({required this.sessionId, required this.vehicleId});

  int get sequencia => _sequencia;

  void registrarObd(int pid, double valor, int timestamp) {
    obd[pid] = LeituraObd(timestamp, valor);
  }

  Map<String, dynamic>? _imu() {
    final a = acelerometro, g = giroscopio;
    if (a == null && g == null) return null;
    // horário da leitura mais recente das duas
    final t = [if (a != null) a.timestamp, if (g != null) g.timestamp].reduce((x, y) => x > y ? x : y);
    return {
      'timestamp': t,
      'accelerometer': a?.valor.toJson(),
      'gyroscope': g?.valor.toJson(),
    };
  }

  Map<String, dynamic>? _obd() {
    if (obd.isEmpty) return null;
    final m = <String, dynamic>{
      'timestamp': obd.values.map((l) => l.timestamp).reduce((x, y) => x > y ? x : y),
    };
    for (final p in pidsTelemetria) {
      final l = obd[p.pid];
      if (l != null) m[p.campo] = p.converter(l.valor);
    }
    return m;
  }

  /// Próximo pacote, com o número de sequência seguinte.
  Map<String, dynamic> pacote() => {
        'session_id': sessionId,
        'vehicle_id': vehicleId,
        'sequence': ++_sequencia,
        'gps': gps?.toJson(),
        'imu': _imu(),
        'obd': _obd(),
      };
}

/// Identificador da sessão: session_AAAAMMDD_hhmmss.
String novoSessionId(DateTime t) {
  String d2(int v) => v.toString().padLeft(2, '0');
  return 'session_${t.year}${d2(t.month)}${d2(t.day)}_${d2(t.hour)}${d2(t.minute)}${d2(t.second)}';
}

// ---------------------------------------------------------------------------
// Arquivo JSON
// ---------------------------------------------------------------------------

/// Grava os pacotes num arquivo .json que é uma lista: "[", os pacotes
/// separados por vírgula e "]" ao fechar. Cada pacote fica numa linha, então
/// mesmo se o app for fechado no meio (arquivo sem o "]" final) dá para ler
/// linha a linha.
class JsonTelemetriaLogger {
  final File arquivo;
  final RandomAccessFile _saida;
  int pacotes = 0;

  JsonTelemetriaLogger._(this.arquivo, this._saida);

  static Future<JsonTelemetriaLogger> criar(Directory pasta, String nome) async {
    await pasta.create(recursive: true);
    final f = File('${pasta.path}/$nome');
    final s = f.openSync(mode: FileMode.write);
    s.writeStringSync('[\n');
    return JsonTelemetriaLogger._(f, s);
  }

  void gravar(String json) {
    _saida.writeStringSync(pacotes == 0 ? json : ',\n$json');
    pacotes++;
    if (pacotes % 50 == 0) _saida.flushSync();
  }

  Future<void> fechar() async {
    _saida.writeStringSync('\n]\n');
    _saida.flushSync();
    _saida.closeSync();
  }
}

// ---------------------------------------------------------------------------
// WebSocket
// ---------------------------------------------------------------------------

enum EstadoWs { desligado, conectando, conectado, aguardando }

/// Cliente WebSocket da telemetria (seção 4.2):
///  * reconexão automática, com espera crescente (1, 2, 4... até 10 s)
///  * buffer local: os pacotes ficam numa fila enquanto não há conexão e são
///    enviados em ordem quando ela volta (até [maxFila] pacotes; acima disso
///    os mais antigos são descartados e contados em [descartados])
///  * controle de sequência: cada pacote leva o "sequence", para o backend
///    identificar perdas
///  * latência: se o servidor responder {"type": "ack", "sequence": n}, o app
///    calcula o tempo de ida e volta desse pacote
///  * registro de falhas: as últimas mensagens de erro ficam em [falhas]
class ClienteTelemetriaWs {
  final Uri uri;
  final int maxFila;
  final void Function()? aoMudar;

  WebSocketChannel? _canal;
  StreamSubscription<dynamic>? _escuta;
  final Queue<String> _fila = Queue();
  final Map<int, int> _enviadoEm = {}; // sequence -> horário de envio (ms)
  bool _ligado = false;
  int _tentativa = 0;
  Timer? _religar;

  EstadoWs estado = EstadoWs.desligado;
  int enviados = 0;
  int descartados = 0;
  int reconexoes = 0;
  int? latenciaMs;
  final List<String> falhas = [];

  ClienteTelemetriaWs(this.uri, {this.maxFila = 6000, this.aoMudar});

  /// Endereço do endpoint a partir do servidor (ex.: ws://192.168.0.10:8000).
  static Uri endpoint(String servidor, String sessionId) {
    var base = servidor.trim();
    if (!base.startsWith('ws://') && !base.startsWith('wss://')) base = 'ws://$base';
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Uri.parse('$base/ws/vehicle/$sessionId');
  }

  int get naFila => _fila.length;

  void _mudou() => aoMudar?.call();

  void _falha(String texto) {
    final t = DateTime.now();
    String d2(int v) => v.toString().padLeft(2, '0');
    falhas.add('${d2(t.hour)}:${d2(t.minute)}:${d2(t.second)} $texto');
    if (falhas.length > 50) falhas.removeAt(0);
  }

  void iniciar() {
    _ligado = true;
    _conectar();
  }

  Future<void> _conectar() async {
    if (!_ligado) return;
    estado = EstadoWs.conectando;
    _mudou();
    try {
      final canal = WebSocketChannel.connect(uri);
      await canal.ready.timeout(const Duration(seconds: 5));
      if (!_ligado) {
        await canal.sink.close();
        return;
      }
      _canal = canal;
      if (_tentativa > 0) reconexoes++;
      _tentativa = 0;
      estado = EstadoWs.conectado;
      _escuta = canal.stream.listen(_aoReceber, onError: (Object e) {
        _falha('erro na conexão: $e');
        _caiu();
      }, onDone: _caiu);
      _mudou();
      _esvaziarFila();
    } catch (e) {
      _falha('não conectou: $e');
      _caiu();
    }
  }

  void _aoReceber(dynamic msg) {
    try {
      final m = json.decode(msg as String);
      if (m is Map && m['type'] == 'ack' && m['sequence'] is int) {
        final enviado = _enviadoEm.remove(m['sequence']);
        if (enviado != null) {
          // a tela é atualizada junto com o CSV, sem redesenhar a cada ack
          latenciaMs = DateTime.now().millisecondsSinceEpoch - enviado;
        }
      }
    } catch (_) {
      // mensagens que não são JSON são ignoradas
    }
  }

  void _caiu() {
    _escuta?.cancel();
    _escuta = null;
    _canal = null;
    if (!_ligado) return;
    estado = EstadoWs.aguardando;
    _mudou();
    final espera = Duration(seconds: [1, 2, 4, 8, 10][_tentativa.clamp(0, 4)]);
    _tentativa++;
    _religar?.cancel();
    _religar = Timer(espera, _conectar);
  }

  /// Envia um pacote (ou guarda na fila se não houver conexão).
  void enviar(String json, int sequencia) {
    _fila.add(json);
    while (_fila.length > maxFila) {
      _fila.removeFirst();
      descartados++;
    }
    if (_enviadoEm.length > 500) _enviadoEm.clear();
    _enviadoEm[sequencia] = DateTime.now().millisecondsSinceEpoch;
    _esvaziarFila();
  }

  void _esvaziarFila() {
    final canal = _canal;
    if (canal == null || estado != EstadoWs.conectado) return;
    try {
      while (_fila.isNotEmpty) {
        canal.sink.add(_fila.first);
        _fila.removeFirst();
        enviados++;
      }
    } catch (e) {
      _falha('falha ao enviar: $e');
      _caiu();
    }
  }

  Future<void> parar() async {
    _ligado = false;
    _religar?.cancel();
    _esvaziarFila();
    await _escuta?.cancel();
    try {
      await _canal?.sink.close();
    } catch (_) {}
    _canal = null;
    estado = EstadoWs.desligado;
    _mudou();
  }
}
