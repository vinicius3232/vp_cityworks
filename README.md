# vp_cityworks — Secretaria de Obras (multi-frente / SADOT)

Empresa de manutenção da cidade para **QBox** (nativo ox_lib/ox_inventory/ox_target), com **várias frentes de trabalho** cooperativas sob a mesma central.

**Frentes (6):** ⚡ Eletricista · 🛣️ Asfalto/Vias · 🏗️ Construção · 🪧 Sinalização · 💡 Iluminação · 🚛 Guincho.
**Modos de tarefa:** `minigame` (3 NUI: solda/voltímetro/fiação), `drill` (alvo com vida), `build` (progress+props), `tow` (rebocar veículo). **Dispatch sob demanda** (`/pedirservico`). Motor genérico (`Config.Disciplines`) — novas frentes entram só adicionando config.

> Script feito por **LORD32 aka Vini32 e Dooc**

## Stack (versões deste servidor)
- qbx_core 1.23.0 · ox_lib 3.32.2 · ox_inventory 2.44.8 · ox_target · ox_fuel · qbx_vehiclekeys · oxmysql

## Instalação
1. Importe o SQL:
   ```sql
   -- sql/migration.sql
   ```
2. `server.cfg` (dentro do grupo `[standalone]` já é `ensure`d automaticamente; **não** duplique):
   ```
   ensure vp_cityworks
   ```
3. (Opcional) log via Discord, sem token hardcoded:
   ```
   set vp_cityworks_webhook "https://discord.com/api/webhooks/..."
   ```

## Gameplay (resumo)
Pega ordem de serviço num NPC → cria lobby (até 4) → escolhe região → caminhão spawna → conserta alvos (transformador, quadro, poste de luz, semáforo, poste telefônico) via minigame → poste de luz/telefônico exigem **escada/lift** → todos OK → entrega o caminhão → recompensa (dinheiro dividido + XP, recompensa multiplica em coop).

## Arquitetura
- **Server-authoritative**: o servidor mantém `Lobbies[ownerCid]` e revalida lobby, proximity, cooldown e trava de concorrência em cada conserto. O client nunca decide recompensa.
- **Minigames** (seletor por tarefa em `Config.Minigames.byTask`) — **3 NUI custom** (`html/`), resultado unificado em `POST minigameResult`:
  - `welding` (solda, arrastar terminal→oposto) → `fixStreetLamp`, `phonePole`
  - `panel` (voltímetro: achar painel defeituoso + parafusos + switch) → `fixTrafo`, `fixHouseBoard`
  - `wiring` (arrastar fio ao conector da mesma cor) → `fixTrafficLamp`
  - `skillcheck` (ox_lib) fica como fallback.
- **Segurança** (`server/security.lua`): `getPlayer`, rate limit, proximity server-side, log opcional.

## Status por fase
| Fase | Item | Estado |
|------|------|--------|
| 1 | Fundação (manifest, config, SQL, ox_target, ped) | ✅ |
| 2 | Lobby coop (convite/aceite/kick/região/scoreboard) | ✅ (scoreboard = notify; NUI futura) |
| 3 | Missão (spawn veículo+keys+fuel, blips, fumaça, alvos) | ✅ |
| 4 | Minigames + 5 tarefas | ✅ **3 minigames NUI custom** (solda, painel/voltímetro, fiação) |
| 5 | Escada + Lift | ✅ escada + **lift móvel** (lógica do base: SlideObject + colisão, player sobe junto) |
| 6 | Recompensa + XP/level + persistência + hardening | ✅ |
| + | HUD ao vivo + tela de recompensa + 4 regiões + comando reset + blip do veículo | ✅ |

## TODO de fidelidade (restante, opcional)
- Extras cosméticos do veículo; menu de lobby em NUI custom (hoje ox_lib).
- Elevador (lift) móvel com controle de altura.
- Scoreboard/HUD visual ao vivo.
- Mais regiões em `config/config.lua` (formato pronto, 2 incluídas).
