# Fuel Sentinel V2

<p align="center">
  <img src="assets/icon/fuel_sentinel_icon.png" width="160" alt="Ícone do Fuel Sentinel">
</p>

<p align="center">
  <b>Conferência de abastecimento e coleta de dados OBD-II pelo celular</b><br>
  <a href="https://github.com/gabestk/Fuel-Sentinel-V2/releases/download/teste/fuel-sentinel.apk">📲 Baixar o APK</a> ·
  <a href="#funcionalidades">Funcionalidades</a> ·
  <a href="#para-desenvolvedores">Para desenvolvedores</a>
</p>

<p align="center">
  <a href="https://github.com/gabestk/Fuel-Sentinel-V2/actions/workflows/testes.yml"><img src="https://github.com/gabestk/Fuel-Sentinel-V2/actions/workflows/testes.yml/badge.svg?branch=main" alt="Build"></a>
  <img src="https://img.shields.io/badge/versão-1.2.0-26B07F" alt="Versão 1.2.0">
  <img src="https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/plataforma-Android-3DDC84?logo=android&logoColor=white" alt="Android">
</p>

> Continuação do [Fuel Sentinel](https://github.com/gabestk/fuel_sentinel), que segue na versão 1.0.
> O desenvolvimento a partir da versão 1.1 acontece aqui.

O Fuel Sentinel se conecta a um adaptador **OBD-II** (a porta de diagnóstico do carro) com chip
**ELM327** pelo Bluetooth e faz duas coisas:

- **Confere um abastecimento**: mede o nível do tanque antes e depois e compara com a quantidade
  informada na bomba.
- **Coleta dados do veículo**: lê os PIDs (os códigos de cada sensor) escolhidos e grava um CSV no
  mesmo formato do aplicativo OBDLink, junto com o GPS e os sensores do celular.

Tudo fica salvo só no celular, e cada coleta pode ser aberta no próprio app, vista no mapa ou
compartilhada.

---

## Sumário

- [Instalar](#instalar)
- [Funcionalidades](#funcionalidades)
  - [Abastecimento](#abastecimento)
  - [Scanner](#scanner)
  - [Telemetria do gêmeo digital](#telemetria-do-gêmeo-digital)
  - [Coletas salvas](#coletas-salvas)
  - [Configuração](#configuração)
- [Arquivos gerados](#arquivos-gerados)
- [Versões](#versões)
- [Para desenvolvedores](#para-desenvolvedores)
- [Limitações conhecidas](#limitações-conhecidas)

---

## Instalar

1. No celular Android, baixe o APK: **[fuel-sentinel.apk](https://github.com/gabestk/Fuel-Sentinel-V2/releases/download/teste/fuel-sentinel.apk)**
2. Abra o arquivo e permita a instalação de fontes desconhecidas, se o Android pedir.
3. Pareie o adaptador OBD-II nas configurações de Bluetooth do celular (a senha costuma ser `1234` ou `0000`).
4. Abra o app e aceite as permissões de Bluetooth e localização.

> O link sempre aponta para a versão mais recente da branch `test`. Para atualizar, basta baixar
> de novo e tocar em **Atualizar**: os APKs são assinados sempre com a mesma chave, e as coletas
> e configurações continuam no celular.

---

## Funcionalidades

### Abastecimento

Confere se o nível do tanque subiu o esperado para a quantidade abastecida. O app lê só dois dados
do veículo: o **nível de combustível** (PID `01 2F`) e o **VIN** (`09 02`, o número de identificação
do veículo).

**Fluxo em três etapas**

| Etapa | O que fazer | O que o app faz |
|---|---|---|
| **1. Nível antes** | Chegar na bomba, carro ligado e parado, e tocar em *Iniciar coleta* | Mede o nível e trava o valor quando ele estabiliza (cerca de 15 s) |
| **2. Abastecer** | Desligar o carro, abastecer e registrar a quantidade (em litros ou em R$) | Guarda a quantidade informada |
| **3. Nível depois** | Ligar o carro e tocar em *Fim do abastecimento* | Mede até o nível parar de subir (máximo de 3 min) e trava o valor |

**Resultado**

- nível antes, nível depois e nível esperado (`antes + litros ÷ capacidade do tanque × 100`)
- litros estimados pelo OBD comparados com os litros informados
- **consistente** se a diferença ficar dentro de 2 pontos percentuais, ou **alerta** se passar

**Como o app decide que o nível estabilizou**

O sensor de nível é uma boia: o valor oscila com o combustível balançando, e muitos carros filtram
a leitura de propósito, que sobe devagar depois de abastecer. Por isso o valor travado é a
**mediana** (o valor do meio, que ignora picos) das leituras dos últimos 30 s, aceita só quando:

- há pelo menos 6 leituras cobrindo pelo menos 15 s
- a variação entre as leituras é de até 1 ponto percentual
- o valor parou de subir ou descer (no máximo 0,5 ponto entre a primeira e a segunda metade da janela)

Se o carro andar (com o PID de velocidade disponível), a medição recomeça. Também dá para travar na
hora com *Usar valor atual*, e o resultado fica marcado como "sem estabilizar".

### Scanner

Coleta livre de PIDs, no estilo do OBDLink:

1. **Conectar** ao adaptador pareado. O app inicializa o ELM327 e mostra a versão e o protocolo.
2. **Buscar PIDs**: lista todos os PIDs do modo 01 que o veículo informa como suportados.
3. **Selecionar** os PIDs e os **calculados** (consumo instantâneo, Fuel Rate, CO2, potência, torque, distância...).
4. **Iniciar coleta**: uma tela mostra o trajeto no mapa, os itens coletados e a quantidade de linhas.
   O botão **Fim da volta** marca voltas de um percurso (coluna `Lap` do CSV).
5. **Parar coleta**: fecha o CSV e mostra onde ele foi salvo.

A gravação é de 1 linha por segundo (ou 2, 5 ou 10), sempre com o último valor de cada PID. PIDs
lentos (temperaturas, nível) são lidos com menos frequência, para os rápidos (rotação, velocidade,
MAF) atualizarem mais.

<details>
<summary><b>Fórmulas dos PIDs calculados</b></summary>

Ajustadas a um CSV real do OBDLink, com diferença relativa abaixo de 0,002 %:

| Coluna | Fórmula |
|---|---|
| Fuel Rate (l/hr) | MAF × 3600 / (AFR × densidade) = MAF × 0,33279 (AFR 14,7 e 0,7359 kg/L) |
| CO2 flow (g/s) | Fuel Rate × 2347,7 g/L / 3600 |
| Instant Fuel Economy (l/100 km) | Fuel Rate / velocidade × 100 |
| Engine Power (PS) | MAF × 1,188916 |
| Engine Torque (N•m) | Engine Power × 7219,6 / rpm |
| Mass air flow rate (calculated) | rpm/120 × MAP × cilindrada × eficiência volumétrica × M_ar / (R × T) |
| Trip Distance, Trip Fuel | integrais da velocidade e da Fuel Rate |
| Fuel Remaining (l) | nível de combustível × capacidade do tanque |

Assim como o OBDLink, as fórmulas assumem gasolina pura e não usam o teor de etanol nem as
correções de combustível. AFR, densidade, preço, tanque, cilindrada e eficiência volumétrica podem
ser alterados nos ajustes do Scanner.

</details>

### Telemetria do gêmeo digital

Ligada no Scanner, a telemetria prepara os dados para o gêmeo digital no BeamNG.tech, conforme a
especificação do projeto (Fase 0, coleta, e Fase 1, comunicação com o backend). Enquanto o CSV
continua a 1 Hz, a telemetria monta **pacotes JSON a 50 Hz** (10, 25, 50 ou 100 Hz), cada um com a
última leitura de cada fonte e o horário em que ela foi adquirida:

```json
{
  "session_id": "session_20261119_113700",
  "vehicle_id": "9BHBG51CAJP000000",
  "sequence": 1250,
  "gps": {"timestamp": 1794950000125, "latitude": -22.58912, "longitude": -43.28431,
          "altitude": 24.0, "speed": 15.2, "heading": 120.5,
          "horizontal_accuracy": 3.0, "speed_accuracy": 0.5},
  "imu": {"timestamp": 1794950000120,
          "accelerometer": {"x": 0.45, "y": 1.20, "z": 9.81},
          "gyroscope": {"x": 0.01, "y": 0.02, "z": 0.18}},
  "obd": {"timestamp": 1794950000115, "speed": 15.0, "rpm": 3200, "throttle_position": 35,
          "engine_load": 22.4, "coolant_temperature": 88, "accelerator_pedal_position": 24.3}
}
```

| Campo | Unidade e origem |
|---|---|
| `timestamp` | milissegundos desde 01/01/1970 (UTC), um por fonte |
| `gps.speed`, `obd.speed` | m/s (o OBD informa km/h e o app converte) |
| `gps.heading` | graus, 0 = norte, sentido horário |
| `imu.accelerometer` | m/s², com a gravidade e nos eixos do celular |
| `imu.gyroscope` | rad/s, nos eixos do celular |
| `obd` | velocidade (`01 0D`), rotação (`0C`), borboleta (`11`), carga (`04`), temperatura (`05`) e pedal D (`49`), os que o veículo suportar |
| bloco `null` | ainda sem leitura daquela fonte (ex.: GPS sem sinal) |

Os PIDs da telemetria são lidos mesmo sem estarem marcados na lista. A compensação da gravidade e a
mudança dos eixos do celular para os do veículo ficam para o backend (seção 5.2 da especificação).

**Arquivo JSON**: `Telemetria_AAAAMMDD_hhmmss.json`, uma lista JSON com um pacote por linha, salva
junto do CSV da mesma coleta. Ele abre no próprio app, no mesmo visualizador dos CSVs.

**WebSocket**: com *Enviar telemetria por WebSocket* ligado, os pacotes vão para
`ws://<servidor>/ws/vehicle/<session_id>` (o servidor é definido nas configurações da coleta, como
`ws://192.168.0.10:8000`, e aceita `wss://`). O cliente:

- reconecta sozinho, esperando 1, 2, 4, 8 e depois 10 s entre as tentativas
- guarda os pacotes numa fila enquanto não há conexão (até 6000, cerca de 2 min a 50 Hz) e os envia
  em ordem quando ela volta. Acima disso descarta os mais antigos e conta quantos
- numera os pacotes (`sequence`), para o backend identificar perdas
- mede a latência se o servidor responder `{"type": "ack", "sequence": n}`
- mostra na tela da coleta o estado da conexão, enviados, fila, descartados, reconexões, latência e a última falha

<details>
<summary><b>Servidor de teste em Python (FastAPI)</b></summary>

Enquanto o backend do projeto não existe, este servidor mínimo recebe os pacotes, responde o `ack`
e mostra o que chegou. Rode no PC na mesma rede do celular e use o IP do PC no app.

```python
# pip install fastapi uvicorn
# uvicorn servidor_teste:app --host 0.0.0.0 --port 8000
import json
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

app = FastAPI()

@app.websocket("/ws/vehicle/{session_id}")
async def veiculo(ws: WebSocket, session_id: str):
    await ws.accept()
    print("conectou:", session_id)
    try:
        while True:
            p = json.loads(await ws.receive_text())
            await ws.send_text(json.dumps({"type": "ack", "sequence": p["sequence"]}))
            if p["sequence"] % 50 == 0:
                obd, gps = p.get("obd") or {}, p.get("gps") or {}
                print(p["sequence"], "v_obd =", obd.get("speed"), "m/s",
                      "lat =", gps.get("latitude"), "lon =", gps.get("longitude"))
    except WebSocketDisconnect:
        print("desconectou:", session_id)
```

</details>

### Coletas salvas

Disponível no Abastecimento e no Scanner. Para cada arquivo, CSV ou JSON da telemetria:

- **Abrir no app**: mapa com o trajeto (início, fim e voltas), gráfico e tabela
  (no JSON, cada pacote vira uma linha e cada campo de GPS, OBD e IMU uma coluna, com as velocidades em km/h)
- **Abrir em outro aplicativo**
- **Compartilhar**: WhatsApp, e-mail, Drive e outros
- **Apagar**

O mapa usa o OpenStreetMap, sem chave de API, e escurece no modo escuro. Sem internet, o trajeto
continua desenhado sobre um fundo liso.

### Configuração

- ler o OBD-II (desligado, a coleta usa só o GPS) e gravar o GPS
- intervalo entre leituras
- taxa de gravação do CSV, GPS, acelerômetro e giroscópio
- **Leitura rápida**: envia o PID com o sufixo `1` (ex.: `010C1`), para o adaptador responder assim
  que a primeira central eletrônica responder. Desligue se vierem muitos valores vazios (alguns
  clones de ELM327 não aceitam).
- tema claro, escuro ou do sistema

---

## Arquivos gerados

Ficam em `Android/data/br.inmetro.fuelsentinel/files/coletas_obd/`, acessível pelo cabo USB no computador.

| Arquivo | Origem | Conteúdo |
|---|---|---|
| `CSVLog_AAAAMMDD_hhmmss.csv` | Scanner | PIDs, calculados, GPS, sensores e `Lap` |
| `Telemetria_AAAAMMDD_hhmmss.json` | Scanner | pacotes da telemetria do gêmeo digital ([formato](#telemetria-do-gêmeo-digital)) |
| `Abastecimento_AAAAMMDD_hhmmss.csv` | Abastecimento | nível, VIN, GPS e coluna `Evento` (nível antes, fim do abastecimento, nível depois, salvo) |
| `AAAA-MM-DD_hh-mm-ss.json` (na pasta `files/`, um nível acima) | Abastecimento | quantidade, níveis antes e depois com horário e se estabilizaram, litros estimados, diferença, foto da bomba (hash) e local |

**Formato do CSV** (igual ao do OBDLink, para os mesmos scripts lerem os dois):

- BOM UTF-8, cabeçalho separado por `, `, linhas por `,` e ponto decimal
- 1ª coluna `Time` no formato `09/30/2026 01:36:32.3944 PM`
- colunas com os nomes e unidades do OBDLink (`Engine RPM (RPM)`, `Fuel Rate (l/hr)`...)
- GPS: `Latitude (deg)`, `Longitude (deg)`, `Altitude (m)`, `GPS Speed (km/h)`, `GPS Accuracy (m)`
- sensores: `Accel X/Y/Z (m/s²)`, `Accel (Grav) X/Y/Z (m/s²)`, `Rotation Rate X/Y/Z (deg/s)`
- `PID refresh rate (Hz)` e `Elapsed time (sec)`

Diferenças em relação ao OBDLink: um PID que ainda não respondeu fica **vazio** (o OBDLink grava 0)
e os acumulados da viagem começam no início de cada coleta.

---

## Versões

| Versão | Onde está | Principais mudanças |
|---|---|---|
| **1.2.0** | branch `test` | Telemetria do gêmeo digital no Scanner: pacotes JSON de GPS, IMU e OBD a até 100 Hz, gravados em arquivo e enviados por WebSocket com reconexão, fila e sequência |
| **1.1.0** | branch `main` | Scanner com CSV no formato OBDLink, PIDs calculados, mapa e voltas · Abastecimento em 3 etapas com nível estabilizado e PIDs fixos · comunicação ELM327 por pergunta e resposta · coletas salvas com visualizador e compartilhamento · modo escuro · nova Configuração · leitura do VIN corrigida · ícone do app · envio para a AWS desativado |
| **1.0.0** | repositório original [`gabestk/fuel_sentinel`](https://github.com/gabestk/fuel_sentinel) | versão original, com escolha livre de PIDs no abastecimento e envio para a nuvem |

---

## Para desenvolvedores

### Requisitos

- Flutter **3.47.9** (a 3.48 exige Gradle 9, que o projeto ainda não usa)
- Android SDK e um celular Android com Bluetooth (o alvo principal)
- adaptador OBD-II ELM327 Bluetooth clássico, ou um emulador de ELM327

### Rodar

```bash
git clone https://github.com/gabestk/Fuel-Sentinel-V2.git
cd Fuel-Sentinel-V2
flutter pub get
flutter run
```

Depois de mudar rotas ou modelos do Hive, gere o código de novo:

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Build automático

A cada push, o GitHub Actions ([`testes.yml`](.github/workflows/testes.yml)) roda:

1. `flutter analyze` e `flutter test`
2. APK de teste (`fuel-sentinel-debug-apk`) e APK de uso (`fuel-sentinel-apk`) como artefatos
3. na branch `test`, publica o APK de uso na release [`teste`](https://github.com/gabestk/Fuel-Sentinel-V2/releases/tag/teste), o link de download fixo

### Estrutura

```
lib/
├── main.dart                 inicialização (Hive, Firebase, permissões)
├── functions/
│   ├── elm327.dart           comunicação com o adaptador: um comando por vez, espera o ">"
│   ├── obd_pids.dart         tabela de PIDs, interpretação das respostas e decodificação do VIN
│   ├── obd_calculados.dart   PIDs calculados
│   ├── nivel_estavel.dart    detecção de nível estável (mediana, dispersão e tendência)
│   ├── telemetria.dart       pacotes do gêmeo digital, arquivo JSON e cliente WebSocket
│   ├── csv_logger.dart       gravação do CSV linha a linha
│   ├── csv_leitor.dart       leitura do CSV para o visualizador
│   ├── json_leitor.dart      leitura do JSON da telemetria para o visualizador
│   └── pastas.dart           pasta das coletas
├── widgets/
│   ├── getdata.dart          aba Abastecimento (conexão)
│   ├── dataConnect.dart      coleta do abastecimento e fluxo em 3 etapas
│   ├── pidScanner.dart       aba Scanner
│   ├── csvViewer.dart        visualizador (mapa, gráfico e tabela)
│   ├── coletasSalvas.dart    lista de coletas (abrir, compartilhar, apagar)
│   ├── MapGps.dart           mapa do trajeto (OpenStreetMap)
│   └── conf.dart             Configuração
├── screens/                  páginas e rotas
├── route/                    auto_route
└── dataBaseClass/            modelos do Hive
test/
├── obd_pids_test.dart
├── nivel_estavel_test.dart
└── telemetria_test.dart
```

---

## Limitações conhecidas

- **Só Android**: o Bluetooth clássico (SPP) usado pelos adaptadores ELM327 não existe no iOS.
- **Boia não linear**: o sensor de nível é menos preciso perto do tanque vazio ou cheio. O resultado
  do abastecimento é um indicativo, e a curva pode ser calibrada por veículo.
- **Ignição desligada**: com o motor desligado a central eletrônica não responde, por isso o nível
  antes é medido com o carro ligado.
- **Protocolo automático**: a primeira consulta pode levar alguns segundos enquanto o adaptador
  descobre o protocolo do veículo.
