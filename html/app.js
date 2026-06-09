// vp_cityworks :: NUI dos 3 minigames — feito por LORD32 aka Vini32 e Dooc
// Audio sintetizado (WebAudio), visual CSS.
// Resultado unificado: POST minigameResult { success }.

const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'vp_cityworks';

const PALETTE = [
    { c: '#ff4545', dim: '#5a1a1a', glow: 'rgba(255,69,69,.7)' },
    { c: '#ffcf24', dim: '#5a4f12', glow: 'rgba(255,207,36,.7)' },
    { c: '#2dff42', dim: '#155a1d', glow: 'rgba(45,255,66,.7)' },
    { c: '#4aa3ff', dim: '#163a5a', glow: 'rgba(74,163,255,.7)' },
    { c: '#ffa500', dim: '#5a3a00', glow: 'rgba(255,165,0,.7)' },
    { c: '#b06bff', dim: '#3a1f5a', glow: 'rgba(176,107,255,.7)' },
];

let active = null; // 'weld' | 'panel' | 'wiring'

/* ----------------------- AUDIO (sintetizado) ----------------------- */
let actx = null;
let weldOsc = null, weldGain = null;
function ac() { if (!actx) actx = new (window.AudioContext || window.webkitAudioContext)(); return actx; }
function startWeldHum() {
    try {
        const c = ac();
        weldOsc = c.createOscillator(); weldGain = c.createGain();
        weldOsc.type = 'sawtooth'; weldOsc.frequency.value = 70; weldGain.gain.value = 0.06;
        weldOsc.connect(weldGain).connect(c.destination); weldOsc.start();
    } catch (e) {}
}
function stopWeldHum() {
    if (weldOsc) { try { weldOsc.stop(); } catch (e) {} weldOsc.disconnect(); weldOsc = null; }
    if (weldGain) { weldGain.disconnect(); weldGain = null; }
}
function beep(freq, dur, type = 'square', vol = 0.12) {
    try {
        const c = ac();
        const o = c.createOscillator(), g = c.createGain();
        o.type = type; o.frequency.value = freq; g.gain.value = vol;
        o.connect(g).connect(c.destination); o.start();
        g.gain.exponentialRampToValueAtTime(0.0001, c.currentTime + dur);
        o.stop(c.currentTime + dur);
    } catch (e) {}
}
const sndConnect = () => beep(880, 0.18, 'sine', 0.18);
const sndError   = () => beep(160, 0.25, 'sawtooth', 0.18);
const sndTick    = () => beep(1200, 0.03, 'square', 0.05);
const sndClick   = () => beep(520, 0.05, 'square', 0.10);

// ---- SFX em loop p/ acoes de mundo (drill/build/winch), acionado via NUI ----
const sfx = { nodes: [], interval: null };
function sfxStop() {
    if (sfx.interval) { clearInterval(sfx.interval); sfx.interval = null; }
    sfx.nodes.forEach(n => { try { n.stop && n.stop(); } catch (e) {} try { n.disconnect(); } catch (e) {} });
    sfx.nodes = [];
}
function sfxStart(type) {
    sfxStop();
    try {
        const c = ac(); if (c.state === 'suspended') c.resume();
        if (type === 'drill' || type === 'winch') {
            const o = c.createOscillator(), g = c.createGain();
            o.type = type === 'drill' ? 'sawtooth' : 'sine';
            o.frequency.value = type === 'drill' ? 95 : 70;
            g.gain.value = type === 'drill' ? 0.06 : 0.05;
            o.connect(g).connect(c.destination); o.start();
            sfx.nodes.push(o, g);
            if (type === 'drill') { // britadeira: tremolo "ratata"
                let on = true;
                sfx.interval = setInterval(() => { on = !on; g.gain.setTargetAtTime(on ? 0.07 : 0.0, c.currentTime, 0.004); }, 70);
            }
        } else if (type === 'build') { // marteladas ritmadas
            sfx.interval = setInterval(() => beep(140, 0.10, 'square', 0.10), 480);
        }
    } catch (e) {}
}

