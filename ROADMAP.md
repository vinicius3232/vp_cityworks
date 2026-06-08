# vp_cityworks — Roadmap de implementação (SADOT multi-frente)

Plano completo das ideias discutidas. Cada fase é um commit no repo.

## ✅ Fase 1 — Motor multi-frente (feito)
- `Config.Disciplines` + `Utils.discipline` + `ActiveDiscipline`. Eletricista como 1ª frente.
- Lobby coop, recompensa dividida, depósito de veículo, boss split, item obrigatório,
  itens de recompensa, XP/nível com gate, hardening, HUD, tela de recompensa.
- Extras 17mov: 2 papéis (desligar tensão), cloakroom, seta vermelha.
- 3 minigames NUI (solda, painel/voltímetro, fiação). Lift móvel + escada.

## 🔧 Fase 2 — Modos de tarefa (motor)
Generalizar a interação por `mode` por tarefa (`discipline.taskMode[task]`):
- `minigame` (atual) — abrir → minigame → concluir.
- `drill` — alvo com VIDA; bater N vezes (progressbar por batida), sincronizado.
  Recria o road worker (NCZ). Server: `hitTarget` decrementa health; conclui em 0.
- `build` — progressbar → spawna prop(s) no alvo → conclui. Recria a construção (Hiype).
- `vehicle` (guincho) — frente especial: alvo é um VEÍCULO (spawn) → prender (flatbed/corda)
  → entregar. Fluxo próprio (towing).

## 🛣️ Fase 3 — Frentes novas (config + modos)
- **Asfalto / Vias** (`drill`): tapar buraco / remover bloqueio com britadeira.
- **Construção / Obra** (`build`): montar andaime/estrutura (progress + props).
- **Sinalização** (`build`/minigame): instalar placa / repintar faixa.
- **Iluminação pública** (`minigame`): trocar lâmpada (variação do eletricista, sem lift).

## 🚛 Fase 4 — Frente Guincho (modo `vehicle`)
Inspiração: 0r-towtruck (open source, 0resmon) — reimplementado do zero, creditado.
- Alvo = veículo quebrado (pool com motivo/dano). Spawn → blip → prender no flatbed
  (`AttachEntityToEntity` no bone bodyshell, posição por modelo) ou corda/gancho
  (`AddRope`) → blip de entrega → entregar → pagar + XP.
- Veículo do job = flatbed; bed sobe/desce.

## 📞 Fase 5 — Dispatch sob demanda (transversal)
- Cidadão (jogador) chama um serviço (guincho/eletricista) com `/pedirservico`.
- Equipes em serviço daquela frente recebem o chamado e podem aceitar.
- Taxa do chamado cobrada do cidadão.

## 📚 Fase 6 — Fechamento
- DOCUMENTATION atualizada, precheck, commit/push final.

## Notas
- Crédito de inspiração nas refs (17mov, NCZ, Hiype, 0r-towtruck) no DOCUMENTATION.
- Sem in-game test: marcar o que exige validação no servidor (física do lift/flatbed/rope).
