# vp_cityworks — Documentação Técnica

**Secretaria de Obras (SADOT)** — empresa de manutenção da cidade para **QBox**, nativa em ox_lib / ox_inventory / ox_target. Várias **frentes de trabalho** cooperativas sob a mesma central, motor genérico por disciplina.

> Script feito por **LORD32 aka Vini32 e Dooc**

---

## 1. Stack (versões confirmadas neste servidor)

| Resource | Versão | Uso |
|----------|--------|-----|
| qbx_core | 1.23.0 | `GetPlayer`, `AddMoney`/`RemoveMoney`, `Notify`, `GetPlayerData` |
| ox_lib | 3.32.2 | callbacks, skillCheck, progressBar, alertDialog, notify, cache, points |
| ox_inventory | 2.44.8 | item obrigatório, itens de recompensa (`GetItemCount`/`AddItem`/`RemoveItem`) |
| ox_target | — | interação no NPC |
| ox_fuel | — | combustível via statebag `Entity(veh).state:set('fuel', x, true)` |
| qbx_vehiclekeys | — | `GiveKeys(src, veh, skipNotif)` |
| oxmysql | — | persistência (sempre `?`) |

OneSync `on`, Entity Lockdown `relaxed` (compatível com `CreateVehicleServerSetter`).

---

## 2. Instalação (plug & play)

**Multi-framework** (QBox/QBCore/ESX) — o core e as chaves de veículo são **auto-detectados** em runtime (`shared/framework.lua`). **Dependências** (comuns aos 3): ox_lib, ox_inventory, ox_target, oxmysql (+ ox_fuel opcional). Veículos são base game (sem stream); itens (`RequiredItem`/`RewardItems`) vêm **desligados** por padrão.

1. Soltar a pasta `vp_cityworks` em `resources/[standalone]/`.
2. `ensure vp_cityworks` (ou já sobe pelo grupo `[standalone]`). **Não importe SQL** — a tabela é criada sozinha no boot (`Config.AutoCreateTable = true`; `sql/migration.sql` é só referência/fallback).
3. ⚠️ **Substitui o `vp_electrician`** — não rode os dois juntos.
4. (Opcional) log Discord via convar: `set vp_cityworks_webhook "https://discord.com/api/webhooks/..."`
5. (Opcional) locale pt-BR: `setr ox:locale pt-br`.

> Para ativar itens (ferramenta obrigatória / itens de recompensa), basta adicionar os itens no `ox_inventory` e ligar `Config.RequiredItem`/`Config.RewardItems`.

---

## 3. Frentes de trabalho (`Config.Disciplines`)

O jogador interage no NPC → escolhe a **frente** → escolhe a **região/contrato** → inicia. Cada frente tem veículo, rótulos, regiões e modo de tarefa próprios.

| Frente (`id`) | Tarefas | Modo | Destaque |
|---------------|---------|------|----------|
| ⚡ `electrician` | trafo, quadro, poste de luz, poste telefônico, semáforo | minigame | escada/lift, 2 papéis (desligar tensão) |
| 🛣️ `roadwork` | buraco, bloqueio | drill | alvo com vida (britadeira) |
| 🏗️ `construction` | andaime, muro | build | progressbar + props |
| 🪧 `signage` | placa, faixa | build + minigame | instalar/pintar |
| 💡 `streetlight` | lâmpada | minigame | sem lift |
| 🚛 `towing` | rebocar veículo | tow | flatbed (`kind='towing'`) |
| 📡 `towers` | reparar torre de rádio | minigame | alvos dinâmicos do `vp_towers` (`kind='towers'`) |

`Config.DisciplineOrder` define a ordem no menu. Cada frente tem `minLevel` (gate de nível, validado no servidor).

---

## 4. Modos de tarefa (`discipline.taskMode[task]`)

O motor é genérico; cada tarefa tem um modo:

- **`minigame`** — abrir alvo (lock) → minigame → concluir. Pode exigir equipamento (`requiresEquipment`) e/ou desligar tensão (`needsPower`).
- **`drill`** — alvo com **vida** (`disc.drill[task].health`); cada batida (`hitTarget`, progressbar) decrementa, sincronizado (`targetHit`); conclui em 0.
- **`build`** — progressbar (`disc.build[task].time`) → conclui → **spawna prop** (`disc.build[task].prop`) sincronizado via `targetUpdated`.
- **`tow`** — frente `kind='towing'`: alvo é um **veículo**; carregar no flatbed → entregar (ver §6).

