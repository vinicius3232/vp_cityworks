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
    ['weld', 'panel', 'wiring', 'hammer'].forEach(id => $(id).classList.add('hidden'));
}
function finish(success) {
    if (!active) return;
    if (active === 'weld') weldCleanup();
    if (active === 'hammer') hammerCleanup();
    if (active === 'panel') panelCleanup();
    active = null;
    hideAll();
    post('minigameResult', { success: !!success });
}

/* ============================================================
   1) SOLDA — tracar a trinca com o macarico (estilo realista)
   Segure e arraste o macarico sobre a linha em zigue-zague: a solda
   derrete/preenche atras com brilho + faiscas. Sair da linha esfria.
============================================================ */
let weld = null;
const WELD = { TOL: 26, STEP: 48, OFF_MAX: 20, GRAB: 48, W: 600, H: 360 };

function openWeld(s) {
    active = 'weld';
    weld = {
        total: Math.max(1, s.wireCount || 3), done: 0,
        attemptsLeft: s.maxFails || 3, timeLeft: s.time || 60,
        loop: null, welding: false, pts: [], cum: [], len: 0, prog: 0, off: 0,
    };
    weldFails(); weldProg();
    $('weld').classList.remove('hidden');
    weldTimer(weld.timeLeft);
    weldNewSeam();
    $('weld-svg').onmousedown = weldDown;
}