/* ----------------------- util ----------------------- */
const $ = (id) => document.getElementById(id);
function post(name, data) {
    fetch(`https://${RES}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data || {}),
    }).catch(() => {});
}
function hideAll() {
    ['weld', 'panel', 'wiring'].forEach(id => $(id).classList.add('hidden'));
}
function finish(success) {
    if (!active) return;
    if (active === 'weld') weldCleanup();
    active = null;
    hideAll();
    post('minigameResult', { success: !!success });
}

/* ============================================================
   1) SOLDA
============================================================ */
let weld = null, currentWeld = null;

function openWeld(s) {
    active = 'weld';
    weld = { total: s.wireCount || 4, wired: 0, attemptsLeft: s.maxFails || 3, timeLeft: s.time || 60, loop: null };
    const rows = $('weld-rows'); rows.innerHTML = '';
    for (let i = 0; i < weld.total; i++) {
        const col = PALETTE[i % PALETTE.length];
        const wire = document.createElement('div');
        wire.className = 'wire';
        wire.style.setProperty('--bright', col.c);
        wire.style.setProperty('--dim', col.dim);
        wire.style.setProperty('--glow', col.glow);
        const left = document.createElement('div'); left.className = 'terminal left';
        const core = document.createElement('div'); core.className = 'core';
        const right = document.createElement('div'); right.className = 'terminal right';
        left.addEventListener('mousedown', () => weldStart(wire, left));
        right.addEventListener('mousedown', () => weldStart(wire, right));
        left.addEventListener('mouseup', () => weldFinish(wire, left));
        right.addEventListener('mouseup', () => weldFinish(wire, right));
        wire.append(left, core, right);
        rows.appendChild(wire);
    }
    weldFails(); weldProg();
    $('weld').classList.remove('hidden');
    weldTimer(weld.timeLeft);
}
function weldStart(wire, term) {
    if (!weld || currentWeld || wire.classList.contains('wired')) return;
    currentWeld = { wire, term };
    document.body.style.cursor = 'none';
    $('torch').classList.remove('hidden');
    startWeldHum();
}
function weldFinish(wire, term) {
    if (!currentWeld || currentWeld.wire !== wire) return;
    const opposite = term !== currentWeld.term;
    weldEndDrag();
    if (opposite) {
        wire.classList.add('wired'); sndConnect(); weld.wired++; weldProg();
        if (weld.wired >= weld.total) finish(true);
    } else weldFail();
}
function weldCancelFail() { if (!currentWeld) return; weldEndDrag(); weldFail(); }
function weldEndDrag() {
    currentWeld = null; document.body.style.cursor = 'default';
    $('torch').classList.add('hidden'); stopWeldHum();
}
function weldFail() {
    sndError(); weld.attemptsLeft--; weldFails();
    if (weld.attemptsLeft <= 0) finish(false);
}
function weldFails() { $('weld-fails').textContent = '⬤ '.repeat(Math.max(0, weld.attemptsLeft)).trim(); }
function weldProg() { $('weld-progress').textContent = `${weld.wired} / ${weld.total}`; }
function fmt(s) { const m = Math.floor(s / 60), x = s % 60; return `${String(m).padStart(2,'0')}:${String(x).padStart(2,'0')}`; }
function weldTimer(sec) {
    const t = $('weld-timer'); t.textContent = fmt(sec); t.classList.remove('warn');
    weld.loop = setInterval(() => {
        weld.timeLeft--; sndTick();
        if (weld.timeLeft <= 0) { t.textContent = '00:00'; return finish(false); }
        t.textContent = fmt(weld.timeLeft);
        if (weld.timeLeft <= 10) t.classList.add('warn');
    }, 1000);
}
function weldCleanup() {
    if (weld && weld.loop) clearInterval(weld.loop);
    weldEndDrag(); weld = null;
}

/* ============================================================
   2) VOLTIMETRO / PAINEL
============================================================ */
let pano = null;

function openPanel(s) {
    active = 'panel';
    const count = s.panels || 12;
    pano = { count, broken: Math.floor(Math.random() * count), phase: 'find', screwsDone: 0 };
    const grid = $('panel-grid'); grid.innerHTML = '';
    for (let i = 0; i < count; i++) {
        const cell = document.createElement('div');
        cell.className = 'pano'; cell.dataset.i = i;
        grid.appendChild(cell);
    }
    $('panel-service').classList.add('hidden');
    $('panel-grid').classList.remove('hidden');
    $('panel-hint').innerHTML = 'Passe o <b>voltimetro</b> sobre os paineis e clique no que estiver com voltagem <b>anormal</b>.';
    $('panel-progress').textContent = 'Localize o painel defeituoso';
    $('volt-read').textContent = '--- V';
    $('volt-read').className = 'timer';
    $('panel').classList.remove('hidden');
    // reset parafusos/cover
    document.querySelectorAll('#panel-service .screw').forEach(sc => sc.classList.remove('gone'));
    $('service-cover').classList.add('hidden');
}
function panelHover(i) {
    if (!pano || pano.phase !== 'find') return;
    const v = $('volt-read');
    if (i === pano.broken) {
        v.textContent = (1 + Math.floor(Math.random() * 5)) + ' V';
        v.className = 'timer volt-read low';
    } else {
        v.textContent = (215 + Math.floor(Math.random() * 25)) + ' V';
        v.className = 'timer volt-read high';
    }
}
function panelClickCell(i) {
    if (!pano || pano.phase !== 'find') return;
    if (i !== pano.broken) { sndError(); return finish(false); } // painel errado = choque
    // entra em reparo
    sndClick();
    pano.phase = 'removing';
    $('panel-grid').classList.add('hidden');
    $('panel-service').classList.remove('hidden');
    $('service-step').textContent = 'Remova os 4 parafusos';
    $('panel-progress').textContent = 'Reparando painel';
}
function panelScrew(el) {
    if (!pano) return;
    if (pano.phase === 'removing' && !el.classList.contains('gone')) {
        el.classList.add('gone'); sndClick(); pano.screwsDone++;
        if (pano.screwsDone >= 4) {
            pano.screwsDone = 0; pano.phase = 'swap';
            $('service-cover').classList.remove('hidden');
            $('service-step').textContent = 'Clique para trocar o switch';
        }
    } else if (pano.phase === 'fastening' && el.classList.contains('gone')) {
        el.classList.remove('gone'); sndClick(); pano.screwsDone++;
        if (pano.screwsDone >= 4) { sndConnect(); finish(true); }
    }
}
function panelCover() {
    if (!pano || pano.phase !== 'swap') return;
    sndClick();
    $('service-cover').classList.add('hidden');
    document.querySelectorAll('#panel-service .screw').forEach(sc => sc.classList.add('gone'));
    pano.screwsDone = 0; pano.phase = 'fastening';
    $('service-step').textContent = 'Reaperte os 4 parafusos';
}

/* ============================================================
   3) FIACAO / ARRASTAR FIOS
============================================================ */
let wiring = null, dragWire = null;

function shuffle(a) { for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }

function openWiring(s) {
    active = 'wiring';
    const count = Math.min(s.count || 4, PALETTE.length);
    wiring = { count, connected: 0 };
    const plugs = $('plugs'), sockets = $('sockets');
    plugs.innerHTML = ''; sockets.innerHTML = '';
    $('wiring-svg').innerHTML = '';

    const order = []; for (let i = 0; i < count; i++) order.push(i);
    const socketOrder = shuffle([...order]);

    order.forEach(ci => {
        const p = document.createElement('div');
        p.className = 'node plug'; p.dataset.color = ci;
        p.style.setProperty('--c', PALETTE[ci].c);
        p.addEventListener('mousedown', (e) => wiringStart(e, p));
        plugs.appendChild(p);
    });
    socketOrder.forEach(ci => {
        const sk = document.createElement('div');
        sk.className = 'node socket'; sk.dataset.color = ci;
        sk.style.setProperty('--c', PALETTE[ci].c);
        sockets.appendChild(sk);
    });
    $('wiring-progress').textContent = `0 / ${count}`;
    $('wiring').classList.remove('hidden');
}
function svgRect() { return $('wiring-svg').getBoundingClientRect(); }
function centerOf(el) {
    const r = el.getBoundingClientRect(), s = svgRect();
    return { x: r.left + r.width / 2 - s.left, y: r.top + r.height / 2 - s.top };
}
function mkLine(x1, y1, color) {
    const ln = document.createElementNS('http://www.w3.org/2000/svg', 'line');
    ln.setAttribute('x1', x1); ln.setAttribute('y1', y1);
    ln.setAttribute('x2', x1); ln.setAttribute('y2', y1);
    ln.setAttribute('stroke', color); ln.setAttribute('stroke-width', '5');
    ln.setAttribute('stroke-linecap', 'round');
    $('wiring-svg').appendChild(ln);
    return ln;
}
function wiringStart(e, plug) {
    if (!wiring || plug.classList.contains('done')) return;
    const c = centerOf(plug);
    dragWire = { plug, line: mkLine(c.x, c.y, PALETTE[plug.dataset.color].c) };
}
function wiringMove(e) {
    if (!dragWire) return;
    const s = svgRect();
    dragWire.line.setAttribute('x2', e.clientX - s.left);
    dragWire.line.setAttribute('y2', e.clientY - s.top);
}
function wiringUp(e) {
    if (!dragWire) return;
    const target = document.elementFromPoint(e.clientX, e.clientY);
    const plug = dragWire.plug;
    if (target && target.classList.contains('socket') && !target.classList.contains('done')
        && target.dataset.color === plug.dataset.color) {
        const c = centerOf(target);
        dragWire.line.setAttribute('x2', c.x); dragWire.line.setAttribute('y2', c.y);
        plug.classList.add('done'); target.classList.add('done');
        sndConnect(); wiring.connected++;
        $('wiring-progress').textContent = `${wiring.connected} / ${wiring.count}`;
        dragWire = null;
        if (wiring.connected >= wiring.count) finish(true);
        return;
    }
    // errou: remove a linha temporaria
    dragWire.line.remove(); dragWire = null;
}

/* ============================================================
   ROTEADOR + EVENTOS GLOBAIS
============================================================ */
window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    switch (d.action) {
        case 'START_WELD':   openWeld(d.settings || {}); break;
        case 'START_PANEL':  openPanel(d.settings || {}); break;
        case 'START_WIRING': openWiring(d.settings || {}); break;
        case 'CLOSE':        finish(false); break;
        case 'HUD_SHOW':     hudShow(d.tasks, d.players); break;
        case 'HUD_TASKS':    hudTasks(d.tasks); break;
        case 'HUD_PLAYERS':  hudPlayers(d.players); break;
        case 'HUD_HIDE':     $('hud').classList.add('hidden'); break;
        case 'REWARD':       showReward(d.data); break;
        case 'SFX':          if (d.play) sfxStart(d.sfx); else sfxStop(); break;
    }
});

/* ============================================================
   HUD ao vivo + tela de recompensa (sem foco)
============================================================ */
function hudShow(tasks, players) { hudTasks(tasks); hudPlayers(players); $('hud').classList.remove('hidden'); }
function hudTasks(tasks) {
    if (!tasks) return;
    const c = $('hud-tasks'); c.innerHTML = '';
    Object.keys(tasks).forEach(k => {
        const t = tasks[k]; const done = t.made >= t.count;
        const row = document.createElement('div');
        row.className = 'hud-row' + (done ? ' done' : '');
        row.innerHTML = `<span class="lbl">${t.label || k}</span><span class="val">${t.made}/${t.count}</span>`;
        c.appendChild(row);
    });
}
function hudPlayers(players) {
    if (!players) return;
    const c = $('hud-players'); c.innerHTML = '';
    const arr = Array.isArray(players) ? players : Object.values(players);
    arr.forEach(p => {
        const row = document.createElement('div'); row.className = 'hud-row';
        row.innerHTML = `<span class="lbl">${p.name || '?'}</span><span class="val">${p.score || 0}</span>`;
        c.appendChild(row);
    });
}
let rewardTimer = null;
function showReward(data) {
    if (!data) return;
    $('reward-name').textContent = data.name || '';
    $('reward-money').textContent = '$' + Number(data.money || 0).toLocaleString('pt-BR');
    $('reward-xp').textContent = (data.xp || 0) + ' XP';
    $('reward-score').textContent = data.score || 0;
    $('hud').classList.add('hidden');
    $('reward').classList.remove('hidden');
    if (rewardTimer) clearTimeout(rewardTimer);
    rewardTimer = setTimeout(() => $('reward').classList.add('hidden'), 6000);
}

// delegacao de eventos do painel
$('panel-grid').addEventListener('mousemove', (e) => {
    const cell = e.target.closest('.pano'); if (cell) panelHover(parseInt(cell.dataset.i));
});
$('panel-grid').addEventListener('click', (e) => {
    const cell = e.target.closest('.pano'); if (cell) panelClickCell(parseInt(cell.dataset.i));
});
document.querySelectorAll('#panel-service .screw').forEach(sc => {
    sc.addEventListener('click', () => panelScrew(sc));
});
$('service-cover').addEventListener('click', panelCover);

// arrastar fios + solda (mouse global)
document.addEventListener('mousemove', (e) => {
    if (active === 'wiring') return wiringMove(e);
    if (active === 'weld' && currentWeld) {
        $('torch').style.left = e.clientX + 'px';
        $('torch').style.top = e.clientY + 'px';
        const r = currentWeld.wire.getBoundingClientRect(), m = 12;
        if (e.clientX < r.left - m || e.clientX > r.right + m || e.clientY < r.top - m || e.clientY > r.bottom + m) weldCancelFail();
    }
});
document.addEventListener('mouseup', (e) => {
    if (active === 'wiring') return wiringUp(e);
    if (active === 'weld') setTimeout(() => { if (currentWeld) weldCancelFail(); }, 30);
});
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && active) finish(false); });