Falha de minigame → `ApplyShockDamage` (`-10..25 HP`). Conclusão centralizada em `completeTargetInternal` (exposta como `vpCompleteTarget`).

---

## 5. Os 3 minigames (NUI custom — `html/`)

Reescritos do zero. Visual CSS, **áudio sintetizado (WebAudio)**, sem assets proprietários. Resultado unificado: `POST minigameResult { success }`.

- **Solda** (`welding`) — arrastar a solda de um terminal ao **oposto**; timer + tentativas.
- **Painel/Voltímetro** (`panel`) — achar o painel de voltagem **anormal** → parafusos → switch → reapertar.
- **Fiação** (`wiring`) — arrastar cada fio ao conector da **mesma cor** (linhas SVG).

Seleção por tarefa: `discipline.minigames.byTask`. Fallback `skillcheck` (ox_lib).

### 5.1 Ponte de minigames externos (`Config.ExternalMinigames`)

Opt-in (`enable=false` por padrão). Permite que qualquer tarefa use minigames de **libs de terceiros** por export, sem nova dependência obrigatória.

- O roteador `StartMinigame` checa, **antes** dos NUI próprios, se o `kind` (valor em `byTask`) é uma chave em `Config.ExternalMinigames.games`. Se for → `StartExternal(spec)`.
- `spec = { resource, export, iterations, config }`. A ponte chama `exports[resource][export](iterations, config)` (via `pcall`) e trata o retorno **booleano** como sucesso.
- **Fallback robusto**: lib não iniciada ou export com erro → cai no `lib.skillCheck`. O jogador **nunca trava**.
- **Server-authoritative intacto**: a ponte é só client; o servidor segue validando `minSeconds`/proximity/`openBy` em `completeTarget`.
- **Presets prontos (bl_ui, MIT)** — assinaturas tiradas do código-fonte real: `Untangle`/`CircleSum`/`LightsOut`/`KeySpam` = `exports.bl_ui:Game(iterations, config) → boolean`. Para outras libs (glitch GPL-3.0 etc.), confirme a assinatura na versão instalada antes de habilitar.
- **Como ligar numa tarefa**: `discipline.minigames.byTask[task] = 'bl_untangle'` (chave de `.games`). Ex. já preparado/comentado na frente `towers` ("hack de antena").

---

## 6. Guincho (`kind='towing'`)

Reimplementado do zero (inspirado no 0r-towtruck, open source).

- `generateMission` sorteia `region.towCount` veículos de `disc.variants` (modelo + coords + motivo).
- `startJob` spawna o(s) flatbed(s) **e** os veículos quebrados (server-side).
- **Carregar** (`loadVehicle`): perto do veículo com um flatbed por perto → `AttachEntityToEntity` no bone do leito (`disc.attachOffset`).
- **Entregar** (`deliverTow`): num `disc.deliveryPoints` → deleta o veículo, paga via `vpCompleteTarget`.
- Concluídos todos → devolver o flatbed no depot (`region.deliveryCoords`) → pagamento.

⚠️ O attach do flatbed precisa de ajuste fino in-game (offset por modelo).

---

## 6.1 Manutenção de Torres (`kind='towers'`) — integração com `vp_towers`

Conserta as torres de rádio do resource externo `vp_towers` (que fornece cobertura de sinal para `vp_crimescene`/`vp_policejob`).