// gera uma trinca em zigue-zague (vertical, alternando lados)
function weldNewSeam() {
    const W = WELD.W, H = WELD.H;
    const segs = 5 + Math.floor(Math.random() * 3); // 5-7 dobras
    const cx = 210 + Math.random() * 180;
    const pts = [];
    for (let i = 0; i <= segs; i++) {
        const y = 34 + (H - 68) * (i / segs);
        const edge = (i === 0 || i === segs);
        const dir = (i % 2 === 0) ? -1 : 1;
        const off = edge ? (Math.random() * 30 - 15) : dir * (52 + Math.random() * 64);
        pts.push({ x: cx + off, y });
    }
    const cum = [0]; let len = 0;
    for (let i = 1; i < pts.length; i++) {
        len += Math.hypot(pts[i].x - pts[i-1].x, pts[i].y - pts[i-1].y);
        cum.push(len);
    }
    weld.pts = pts; weld.cum = cum; weld.len = len; weld.prog = 0; weld.off = 0;

    const d = 'M ' + pts.map(p => `${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(' L ');
    const a = pts[0], b = pts[pts.length - 1];
    $('weld-svg').classList.remove('warn');
    $('weld-svg').innerHTML =
        `<defs><linearGradient id="wfill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stop-color="#ffe27a"/><stop offset=".5" stop-color="#ff7b00"/><stop offset="1" stop-color="#ff3b30"/>
        </linearGradient></defs>
        <path class="weld-base" d="${d}"/>
        <path id="weld-fill" class="weld-fill" d=""/>
        <circle class="weld-node start" cx="${a.x.toFixed(1)}" cy="${a.y.toFixed(1)}" r="9"/>
        <circle class="weld-node end" cx="${b.x.toFixed(1)}" cy="${b.y.toFixed(1)}" r="9"/>`;
}

function weldSvgPoint(e) {
    const r = $('weld-svg').getBoundingClientRect();
    return { x: (e.clientX - r.left) / r.width * WELD.W, y: (e.clientY - r.top) / r.height * WELD.H };
}
function weldPointAt(arc) {
    const { pts, cum } = weld;
    for (let i = 1; i < cum.length; i++) {
        if (arc <= cum[i]) {
            const t = (arc - cum[i-1]) / ((cum[i] - cum[i-1]) || 1);
            return { x: pts[i-1].x + (pts[i].x - pts[i-1].x) * t, y: pts[i-1].y + (pts[i].y - pts[i-1].y) * t };
        }
    }
    return pts[pts.length - 1];
}
function weldProject(p) {
    const { pts, cum } = weld;
    let best = { arc: 0, dist: 1e9 };
    for (let i = 1; i < pts.length; i++) {
        const ax = pts[i-1].x, ay = pts[i-1].y, dx = pts[i].x - ax, dy = pts[i].y - ay;
        const l2 = dx*dx + dy*dy || 1;
        let t = ((p.x - ax) * dx + (p.y - ay) * dy) / l2; t = Math.max(0, Math.min(1, t));
        const dist = Math.hypot(p.x - (ax + dx*t), p.y - (ay + dy*t));
        if (dist < best.dist) best = { arc: cum[i-1] + t * Math.hypot(dx, dy), dist };
    }
    return best;
}
function weldDown(e) {
    if (!weld || weld.welding) return;
    const head = weldPointAt(weld.prog), p = weldSvgPoint(e);
    if (Math.hypot(p.x - head.x, p.y - head.y) > WELD.GRAB) return; // tem de pegar do ponto atual
    weld.welding = true;
    $('torch').classList.remove('hidden');
    document.body.style.cursor = 'none';
    startWeldHum();
    weldMove(e);
}
function weldMove(e) {
    if (!weld || !weld.welding) return;
    $('torch').style.left = e.clientX + 'px';
    $('torch').style.top = e.clientY + 'px';
    const pr = weldProject(weldSvgPoint(e));
    if (pr.dist > WELD.TOL || pr.arc > weld.prog + WELD.STEP) { // fora da linha / pulou
        weld.off++;
        $('weld-svg').classList.add('warn');
        if (weld.off >= WELD.OFF_MAX) weldStrayFail();
        return;
    }
    $('weld-svg').classList.remove('warn');
    weld.off = Math.max(0, weld.off - 1);
    if (pr.arc > weld.prog) {
        weld.prog = pr.arc;
        weldDrawFill();
        weldSparks(e.clientX, e.clientY);
        sndTick();
        if (weld.prog >= weld.len * 0.985) weldSeamDone();
    }
}
function weldDrawFill() {
    const { pts, cum, prog } = weld;
    let d = `M ${pts[0].x.toFixed(1)} ${pts[0].y.toFixed(1)}`;
    for (let i = 1; i < cum.length; i++) {
        if (cum[i] <= prog) { d += ` L ${pts[i].x.toFixed(1)} ${pts[i].y.toFixed(1)}`; }
        else { const hp = weldPointAt(prog); d += ` L ${hp.x.toFixed(1)} ${hp.y.toFixed(1)}`; break; }
    }
    const f = $('weld-fill'); if (f) f.setAttribute('d', d);
}
function weldSeamDone() {
    sndConnect();
    const f = $('weld-fill'); if (f) f.classList.add('done');
    weld.done++; weldProg();
    weld.welding = false; weldEndDrag();
    if (weld.done >= weld.total) return finish(true);
    setTimeout(() => { if (active === 'weld') weldNewSeam(); }, 380);
}
function weldStrayFail() {
    sndError(); weld.off = 0; weld.welding = false; weldEndDrag();
    weld.attemptsLeft--; weldFails();
    if (weld.attemptsLeft <= 0) return finish(false);
    weld.prog = 0; weldDrawFill(); // recomeca a costura atual
}
function weldUp() {
    if (!weld || !weld.welding) return;
    weld.welding = false; weldEndDrag();
}
function weldEndDrag() {
    document.body.style.cursor = 'default';
    $('torch').classList.add('hidden'); stopWeldHum();
}
function weldSparks(x, y) {
    for (let i = 0; i < 3; i++) {
        const s = document.createElement('div'); s.className = 'spark';
        s.style.left = x + 'px'; s.style.top = y + 'px';
        s.style.setProperty('--dx', (Math.random() * 44 - 22) + 'px');
        s.style.setProperty('--dy', (Math.random() * 30 + 8) + 'px');
        document.body.appendChild(s);
        setTimeout(() => s.remove(), 460);
    }
}
function weldFails() { $('weld-fails').textContent = '⬤ '.repeat(Math.max(0, weld.attemptsLeft)).trim(); }
function weldProg() { $('weld-progress').textContent = `${weld.done} / ${weld.total}`; }
function fmt(s) { const m = Math.floor(s / 60), x = s % 60; return `${String(m).padStart(2,'0')}:${String(x).padStart(2,'0')}`; }
function weldTimer(sec) {
    const t = $('weld-timer'); t.textContent = fmt(sec); t.classList.remove('warn');
    weld.loop = setInterval(() => {
        weld.timeLeft--;
        if (weld.timeLeft <= 0) { t.textContent = '00:00'; return finish(false); }
        t.textContent = fmt(weld.timeLeft);
        if (weld.timeLeft <= 10) t.classList.add('warn');
    }, 1000);
}
function weldCleanup() {
    if (weld && weld.loop) clearInterval(weld.loop);
    document.querySelectorAll('.spark').forEach(s => s.remove());
    weldEndDrag(); weld = null;
}

/* ============================================================
   2) VOLTIMETRO / PAINEL
============================================================ */
let pano = null;

function openPanel(s) {
    active = 'panel';
    stopMeterTone();
    const count = s.panels || 12;
    pano = { count, broken: Math.floor(Math.random() * count), phase: 'find', screwsDone: 0,
        wrong: 0, maxWrong: (s.maxWrong != null ? s.maxWrong : 2), hoverCell: null, measuredCell: null, measuring: null };
    const grid = $('panel-grid'); grid.innerHTML = '';
    for (let i = 0; i < count; i++) {
        const cell = document.createElement('div');
        cell.className = 'pano'; cell.dataset.i = i;
        if (s.image) { // hook: foto propria/livre no disjuntor
            cell.classList.add('img');
            cell.style.backgroundImage = `url("${s.image}")`;
        } else { // disjuntor estilizado (4 parafusos nos cantos + alavanca)
            cell.innerHTML = '<span class="brk-screw s1"></span><span class="brk-screw s2"></span>' +
                '<span class="brk-screw s3"></span><span class="brk-screw s4"></span><span class="brk-lever"></span>';
        }
        grid.appendChild(cell);
    }
    $('panel-service').classList.add('hidden');
    $('panel-grid').classList.remove('hidden');
    $('panel-hint').innerHTML = 'Passe o <b>multimetro</b> sobre os disjuntores e clique no que estiver com voltagem <b>anormal</b>.';
    $('panel-progress').textContent = 'Localize o disjuntor defeituoso';
    $('mm-read').textContent = '000';
    $('mm-read').className = 'mm-read';
    $('panel').classList.remove('hidden');
    // reset parafusos/cover
    document.querySelectorAll('#panel-service .screw').forEach(sc => sc.classList.remove('gone'));
    $('service-cover').classList.add('hidden');
    // placa de reparo usa a MESMA foto do disjuntor (se houver)
    const sb = $('service-board');
    if (s.image) { sb.classList.add('img'); sb.style.backgroundImage = `url("${s.image}")`; }
    else { sb.classList.remove('img'); sb.style.backgroundImage = ''; }
    const pb = $('mm-probe'); if (pb) pb.style.display = 'block'; // mostra a ponteira
}
function moveProbe(e) {
    const p = $('mm-probe'); if (!p) return;
    p.style.left = e.clientX + 'px'; p.style.top = e.clientY + 'px';
}
// ---- C: tom do multimetro (continuidade) ----
let meterOsc = null, meterGain = null;
function startMeterTone(broken) {
    stopMeterTone();
    try {
        const c = ac(); if (c.state === 'suspended') c.resume();
        meterOsc = c.createOscillator(); meterGain = c.createGain();
        meterOsc.type = 'sine';
        meterOsc.frequency.value = broken ? 200 : 640; // grave = defeito, agudo = normal
        meterGain.gain.value = 0.04;
        meterOsc.connect(meterGain).connect(c.destination); meterOsc.start();
        if (broken) { // defeito: tom intermitente (sem continuidade)
            let on = true;
            meterGain._iv = setInterval(() => { on = !on; meterGain.gain.setTargetAtTime(on ? 0.05 : 0.0, c.currentTime, 0.01); }, 180);
        }
    } catch (e) {}
}
function stopMeterTone() {
    if (meterGain && meterGain._iv) clearInterval(meterGain._iv);
    if (meterOsc) { try { meterOsc.stop(); } catch (e) {} meterOsc.disconnect(); meterOsc = null; }
    if (meterGain) { meterGain.disconnect(); meterGain = null; }
}
// acende a luz do voltimetro (verde=normal, vermelho=defeito, null=apaga)
function mmLights(broken) {
    document.querySelectorAll('#mm .mm-light').forEach(l => l.classList.remove('on'));
    if (broken === null) return;
    const lit = document.querySelector('#mm .mm-light.' + (broken ? 'red' : 'green'));
    if (lit) lit.classList.add('on');
}
// ---- A: medir segurando (flutua -> estabiliza) ----
function stopMeasure() { if (pano && pano.measuring) { clearInterval(pano.measuring); pano.measuring = null; } }
function startMeasure(i) {
    stopMeasure(); stopMeterTone();
    const v = $('mm-read');
    const broken = (i === pano.broken);
    const real = broken ? (1 + Math.floor(Math.random() * 5)) : (215 + Math.floor(Math.random() * 25));
    let elapsed = 0; const total = 650;
    pano.measuring = setInterval(() => {
        if (!pano || pano.phase !== 'find') { stopMeasure(); return; }
        elapsed += 60;
        if (elapsed < total) { // leitura instavel enquanto mede
            v.textContent = String(Math.floor(Math.random() * 260)).padStart(3, '0');
            v.className = 'mm-read';
            sndTick();
        } else { // estabiliza
            v.textContent = String(real).padStart(3, '0');
            v.className = 'mm-read ' + (broken ? 'low' : 'high');
            pano.measuredCell = i;
            startMeterTone(broken);
            mmLights(broken);
            stopMeasure();
        }
    }, 60);
}
function panelHover(i) {
    if (!pano || pano.phase !== 'find') return;
    if (pano.hoverCell === i) return; // ja medindo este
    pano.hoverCell = i;
    startMeasure(i);
}
function panelGridLeave() {
    if (!pano || pano.phase !== 'find') return;
    pano.hoverCell = null; stopMeasure(); stopMeterTone(); mmLights(null);
    const v = $('mm-read'); v.textContent = '000'; v.className = 'mm-read';
}
function panelCleanup() {
    stopMeasure(); stopMeterTone(); mmLights(null);
    const pb = $('mm-probe'); if (pb) pb.style.display = 'none';
}
function panelClickCell(i) {
    if (!pano || pano.phase !== 'find') return;
    const cell = document.querySelector(`#panel-grid .pano[data-i="${i}"]`);
    if (i === pano.broken) { // achou o defeituoso -> reparo
        sndClick(); panelCleanup();
        pano.phase = 'removing';
        $('panel-grid').classList.add('hidden');
        $('panel-service').classList.remove('hidden');
        $('service-step').textContent = 'Remova os 4 parafusos';
        $('panel-progress').textContent = 'Reparando disjuntor';
        return;
    }
    // B: errar NAO falha na hora — da tentativas
    sndError();
    if (cell) { cell.classList.add('wrong'); setTimeout(() => cell.classList.remove('wrong'), 400); }
    pano.wrong++;
    const left = (pano.maxWrong + 1) - pano.wrong;
    if (left <= 0) return finish(false); // estourou as tentativas -> choque
    $('panel-progress').textContent = `Tensao normal aqui. Continue medindo (${left} tentativa${left > 1 ? 's' : ''}).`;
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
function mkCable(color) {
    const p = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    p.setAttribute('class', 'cable tmp');
    p.setAttribute('stroke', color);
    $('wiring-svg').appendChild(p);
    return p;
}
// curva do cabo: bezier com controle horizontal (cruzamento suave estilo painel real)
function cableD(x1, y1, x2, y2) {
    const dx = Math.abs(x2 - x1) * 0.5 + 12;
    return `M ${x1} ${y1} C ${x1 + dx} ${y1}, ${x2 - dx} ${y2}, ${x2} ${y2}`;
}
function wiringStart(e, plug) {
    if (!wiring || plug.classList.contains('done')) return;
    const c = centerOf(plug);
    dragWire = { plug, x1: c.x, y1: c.y, path: mkCable(PALETTE[plug.dataset.color].c) };
    dragWire.path.setAttribute('d', cableD(c.x, c.y, c.x, c.y));
}
function wiringMove(e) {
    if (!dragWire) return;
    const s = svgRect();
    dragWire.path.setAttribute('d', cableD(dragWire.x1, dragWire.y1, e.clientX - s.left, e.clientY - s.top));
}
function wiringUp(e) {
    if (!dragWire) return;
    const target = document.elementFromPoint(e.clientX, e.clientY);
    const plug = dragWire.plug;
    if (target && target.classList.contains('socket') && !target.classList.contains('done')
        && target.dataset.color === plug.dataset.color) {
        const c = centerOf(target);
        dragWire.path.setAttribute('d', cableD(dragWire.x1, dragWire.y1, c.x, c.y));
        dragWire.path.classList.remove('tmp');
        plug.classList.add('done'); target.classList.add('done');
        sndConnect(); wiring.connected++;
        $('wiring-progress').textContent = `${wiring.connected} / ${wiring.count}`;
        dragWire = null;
        if (wiring.connected >= wiring.count) finish(true);
        return;
    }
    // errou: remove o cabo temporario
    dragWire.path.remove(); dragWire = null;
}

/* ============================================================
   4) MARTELO / CONSTRUTOR — pressione a tecla certa p/ martelar
============================================================ */
let hammer = null;
const HAMMER_KEYS = ['Q', 'E', 'R', 'F'];

function openHammer(s) {
    active = 'hammer';
    hammer = { total: Math.max(1, s.nails || 3), done: 0, fails: 0, maxFails: s.maxFails || 4, key: null, timeout: null };
    $('hammer-progress').textContent = `0 / ${hammer.total}`;
    $('hammer-nail').style.transform = 'translateX(-50%) translateY(0px)';
    $('hammer').classList.remove('hidden');
    hammerNextKey();
    hammer.timeout = setTimeout(() => { if (active === 'hammer') finish(false); }, (s.time || 22) * 1000);
}
function hammerNextKey() {
    hammer.key = HAMMER_KEYS[Math.floor(Math.random() * HAMMER_KEYS.length)];
    const k = $('hammer-key'); k.textContent = hammer.key; k.className = 'hammer-key';
}
function hammerSwing() {
    const t = $('hammer-tool'); t.classList.add('swing');
    setTimeout(() => t.classList.remove('swing'), 90);
}
function hammerKey(e) {
    if (active !== 'hammer' || !hammer || !hammer.key) return;
    const key = (e.key || '').toUpperCase();
    if (!HAMMER_KEYS.includes(key)) return; // ESC e tratado no handler global
    const cap = $('hammer-key');
    if (key === hammer.key) {
        hammerSwing(); beep(150, 0.07, 'square', 0.14);
        cap.classList.add('hit');
        hammer.done++;
        $('hammer-progress').textContent = `${hammer.done} / ${hammer.total}`;
        $('hammer-nail').style.transform = `translateX(-50%) translateY(${Math.round(hammer.done / hammer.total * 44)}px)`;
        // faiscas no impacto (reusa o spawner da solda)
        const nr = $('hammer-nail').getBoundingClientRect();
        weldSparks(nr.left + nr.width / 2, nr.top);
        if (hammer.done >= hammer.total) { hammer.key = null; sndConnect(); return setTimeout(() => finish(true), 200); }
        setTimeout(hammerNextKey, 150);
    } else {
        cap.classList.add('miss'); sndError(); hammer.fails++;
        setTimeout(() => cap.classList.remove('miss'), 220);
        if (hammer.fails >= hammer.maxFails) finish(false);
    }
}
function hammerCleanup() {
    if (hammer && hammer.timeout) clearTimeout(hammer.timeout);
    hammer = null;
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
        case 'START_HAMMER': openHammer(d.settings || {}); break;
        case 'CLOSE':        finish(false); break;
        case 'HUD_SHOW':     hudShow(d.tasks, d.players); break;
        case 'HUD_TASKS':    hudTasks(d.tasks); break;
        case 'HUD_PLAYERS':  hudPlayers(d.players); break;
        case 'HUD_HIDE':     $('hud').classList.add('hidden'); break;
        case 'REWARD':       showReward(d.data); break;
        case 'SFX':          if (d.play) sfxStart(d.sfx); else sfxStop(); break;
        case 'NOTIFY':       cityNotify(d.ntype, d.message); break;
        case 'OPEN_MENU':    openMenu(d.data); break;
        case 'MENU_UPDATE':  if (menuState) renderMenu(d.data); break;
        case 'CLOSE_MENU':   closeMenu(); break;
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
        row.innerHTML = `<div class="hud-av" style="background:${avatarColor(p.name)}">${avatarInitials(p.name)}</div>` +
            `<span class="lbl">${p.name || '?'}</span><span class="val">${p.score || 0}</span>`;
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

/* ============================================================
   NOTIFICACOES in-NUI (fila + auto-some)
============================================================ */
function cityNotify(ntype, message) {
    const c = $('notify'); if (!c) return;
    const t = (ntype === 'error' || ntype === 'success') ? ntype : 'info';
    const box = document.createElement('div');
    box.className = 'notify-box ' + t;
    const icon = t === 'error' ? '!' : (t === 'success' ? '✓' : 'i');
    const title = t === 'error' ? 'Erro' : (t === 'success' ? 'Sucesso' : 'Info');
    box.innerHTML = `<div class="notify-ico">${icon}</div><div class="notify-txt">` +
        `<span class="notify-title">${title}</span><span class="notify-msg">${message || ''}</span></div>`;
    c.appendChild(box);
    setTimeout(() => { box.classList.add('out'); setTimeout(() => box.remove(), 320); }, 3600);
}

/* ============================================================
   MENU principal (Secretaria de Obras)
============================================================ */
let menuState = null;
function openMenu(data) { renderMenu(data); $('menu').classList.remove('hidden'); }
function closeMenu() {
    menuState = null;
    $('menu').classList.add('hidden');
    $('menu-split-box').classList.add('hidden');
    $('menu-split-box').innerHTML = '';
}
// avatar gerado a partir das iniciais (sem precisar de imagem do servidor)
function avatarInitials(name) {
    const parts = (name || '?').trim().split(/\s+/);
    return ((parts[0] || '?')[0] + (parts[1] ? parts[1][0] : '')).toUpperCase();
}
function avatarColor(name) {
    let h = 0; for (let i = 0; i < (name || '').length; i++) h = (h * 31 + name.charCodeAt(i)) % 360;
    return `hsl(${h}, 45%, 40%)`;
}
const brl = (n) => Number(n || 0).toLocaleString('pt-BR');

function renderMenu(data) {
    menuState = data;
    // ---- perfil ----
    $('menu-sub').textContent = data.disciplineLabel || 'Departamento de Obras';
    $('menu-name').textContent = data.name || '—';
    $('menu-money').textContent = '$' + brl(data.money);
    $('menu-lvl').textContent = 'Nv ' + (data.level || 1);
    const av = $('menu-avatar'); av.textContent = avatarInitials(data.name); av.style.background = avatarColor(data.name);
    $('menu-xp-bar').style.width = Math.min(100, ((data.xp || 0) / (data.nextXp || 1)) * 100) + '%';
    $('menu-xp-text').textContent = brl(data.xp) + ' / ' + brl(data.nextXp) + ' XP';

    // ---- frentes ----
    const dc = $('menu-disciplines'); dc.innerHTML = '';
    (data.disciplines || []).forEach(di => {
        const el = document.createElement('div');
        el.className = 'disc-chip' + (di.id === data.currentDiscipline ? ' active' : '') + (di.locked ? ' locked' : '');
        el.textContent = di.label;
        if (!di.locked && di.id !== data.currentDiscipline) el.onclick = () => post('menuDiscipline', { id: di.id });
        dc.appendChild(el);
    });

    // ---- contratos (cards) ----
    const regions = data.regions || [];
    $('menu-region-count').textContent = regions.length + ' ' + (regions.length === 1 ? 'região' : 'regiões');
    const rc = $('menu-regions'); rc.innerHTML = '';
    regions.forEach(r => {
        const el = document.createElement('div');
        el.className = 'region-card' + (r.selected ? ' selected' : '') + (r.locked ? ' locked' : '');
        const tasks = (r.tasks || []).map(t => `<div class="rc-task"><span class="rc-dot"></span>${t.count} ${t.label}</div>`).join('');
        const badge = r.minLevel > 0
            ? `<span class="rc-badge ${r.locked ? 'bad' : 'ok'}">Nv ${r.minLevel}</span>`
            : `<span class="rc-badge ok">Sem nível</span>`;
        el.innerHTML =
            `<div class="rc-head"><span class="rc-title">${r.title}</span>${badge}</div>` +
            `<div class="rc-chips"><span class="rc-money">$${brl(r.money)}</span>` +
            `<span class="rc-xp">${brl(r.xp)} XP</span>` +
            `<span class="rc-players">1-${r.maxPlayers || 4} 👷</span></div>` +
            `<div class="rc-tasks">${tasks}</div>`;
        if (!r.locked) el.onclick = () => post('menuMission', { key: r.key });
        rc.appendChild(el);
    });

    // ---- equipe ----
    const players = data.players || [];
    $('menu-team-count').textContent = '(' + players.length + '/' + (data.maxPlayers || 4) + ')';
    const pl = $('menu-players'); pl.innerHTML = '';
    players.forEach(p => {
        const el = document.createElement('div'); el.className = 'player-row';
        el.innerHTML =
            `<div class="pr-av" style="background:${avatarColor(p.name)}">${avatarInitials(p.name)}</div>` +
            `<div class="pr-info"><span class="pr-name">${p.name}${p.owner ? ' <span class="pr-owner">(dono)</span>' : ''}</span>` +
            `<span class="pr-lvl">Nv ${p.level || 1}</span></div>` +
            ((data.isOwner && !p.owner) ? `<span class="pr-kick" data-cid="${p.cid}">✕</span>` : '');
        pl.appendChild(el);
    });
    pl.querySelectorAll('.pr-kick').forEach(k => k.onclick = () => post('menuKick', { cid: k.dataset.cid }));

    // ---- detalhes do contrato selecionado ----
    const det = $('menu-details');
    const sel = regions.find(r => r.selected);
    if (sel) {
        const tasks = (sel.tasks || []).map(t => `<div class="det-row"><span class="det-dot"></span>${t.count} ${t.label}</div>`).join('');
        const items = (data.rewardItems || []).map(it => `<div class="det-row"><span class="det-dot gold"></span>${it.item} <span class="det-mut">(${it.chance}%)</span></div>`).join('');
        det.innerHTML =
            `<div class="det-sec"><div class="det-label">TAREFAS</div>${tasks || '<div class="det-empty">—</div>'}</div>` +
            (items ? `<div class="det-sec"><div class="det-label">ITENS DE RECOMPENSA</div>${items}</div>` : '') +
            (data.requiredItem ? `<div class="det-sec"><div class="det-label">EXIGE</div><div class="det-row"><span class="det-dot red"></span>${data.requiredItem}</div></div>` : '') +
            `<div class="det-rewards"><div class="det-rw money"><span>RECOMPENSA</span>$ ${brl(sel.money)}</div><div class="det-rw xp"><span>EXP</span>${brl(sel.xp)} XP</div></div>`;
    } else {
        det.innerHTML = '<div class="det-empty">Selecione um contrato para ver os detalhes.</div>';
    }

    // ---- acoes ----
    $('menu-split').style.display = (data.bossSplit && data.isOwner && players.length > 1) ? 'inline-block' : 'none';
    $('menu-invite').style.display = data.isOwner ? 'inline-block' : 'none';
    $('menu-invite-id').style.display = data.isOwner ? 'inline-block' : 'none';
    const start = $('menu-start');
    start.disabled = !data.selectedRegion;
    start.textContent = data.selectedRegion ? 'INICIAR TRABALHO' : 'SELECIONE UM CONTRATO';
}
function toggleSplitBox() {
    const box = $('menu-split-box');
    if (!box.classList.contains('hidden')) { box.classList.add('hidden'); box.innerHTML = ''; return; }
    const players = (menuState && menuState.players) || [];
    if (players.length < 2) return;
    const def = Math.floor(100 / players.length);
    box.innerHTML = '';
    players.forEach(p => {
        const row = document.createElement('div'); row.className = 'split-row';
        row.innerHTML = `<span>${p.name}</span><input type="number" min="0" max="100" value="${def}" data-cid="${p.cid}"/>`;
        box.appendChild(row);
    });
    const btn = document.createElement('button'); btn.className = 'menu-btn ghost'; btn.textContent = 'Salvar divisão';
    btn.onclick = () => {
        const split = {};
        box.querySelectorAll('input').forEach(i => { split[i.dataset.cid] = parseInt(i.value) || 0; });
        post('menuSplit', { split: split });
        box.classList.add('hidden');
    };
    box.appendChild(btn);
    box.classList.remove('hidden');
}
$('menu-close').onclick = () => { closeMenu(); post('menuClose'); };
$('menu-start').onclick = () => { if (menuState && menuState.selectedRegion) post('menuStart'); };
$('menu-invite').onclick = () => {
    const id = parseInt($('menu-invite-id').value);
    if (id) { post('menuInvite', { id: id }); $('menu-invite-id').value = ''; }
};
$('menu-split').onclick = () => toggleSplitBox();
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && menuState) { closeMenu(); post('menuClose'); }
});

// delegacao de eventos do painel
$('panel-grid').addEventListener('mousemove', (e) => {
    const cell = e.target.closest('.pano'); if (cell) panelHover(parseInt(cell.dataset.i));
});
$('panel-grid').addEventListener('click', (e) => {
    const cell = e.target.closest('.pano'); if (cell) panelClickCell(parseInt(cell.dataset.i));
});
$('panel-grid').addEventListener('mouseleave', panelGridLeave);
document.querySelectorAll('#panel-service .screw').forEach(sc => {
    sc.addEventListener('click', () => panelScrew(sc));
});
$('service-cover').addEventListener('click', panelCover);

// arrastar fios + solda (mouse global)
document.addEventListener('mousemove', (e) => {
    if (active === 'wiring') return wiringMove(e);
    if (active === 'weld') return weldMove(e);
    if (active === 'panel') return moveProbe(e);
});
document.addEventListener('mouseup', (e) => {
    if (active === 'wiring') return wiringUp(e);
    if (active === 'weld') return weldUp(e);
});
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && active) finish(false); });
document.addEventListener('keydown', (e) => { if (active === 'hammer') hammerKey(e); });
