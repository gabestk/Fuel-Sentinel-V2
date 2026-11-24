# Fuel Sentinel V2

App Flutter (Android) que lê o veículo por um adaptador OBD-II ELM327 via
Bluetooth clássico e grava os dados no celular. Faz parte da tese de doutorado do
autor (gêmeo digital veicular) e da frente AIDA-C. O README explica as funções.

A sessão principal é a **líder da equipe**: recebe o pedido, divide o trabalho
entre os agentes de `.claude/agents/` e confere o resultado antes de entregar.
Agentes não chamam outros agentes.

## Equipe

| Agente | Camada | Arquivos principais |
|---|---|---|
| `app-interface` | telas e navegação | `lib/widgets/`, `lib/screens/`, `lib/route/` |
| `app-dados-obd` | comunicação e dados | `lib/functions/` (ELM327, PIDs, CSV, JSON, telemetria) |
| `app-backend` | servidor FastAPI (quando existir) | `backend/` |
| `app-testador` | testes e CI | `test/`, `.github/workflows/` |

Mudança que cruza camadas (ex.: um dado novo na telemetria que aparece numa
tela) vai primeiro ao `app-dados-obd`, depois ao `app-interface`, e no fim ao
`app-testador`.

## Como trabalhar neste repositório

- Mudanças vão para a branch `test`. A `main` só recebe o que já foi testado no
  celular, quando o autor pedir.
- Commits só com o nome do autor: `git -c user.name="Gabriel Trajano"
  -c user.email="131036391+gabestk@users.noreply.github.com" commit`, sem
  linhas de coautoria.
- Não há Flutter local garantido: o CI (`.github/workflows/testes.yml`) roda
  `flutter analyze`, `flutter test` e gera os APKs. O APK de uso sai assinado com
  a chave dos Secrets e é publicado na release `teste`.
- Pacote do app: `br.inmetro.fuelsentinel`. O pacote Dart continua `obdapp`.
- `lib/route/autoroute.gr.dart` é gerado, mas é editado à mão quando muda uma rota.
- Atualize o README junto com qualquer mudança de funcionalidade.
- Ícone próprio em `assets/icon/`: não voltar ao ícone padrão.