- `generateMission` (branch `kind='towers'`) lê `exports.vp_towers:GetTowers()` e coleta as torres **danificadas** (`health < integration.repairThreshold`). O **índice** do alvo é a posição real no array do `vp_towers` (usada no reparo).
- Se faltar trabalho e `integration.simulateDamage=true`, danifica torres saudáveis (`SetTowerHealth(i, damagedHealth)`) até ter `region.towCount` alvos.
- Alvos são `mode='minigame'` na **base** da torre (`equipped=true`, sem lift). Minigame de fiação (`minigames.byTask.fix='wiring'`).
- **Reparo** (em `completeTargetInternal`): ao concluir um alvo com `towerIndex`, o servidor chama `exports.vp_towers:SetTowerHealth(towerIndex, integration.repairTo)` (guardado por `GetResourceState`).
- `startJob` agora **gera a missão antes de cobrar** depósito/item: se `mission.remaining == 0` (sem `vp_towers` ou sem torres danificadas), aborta com `no_work_available` **sem cobrar nada**.
- **Desgaste opcional** (`server/towers.lua` + `Config.TowerWear`, *default off*): thread que degrada uma torre aleatória a cada `interval`, criando manutenção natural. ⚠️ afeta a cobertura de sinal — ligar com consciência.

> Integração 100% via exports do `vp_towers` (sem acoplamento de tabela/evento). Resource ausente → frente inerte.

---

## 7. Dispatch sob demanda (`Config.Dispatch`)

- Cidadão usa `/pedirservico` → escolhe a frente (em `Config.Dispatch.disciplines`) → paga taxa.
- Todas as **equipes em serviço** daquela frente recebem **blip (com rota) + notify** no local do cidadão.
- O atendimento/recompensa é RP (a equipe vai até lá). Server valida fundos e existência de equipe.

---

## 8. Arquitetura (server-authoritative)

O servidor é a única fonte de verdade. **Nunca confia** em coords/identificadores do client.

- `Lobbies[ownerCid]` = estado completo (players, `disciplineId`, região, missão, veículos).
- `PlayerLobby[citizenid]` = lookup reverso → o lobby é **derivado do `src`**.
- Cada conclusão revalida: lobby existe? job começou? alvo aberto **por este player**? **proximity server-side**? cooldown? **tempo mínimo** (anti-skip, `Config.Minigames.minSeconds`)?
- **Gate de nível** validado no servidor (`selectDiscipline`/`selectMission`/`startJob`).
- Recompensa só após o servidor confirmar o veículo no ponto de entrega (anti pagamento-duplo, `lobby.paid`).
- **Hardening**: todo `RegisterNetEvent` com `Security.canAct` (rate limit) + guards de tipo; `Security.isNear` (proximity); `Security.logSuspicious`.

### Contrato (resumo)
- **Callbacks:** `getProfile`, `openTarget`.
- **Eventos servidor:** `invite`, `acceptInvite`, `kickPlayer`, `selectDiscipline`, `selectMission`, `startJob`, `setRewardSplit`, `resetJob`, `completeTarget`, `cutPower`, `hitTarget`, `closeTarget`, `buildEquipment`, `removeEquipment`, `moveLift`, `loadVehicle`, `deliverTow`, `deliverVehicle`, `requestService`.
- **Eventos cliente:** `receiveInvite`, `refreshLobby`, `leftLobby`, `jobStarted`, `targetUpdated`, `targetHit`, `powerCut`, `refreshScore`, `jobComplete`, `jobReset`, `rewardScreen`, `equipmentBuilt`/`Removed`, `liftMove`, `towLoaded`, `towDelivered`, `serviceCall`.
- **NUI:** `START_WELD`/`START_PANEL`/`START_WIRING`/`CLOSE`/`HUD_*`/`REWARD`; callback `minigameResult`.

---

## 9. Referência de configuração (`config/config.lua`)

**Compartilhado (global):**
| Chave | Descrição |
|-------|-----------|
| `Interaction` | NPC (coords, ped, blip, distância) |
| `RequiredJob` | `'all'` ou `{ job = gradeMin }` |
| `MaxPlayersPerLobby` / `InviteMaxDistance` / `JobResetCommand` | coop |
| `Cooldowns` | rate limits por evento |
| `VehicleDeposit` / `RequiredItem` / `RewardItems` / `BossRewardSplit` | economia |
| `Dispatch` | serviço sob demanda (command, fee, disciplines) |
| `Equipment` | escada/lift |
| `WorkClothes` / `RedArrowMarker` | cloakroom / seta |
| `Minigames.failDamage` / `minSeconds` | dano / anti-skip |
| `ExternalMinigames` | ponte opcional p/ libs externas (bl_ui/glitch) por export |
| `TowerWear` | desgaste opcional das torres do `vp_towers` |
| `MaxLevel` / `RequiredXP` | progressão |
| `LogWebhookConvar` | webhook por convar |

