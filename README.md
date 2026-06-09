# vp_cityworks — Secretaria de Obras (multi-frente / SADOT)

Empresa de manutenção da cidade para **QBox** (nativo ox_lib/ox_inventory/ox_target), com **várias frentes de trabalho** cooperativas sob a mesma central.

**Frentes (6):** ⚡ Eletricista · 🛣️ Asfalto/Vias · 🏗️ Construção · 🪧 Sinalização · 💡 Iluminação · 🚛 Guincho.
**Modos de tarefa:** `minigame` (3 NUI: solda/voltímetro/fiação), `drill` (alvo com vida), `build` (progress+props), `tow` (rebocar veículo). **Dispatch sob demanda** (`/pedirservico`). Motor genérico (`Config.Disciplines`) — novas frentes entram só adicionando config.

> Script feito por **LORD32 aka Vini32 e Dooc**

## Stack
- **Core (auto-detect):** qbx_core · qb-core · es_extended
- **Comuns:** ox_lib · ox_inventory · ox_target · oxmysql (+ ox_fuel opcional)
- **Chaves (auto):** qbx_vehiclekeys · qb-vehiclekeys · wasabi_carlock (ou `Config.GiveKeysFn`)

## Instalação (plug & play)
1. **Não precisa importar SQL** — a tabela `vp_cityworks` é criada sozinha ao iniciar (`Config.AutoCreateTable`). `sql/migration.sql` fica só como referência.
2. O grupo `[standalone]` já é `ensure`d — **não** duplique. Para forçar: `ensure vp_cityworks`.
3. ⚠️ **Substitui o `vp_electrician`** — não rode os dois juntos (duplica NPC/tabela). No servidor de dev a pasta antiga já foi removida.
4. (Opcional) log Discord por convar: `set vp_cityworks_webhook "https://discord.com/api/webhooks/..."`
5. (Opcional) pt-BR: `setr ox:locale pt-br`.

## Gameplay (resumo)
NPC → escolhe **frente** → escolhe **região** → cria lobby (até 4) → caminhão spawna (chave+fuel) →
executa as tarefas conforme o modo da frente (minigame / britadeira / construção / reboque) →
entrega o veículo no depot → **recompensa** (dinheiro dividido + XP, multiplica em coop, depósito reembolsado).

## Arquitetura (resumo)
- **Server-authoritative**: `Lobbies[ownerCid]` derivado do `src`; revalida lobby, proximity, cooldown,
  trava de concorrência, anti-skip e gate de nível em cada conclusão. O client nunca decide recompensa.
- **Multi-framework** (QBox/QBCore/ESX, auto-detect via `shared/framework.lua`).
- **Motor por frente** (`Config.Disciplines`) com 4 modos de tarefa: `minigame` (3 NUI: solda/voltímetro/fiação),
  `drill` (alvo com vida + SFX britadeira), `build` (progress+props + SFX martelo), `tow` (guincho/flatbed + SFX winch).
- **Menu em NUI custom** (não ox_lib): frentes, contratos, equipe, boss split.
- **Dispatch** (`/pedirservico`): cidadão chama, equipe em serviço recebe o chamado.
- **Hardening completo** (`server/security.lua`): rate limit + guards de tipo + proximity em todos os eventos.

## Status
| Fase | Item | Estado |
|------|------|--------|
| 1 | Motor multi-frente + eletricista completo (3 minigames, lift, HUD, recompensa) | ✅ |
| 1 | Extras: depósito, item obrigatório, itens de recompensa, boss split, 2 papéis, cloakroom, seta | ✅ |
| 2 | Modos de tarefa `drill` + `build` | ✅ |
| 3 | Frentes Asfalto / Construção / Sinalização / Iluminação | ✅ |
| 4 | Frente Guincho (`tow`) | ✅ |
| 5 | Dispatch sob demanda | ✅ |
| 6 | Docs + precheck (eventos/callbacks/locales casados, manifest, balance) | ✅ |
| 🔍 | Auditoria 4 dimensões: **0 críticos, 0 altos** (perf otimizada, segurança/DB ok) | ✅ |

## Ajuste in-game pendente (física/mundo)
- "Pegada" do **lift** e offset do **attach do flatbed** (guincho).
- **Coords** das frentes novas (asfalto/construção/sinalização/guincho) — posicionar no mapa real.

Detalhes técnicos: ver `DOCUMENTATION.md`. Roadmap das fases: `ROADMAP.md`.