**Por frente (`Config.Disciplines[id]`):**
`label`, `icon`, `minLevel`, `kind?`, `vehicle`, `taskLabels`, `requiresEquipment`, `needsPower?`, `targetRadius`, `taskMode`, `drill?`, `build?`, `minigames?`, `clothes?`, `trafficLightModels?`, `variants?`/`deliveryPoints?` (towing), `regions` (key, title, minLevel, awards, spawn, delivery, jobTasks+pools | towCount).

---

## 10. Mapa de arquivos

```
config/config.lua      frentes (Disciplines), config global, dispatch
shared/utils.lua       discipline()/region(), recompensa coop, sorteio, XP
server/database.lua    queries oxmysql (?)
server/security.lua    getPlayer, rate limit, proximity, log
server/main.lua        lobby, frentes, convites, start, veículo, gate, mission
server/missions.lua    conclusão (minigame/drill/build), equipamento, lift, power
server/towing.lua      carregar/entregar veículo (guincho)
server/towers.lua      desgaste opcional de torres (Config.TowerWear)
server/dispatch.lua    serviço sob demanda
server/rewards.lua     entrega, pagamento (split/depósito), XP, persistência
client/main.lua        ped, ox_target, menu (frente→região), lobby, reset cmd
client/mission.lua     blips, markers, alvos (modos), entrega, HUD, cloakroom, seta
client/equipment.lua   escada + lift móvel (SlideObject)
client/minigames.lua   roteador NUI/skillcheck + dano
client/towing.lua      loop de reboque (carregar/entregar/attach)
client/dispatch.lua    /pedirservico + blip do chamado
html/                  index.html · style.css · app.js (minigames + HUD + recompensa)
sql/migration.sql      tabela vp_cityworks (PK)
```

---

## 11. Pendências de ajuste in-game

Tudo o que depende de física/mundo (não dá pra validar fora do servidor):
- **Lift** (escada/elevador): velocidade/altura/“pegada” do player.
- **Guincho**: offset do attach no flatbed (idealmente por modelo).
- **Coords** das frentes novas (asfalto/construção/sinalização/guincho) — posicionar no mapa real.

O resto (lógica, eventos, NUI) está verificado: eventos client↔server casados, callbacks casados, 52/52 locale keys, manifest completo, Lua balanceado.

---

## 12. Auditoria (4 dimensões)

Última auditoria: **0 críticos, 0 altos**.
- **Performance**: sem loop sem `Wait()`, sem `PlayerPedId()` em loop (`cache.ped`), sem `GetGamePool`/`GetDistanceBetweenCoords`, Waits adaptativos (`Wait(sleep)`), threads dormem 1000ms idle. Semáforo com **entidade cacheada + throttle 250ms**; seta vermelha raio 35m. Resmon: idle ~0.00–0.01ms, job ativo ~0.01–0.02ms.
- **Segurança**: 19/19 eventos validam source (`canAct` + guards de tipo + `isNear`), anti-skip (`minSeconds`), anti pagamento-duplo, gate de nível server-side, anti convite-spoof, log de suspeitos. *Limitação conhecida:* resultado de minigame é client-side (mitigado por minSeconds+proximity+lock).
- **Qualidade**: `lib.notify`/`progressBar`/`callback`/`skillCheck`, `ox_target`, config separado, i18n 52/52 (pt-br=en).
- **DB**: 100% parametrizado (`?`), PK em `citizenid`, colunas específicas, `.await` em coroutine.

---

## 13. Troubleshooting

| Sintoma | Causa provável |
|---------|----------------|
| Menu não abre | `RequiredJob` ou ox_target ausente |
| Duas Secretarias / NPC duplo | `vp_electrician` antigo ainda ativo — desabilite |
| Veículo não spawna | Entity Lockdown / modelo inválido |
| Sem combustível | ox_fuel espera statebag `fuel` (setado no spawn) |
| Minigame não aparece | `ui_page`/`files` no manifest; cache NUI (restart) |
| Não paga recompensa | veículo precisa estar no ponto de entrega |
| Frente nova "no chão"/longe | coords de config a posicionar no mapa |
| Texto em inglês | `setr ox:locale pt-br` |
