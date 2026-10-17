import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM, VirtualConsole } from 'jsdom';

// Execute the shipped script, not a reimplementation of its state machine.
const html = readFileSync(new URL('../../Resources/panel.html', import.meta.url), 'utf8');
const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)];
assert.equal(scripts.length, 1, 'the panel has one inline application script');
const clone = value => JSON.parse(JSON.stringify(value));
const secret = 'ui-test-secret-never-render-me';
const fixture = {
  schema_version: 1, active_profile: 'p1', first_run_shown: false,
  future_extension: { preserved: true },
  globals: {
    engine: { mode: 'manual', manual_path: '/fixture/kit-1.3.0', brew: false },
    host: '127.0.0.1', port: 8123, api_key: secret,
    allowed_hosts: ['engine.local'], allowed_origins: [], web_ui: true,
    model_folders: [
      { id: 'lmstudio', path: '/fixture/models', source: 'auto' },
      { id: 'u-1', path: '/fixture/missing', source: 'manual' }
    ]
  },
  profiles: [
    { id: 'p1', name: 'Default', model: { source: 'lmstudio', id: 'org/model', dir: null },
      options: { ane: true, persistent_cache: true, max_cache_disk: '100g' }, meta: { last_used_at: null } },
    { id: 'p2', name: 'Untouched', options: { ane: false }, model: { source: 'none' }, meta: {} }
  ]
};

// 1.3.0-contract option groups (memory/cache/compute/api + the model-axis extras).
const DEFAULT_DEFS = [
  { key: 'kv_format', flag: '--kv-format', kind: 'value', group: 'memory', default: 'int8', choices: ['int8', 'bf16'], requires: [] },
  { key: 'decode_share', flag: '--decode-share', kind: 'value', group: 'memory', default: null, requires: [] },
  { key: 'persistent_cache', flag: '--persistent-cache', kind: 'bool', group: 'cache', default: true, requires: [] },
  { key: 'max_cache_disk', flag: '--max-cache-disk', kind: 'value', group: 'cache', default: '100g', requires: [] },
  { key: 'cache_dir', flag: '--cache-dir', kind: 'value', group: 'cache', default: null, requires: ['persistent_cache'] },
  { key: 'ane', flag: '--ane', kind: 'bool', group: 'compute', default: true, requires: [] },
  { key: 'allow_idle_sleep', flag: '--allow-idle-sleep', kind: 'bool', group: 'compute', default: false, requires: [] },
  { key: 'served_model_name', flag: '--served-model-name', kind: 'value', group: 'api', default: null, requires: [] },
  { key: 'max_request_size', flag: '--max-request-size', kind: 'value', group: 'api', default: '256m', requires: [] },
  { key: 'draft_model', flag: '--draft-model', kind: 'value', group: 'model-axis', default: null, requires: [] },
  { key: 'revision', flag: '--revision', kind: 'value', group: 'model-axis', default: null, requires: [] }
];

// This bridge fixture models D13; Swift tests + live smoke prove the real producer.
const signature = doc => {
  const p = doc.profiles.find(p => p.id === doc.active_profile) || doc.profiles[0];
  return JSON.stringify([doc.globals.engine, doc.globals.host, doc.globals.port, doc.globals.api_key,
    doc.globals.allowed_hosts, doc.globals.allowed_origins, doc.globals.web_ui, p?.id, p?.model, p?.options]);
};
const results = [];
function check(name, body) {
  try { body(); results.push({ assertion: name, pass: true }); }
  catch (error) { results.push({ assertion: name, pass: false, error: error.message }); }
  console.log(JSON.stringify(results.at(-1)));
}
function panel({ firstRun = false, optionDefs = null } = {}) {
  let doc = clone(fixture), baseline = signature(doc), rejectSave = false;
  const commands = [], replies = [], timers = new Map(), errors = [];
  let timerID = 0;
  const virtualConsole = new VirtualConsole();
  virtualConsole.on('jsdomError', error => errors.push(error.message));
  const dom = new JSDOM(html.replace(scripts[0][0], ''), {
    url: 'https://splashui.test/', runScripts: 'outside-only', virtualConsole
  });
  const w = dom.window, $ = id => w.document.getElementById(id);
  w.HTMLCanvasElement.prototype.getContext = () => ({
    clearRect() {}, beginPath() {}, moveTo() {}, lineTo() {}, stroke() {}
  });
  w.HTMLElement.prototype.scrollIntoView = function () { this.dataset.scrolled = 'true'; };
  w.setTimeout = callback => { timers.set(++timerID, callback); return timerID; };
  w.clearTimeout = id => timers.delete(id);
  const engineTick = doc => ({ ...doc.globals.engine, path: doc.globals.engine.manual_path,
    version: '1.3.0', valid: true, tried: [doc.globals.engine.manual_path],
    arch: 'ARM64', os: 'MACOS 26', verdict: 'valid', verdict_reason: null });
  const tick = (overrides = {}, extra = {}) => w.update({
    state: 'idle', ready: true, server: { pid: 17573, launched_by_app: true },
    cfg: {
      engine: engineTick(doc),
      folders: doc.globals.model_folders.map(f => ({ ...f, present: f.id === 'lmstudio', scanning: false,
        models: f.id === 'lmstudio' ? [
          { id: 'org/model', source: f.id, dir: '/fixture/models/org/model', kind: 'package', size_bytes: 1900000000, eligibility: 'runnable', drafter: 'PACKAGE — baked in' },
          { id: 'org/assembly', source: f.id, dir: '/fixture/models/org/assembly', kind: 'assembly', size_bytes: 1800000000, eligibility: 'unrunnable', eligibility_reason: 'missing draft/config.json', drafter: 'MISSING — draft/config.json required' }
        ] : [] })),
      host: doc.globals.host, allowed_hosts: doc.globals.allowed_hosts, allowed_origins: doc.globals.allowed_origins, web_ui: doc.globals.web_ui,
      api_key_masked: 'ui••••••me', first_run: firstRun && !doc.first_run_shown,
      profiles: doc.profiles.map(p => ({ ...p,
        model: { ...p.model, size_bytes: p.model.id === 'org/model' ? 1900000000 : null },
        eligibility: p.model.source === 'none' ? 'unrunnable' : 'runnable', drafter: 'PACKAGE — baked in',
        preview: p.model.source === 'none' ? { args: [], error: 'no model selected — pick one in the MODEL pill', restart: false }
          : { args: ['-u', '-m', 'server.server', p.model.dir || '/fixture/models/org/model', '--model', p.model.id, '--host', doc.globals.host, '--port', String(doc.globals.port)], error: null, restart: false } })),
      active_profile: doc.active_profile,
      in_flight: 3,
      option_defs: optionDefs ?? DEFAULT_DEFS,
      restart_required: signature(doc) !== baseline, result: null, ...overrides
    }, ...extra
  });
  w.webkit = { messageHandlers: {
    size: { postMessage() {} },
    cmd: { postMessage(message) {
      const m = clone(message); commands.push(m);
      replies.push(() => {
        if (m.cmd === 'config.get') w.__cfgGet(clone(doc));
        if (m.cmd === 'config.reveal_key') w.__cfgRevealKey({ key: doc.globals.api_key });
        if (m.cmd === 'config.validate') {
          const invalid = m.doc.profiles.find(p => p.options.kv_format && !['int8', 'bf16'].includes(p.options.kv_format));
          const names = m.doc.profiles.map(p => p.name);
          const duplicate = new Set(names).size !== names.length;
          w.__cfgValidate({
            ok: !invalid && !duplicate,
            errors: [...(invalid ? [`profile ${invalid.id} option kv_format: invalid syntax`] : []),
              ...(duplicate ? ['duplicate profile name(s)'] : [])],
            warnings: [], validation_id: m.validation_id,
            option_defs: optionDefs ?? DEFAULT_DEFS,
            profiles: m.doc.profiles.map(p => ({ id: p.id, eligibility: p.model.source === 'none' ? 'unrunnable' : 'runnable', drafter: 'PACKAGE — baked in' }))
          });
        }
        if (m.cmd === 'config.save' || m.cmd === 'config.activate') {
          const names = m.doc.profiles.map(p => p.name);
          const duplicate = new Set(names).size !== names.length;
          const result = { ok: !rejectSave && !duplicate, errors: rejectSave ? ['rejected fixture'] : duplicate ? ['duplicate profile name(s)'] : [], warnings: [] };
          if (result.ok) { doc = clone(m.doc); if (m.cmd === 'config.activate') { doc.active_profile = m.profileId; doc.profiles.find(p => p.id === m.profileId).meta.last_used_at = new Date().toISOString(); } }
          w.__cfgSave(result); tick({ result });
        }
        if (m.cmd === 'config.firstRunDone') doc.first_run_shown = true;
      });
    } }
  } };
  w.eval(scripts[0][1] + '\nwindow.__test = { draft: () => CF.draft, dirty: cfDirty, doc: cfBuildDoc, S: () => S, repeatTick: () => window.update({ ...S }) };');
  function drain() { while (replies.length) replies.shift()(); }
  function flushTimers() {
    const pending = [...timers.values()]; timers.clear();
    for (const callback of pending) callback();
    drain();
  }
  function change(id, value) { $(id).value = String(value); $(id).dispatchEvent(new w.Event('change')); }
  function save() { flushTimers(); }   // S7: no save buttons — a passing validation commits the dirty draft
  drain(); tick();
  return { w, $, tick, commands, drain, flushTimers, change, save, errors,
    doc: () => clone(doc), reject: value => { rejectSave = value; },
    restarted: () => { baseline = signature(doc); tick(); }, close: () => dom.window.close() };
}

// ---- S7: the shared surfaces (status view untouched, settings + footer rebuilt) ----
const p = panel();
try {
  const { w, $, tick, commands, drain, change, save } = p;
  check('default screen is telemetry-only status', () => {
    assert.ok(!$('statusView').hidden && $('settingsView').hidden);
    assert.equal($('statusView').querySelector('section.settings-global, section.settings-profiles'), null);
    assert.deepEqual([...$('statusView').querySelectorAll('section')].map(s => s.dataset.channel), ['01', '02', '03', '04', '05']);
  });
  check('telemetry performance, engine and requests remain intact', () => {
    assert.equal($('toks').closest('section').dataset.channel, '01');
    assert.equal($('ane').closest('section').dataset.channel, '02');
    assert.equal($('recentTable').querySelectorAll('th').length, 6);
  });
  check('settings rail: 06 lilac + 07 green sections with broken-line dividers', () => {
    assert.deepEqual([...$('settingsView').querySelectorAll('section')].map(s => s.dataset.channel), ['06', '07']);
    assert.match(html, /\.settings-global\s*{[^}]*--accent:\s*var\(--lavender\)/);
    assert.match(html, /\.settings-profiles\s*{[^}]*--accent:\s*var\(--green\)/);
    assert.match(html, /section::after\s*{[^}]*linear-gradient\(to right, var\(--accent\)/);
  });
  check('settings header: title, STATUS cap, active profile bar, engine state pill', () => {
    assert.equal($('s7Title').textContent, 'Splash settings');
    assert.ok($('btnStatus').closest('#settingsHeader'));
    assert.equal($('s7ProfileName').textContent, 'Default');
    assert.ok($('s7ProfileModel').textContent.includes('org/model'));
    assert.equal($('s7EngState').textContent, 'IDLE');
    assert.ok($('s7EngState').classList.contains('up'));
  });
  tick({}, { state: 'down', server: { pid: null, launched_by_app: false } });
  check('settings engine-state pill: DOWN when the server is gone', () => {
    assert.equal($('s7EngState').textContent, 'DOWN');
    assert.ok(!$('s7EngState').classList.contains('up'));
  });
  tick();
  check('hamburger switches views without bridging or losing draft', () => {
    const count = commands.length, draft = w.__test.draft();
    $('statusView').scrollTop = 90;
    $('btnSettings').click();
    assert.ok($('statusView').hidden && !$('settingsView').hidden);
    assert.equal($('settingsView').scrollTop, 0);
    assert.equal(commands.length, count);
    assert.equal(w.__test.draft(), draft);
  });
  check('S7 controls live on the settings screen', () => {
    for (const id of ['capAuto', 'capManual', 'manualPath', 'btnBrowseEngine', 'engPath', 'engTried', 'vCfg', 'engArch', 'engValid',
      'cfgMsg', 'folderList', 'folderPath', 'btnBrowseFolder', 'btnAddFolder',
      'cfgHost', 'cfgPort', 'cfgKey', 'btnKeyEye', 'cfgAllowedHost', 'cfgAllowedOrigin', 'webUiOn', 'webUiOff',
      'profileList', 'btnProfileAdd', 'ptabGeneral', 'ptabMemory', 'ptabCache', 'ptabCompute', 'ptabApi',
      'profileName', 'btnProfileActivate', 'btnProfileClone', 'btnProfileRemove', 'modelPill', 'modelPillName',
      'profileDrafter', 'profileModelAxis', 'profileLaunchMeta', 'profilePreviewBox', 'profileRestartPrompt'])
      assert.ok($('settingsView').contains($(id)), id);
  });
  check('chooser and first-run modals live at the top level, outside both views', () => {
    for (const id of ['cfgModal', 'modelModal', 'modelSearch', 'modelSrcCaps', 'modelRows', 'modelCancel', 'modelOk', 'modelClose']) {
      const el = $(id);
      assert.ok(w.document.body.contains(el) && !el.closest('#statusView, #settingsView'), id);
    }
  });
  check('footer controls live on the shared footer', () => {
    for (const id of ['footRow1', 'footRow2', 'restartPill', 'cfgPill', 'verPill', 'btnGroup', 'btnStart', 'btnRestart', 'btnStop', 'pidPill', 'pidLabel', 'pidNum', 'envPill'])
      assert.ok(w.document.getElementById('footer').contains($(id)), id);
  });
  check('save buttons are gone — every change auto-saves', () => {
    assert.equal($('btnCfgSave'), null);
    assert.equal($('btnProfilesSave'), null);
    assert.ok([...$('settingsView').querySelectorAll('button')].every(b => !/\bsave\b/i.test(b.textContent)));
  });
  check('network panel: host, port, masked key, allowed lists, web ui populated', () => {
    assert.equal($('cfgHost').value, '127.0.0.1');
    assert.equal($('cfgPort').value, '8123');
    assert.ok($('cfgKey').readOnly && $('cfgKey').value === '· · · · · · · ·');
    assert.equal($('cfgAllowedHost').value, 'engine.local');
    assert.equal($('cfgAllowedOrigin').value, '');
    assert.ok($('webUiOn').classList.contains('on') && !$('webUiOff').classList.contains('on'));
  });
  check('raw API key absent from DOM text and inputs before any reveal', () => {
    assert.ok(!w.document.documentElement.outerHTML.includes(secret));
    assert.ok([...w.document.querySelectorAll('input')].every(input => !input.value.includes(secret)));
  });
  check('initial draft is clean', () => assert.equal(w.__test.dirty(), false));
  check('engine panel: manual caps, path field, ladder, version, arch, VALID cap', () => {
    assert.ok($('capManual').classList.contains('on') && !$('capAuto').classList.contains('on'));
    assert.ok(!$('manualPath').disabled && $('manualPath').value === '/fixture/kit-1.3.0');
    assert.equal($('engPath').textContent, '/fixture/kit-1.3.0');
    assert.equal($('vCfg').textContent, '1.3.0');
    assert.equal($('engArch').textContent, 'ARM64 · MACOS 26');
    assert.match($('engValid').textContent, /^VALID/);
    assert.ok($('engValid').classList.contains('valid'));
    assert.equal($('engTried').textContent, 'ladder: /fixture/kit-1.3.0');
  });
  $('capAuto').click();
  check('Auto disables the manual path input', () => assert.ok($('manualPath').disabled && $('capAuto').classList.contains('on')));
  $('capManual').click();
  tick({ engine: { ...w.__test.S().cfg.engine, verdict: 'valid', version: '1.3.1',
    verdict_reason: 'built against v1.3.0; running v1.3.1' } });
  check('verdict cap: any version is supported — a non-built-against kit is VALID with the version as info', () => {
    assert.match($('engValid').textContent, /^VALID — built against v1\.3\.0; running v1\.3\.1$/);
    assert.ok($('engValid').classList.contains('valid'));
    assert.equal($('engValid').dataset.tip, 'built against v1.3.0; running v1.3.1');
  });
  tick({ engine: { ...w.__test.S().cfg.engine, verdict: 'fallback', version: '1.3.1' },
    mapping_used: '1.3.0', registry_report: { missing_in_kit: ['--foo'] } });
  check('verdict cap: fallback carries the registry report as its tip', () => {
    assert.match($('engValid').textContent, /FALLBACK MAPPING/);
    assert.ok($('engValid').classList.contains('fallback'));
    assert.match($('engValid').dataset.tip, /Running on the latest authored mapping v1\.3\.0/);
    assert.match($('engValid').dataset.tip, /kit lacks: --foo/);
  });
  tick();
  check('global column selection drives the detail panels', () => {
    assert.ok(!$('gpanelEngine').hidden && $('gpanelFolders').hidden && $('gpanelNetwork').hidden);
    $('gcolFolders').click();
    assert.ok($('gpanelFolders').hidden === false && $('gpanelEngine').hidden && $('gpanelNetwork').hidden);
    assert.ok($('gcolFolders').classList.contains('on') && !$('gcolEngine').classList.contains('on'));
    $('gcolNetwork').click();
    assert.ok(!$('gpanelNetwork').hidden && $('gpanelEngine').hidden && $('gpanelFolders').hidden);
    $('gcolEngine').click();
    assert.ok(!$('gpanelEngine').hidden);
  });
  check('folder rows: source tag, path, status, model count', () => {
    assert.equal(w.document.querySelectorAll('#folderList .frow').length, 2);
    assert.match($('folderList').textContent, /LM Studio/);
    assert.match($('folderList').textContent, /\/fixture\/models/);
    assert.match($('folderList').textContent, /PRESENT.*2 models/);
    assert.match($('folderList').textContent, /Manual/);
    assert.match($('folderList').textContent, /MISSING.*0 models/);
  });
  tick({ folders: [{ id: 'lmstudio', scanning: true, present: true, models: [] }] });
  check('scanning folder uses SCANNING state', () => assert.match($('folderList').textContent, /SCANNING/));
  tick();
  w.document.querySelector('#folderList [data-act="scan"]').click(); drain();
  check('scan bridges the selected folder ID', () => assert.deepEqual(commands.at(-1), { cmd: 'config.scan', id: 'lmstudio' }));
  $('folderPath').value = '/fixture/added';
  $('btnAddFolder').click();
  check('folder add creates a manual row', () => {
    const folders = w.__test.draft().folders;
    assert.equal(folders.length, 3);
    assert.deepEqual(JSON.parse(JSON.stringify(folders.at(-1))), { id: 'folder3', path: '/fixture/added', source: 'manual' });
    assert.equal($('folderPath').value, '');
  });
  w.document.querySelector('#folderList [data-act="del"][data-i="2"]').click(); tick();
  check('folder delete removes the draft row', () => assert.equal(w.__test.draft().folders.length, 2));
  change('cfgHost', '0.0.0.0');
  save();
  check('host edit auto-saves (no save button) and round-trips the doc', () => {
    const saved = commands.findLast(m => m.cmd === 'config.save').doc;
    assert.equal(saved.globals.host, '0.0.0.0');
    assert.equal(saved.globals.port, 8123);
    assert.deepEqual(saved.globals.allowed_hosts, ['engine.local']);
    assert.equal(saved.globals.api_key, secret);
    assert.equal(saved.active_profile, 'p1');
    assert.ok(!('restart_required' in saved) && saved.schema_version === 1);
  });
  check('changed running plan arms the RESTART NEEDED pill + restart button', () => {
    assert.ok(!$('restartPill').hidden);
    assert.equal($('btnRestart').textContent, 'Restart to apply');
    assert.match($('cfgMsg').textContent, /restart to apply/);
  });
  change('cfgHost', '127.0.0.1'); save(); p.restarted();
  check('restoring baseline clears the restart pill', () => {
    assert.ok($('restartPill').hidden);
    assert.equal($('btnRestart').textContent, 'Restart');
  });
  check('allowed-hosts and allowed-origins parse comma lists', () => {
    change('cfgAllowedHost', 'a.local, b.local');
    change('cfgAllowedOrigin', 'http://a.local, http://b.local');
    assert.deepEqual(JSON.parse(JSON.stringify(w.__test.draft().allowedHosts)), ['a.local', 'b.local']);
    assert.deepEqual(JSON.parse(JSON.stringify(w.__test.draft().allowedOrigins)), ['http://a.local', 'http://b.local']);
  });
  save();
  check('network lists auto-save into globals', () => {
    const saved = commands.findLast(m => m.cmd === 'config.save').doc;
    assert.deepEqual(saved.globals.allowed_hosts, ['a.local', 'b.local']);
    assert.deepEqual(saved.globals.allowed_origins, ['http://a.local', 'http://b.local']);
  });
  change('cfgAllowedHost', 'engine.local');
  change('cfgAllowedOrigin', ''); save(); p.restarted();
  $('webUiOff').click(); save();
  check('web UI OFF round-trips web_ui false', () => {
    assert.equal(w.__test.draft().webUI, false);
    assert.equal(commands.findLast(m => m.cmd === 'config.save').doc.globals.web_ui, false);
    assert.ok($('webUiOff').classList.contains('on') && !$('webUiOn').classList.contains('on'));
  });
  $('webUiOn').click(); save(); p.restarted();
  check('web UI ON restores the default', () => assert.equal(w.__test.draft().webUI, true));
  check('eye toggle reveals the raw key on explicit action', () => {
    $('btnKeyEye').click(); drain();
    assert.deepEqual(commands.at(-1), { cmd: 'config.reveal_key' });
    assert.equal($('cfgKey').value, secret);
    assert.equal($('btnKeyEye').getAttribute('aria-pressed'), 'true');
  });
  check('key re-masks on blur and on the next tick', () => {
    $('cfgKey').dispatchEvent(new w.Event('blur'));
    assert.equal($('cfgKey').value, '· · · · · · · ·');
    tick();
    assert.equal($('cfgKey').value, '· · · · · · · ·');
    assert.equal($('btnKeyEye').getAttribute('aria-pressed'), 'false');
  });
  change('cfgPort', 8199); p.reject(true); save();
  check('failed save retains the dirty draft and renders errors', () => {
    assert.ok(w.__test.dirty());
    assert.equal($('cfgPort').value, '8199');
    assert.ok($('cfgMsg').textContent.includes('rejected fixture'));
    assert.equal(p.doc().globals.port, 8123);
  });
  p.reject(false);
  const edited = clone(w.__test.draft());
  w.__cfgGet(clone(fixture));
  check('repeated config.get cannot clobber unsaved edits', () => assert.deepEqual(clone(w.__test.draft()), edited));
  $('btnBrowseEngine').click(); drain();
  check('engine browse uses the correct context and switches to Manual', () => {
    assert.deepEqual(commands.at(-1), { cmd: 'browse', context: 'engine' });
  });
  tick({ picked: { context: 'engine', path: '/fixture/picked-kit' } });
  check('engine picker synchronizes draft and input', () => assert.ok(w.__test.draft().manualPath === '/fixture/picked-kit' && $('manualPath').value === '/fixture/picked-kit'));
  change('cfgPort', 8123); save(); p.restarted();
  check('telemetry-only tick retains cfg state', () => {
    w.update({ state: 'idle', ready: true, server: { pid: 17573, launched_by_app: true } });
    assert.equal($('vCfg').textContent, '1.3.0');
  });
  check('ordinary session does not show the first-run modal', () => assert.notEqual($('cfgModal').style.display, 'flex'));
  check('footer: shared swoop, two rows, pills populated', () => {
    assert.ok($('restartPill').hidden);
    assert.equal($('verPill').textContent, 'v1.3.0');
    assert.equal($('pidNum').textContent, '17573');
    assert.equal($('envPill').textContent, 'APP-MANAGED');
    assert.equal($('footRow2').children.length, 3);
    const [group, center, env] = $('footRow2').children;
    assert.equal(group.id, 'btnGroup');
    assert.equal(center.querySelector('#pidPill') ? true : false, true);
    assert.equal(env.id, 'envPill');
    assert.deepEqual([...group.querySelectorAll('.btn')].map(b => b.id), ['btnStart', 'btnRestart', 'btnStop']);
  });
  check('CONFIG pill opens settings from the status view', () => {
    $('btnStatus').click();
    assert.ok(!$('statusView').hidden && $('settingsView').hidden);
    $('cfgPill').click();
    assert.ok($('settingsView').hidden === false && $('statusView').hidden);
    $('btnStatus').click();
    assert.ok(!$('statusView').hidden && $('settingsView').hidden);
  });
  check('no unhandled DOM errors', () => assert.deepEqual(p.errors, []));
} finally { p.close(); }

// ---- D10: first-run modal (unchanged behavior) ----
for (const button of ['modalDismiss', 'modalCta']) {
  const first = panel({ firstRun: true });
  try {
    check(`${button}: first-run modal appears`, () => assert.equal(first.$('cfgModal').style.display, 'flex'));
    first.$(button).click(); first.drain();
    check(`${button}: dismissal bridges persistence`, () => assert.ok(first.doc().first_run_shown && first.commands.at(-1).cmd === 'config.firstRunDone'));
    first.tick({ first_run: true });
    check(`${button}: stale first_run tick cannot reopen modal`, () => assert.equal(first.$('cfgModal').style.display, 'none'));
    if (button === 'modalCta') check('first-run CTA opens the settings screen', () => assert.ok(!first.$('settingsView').hidden && first.$('statusView').hidden));
  } finally { first.close(); }
}

// ---- S7: profiles (channel 07) ----
const profiles = panel();
try {
  const { w, $, tick, change, save } = profiles;
  const rows = () => [...w.document.querySelectorAll('#profileList .profrow')];
  check('profile list: rows, selection highlight, active dot', () => {
    assert.equal(rows().length, 2);
    assert.equal(rows()[0].getAttribute('data-profile-id'), 'p1');
    assert.ok(rows()[0].classList.contains('on'));
    assert.ok(rows()[0].querySelector('.profdot').classList.contains('on'));
    assert.ok(!rows()[1].querySelector('.profdot').classList.contains('on'));
  });
  rows()[1].click();
  check('selecting a profile switches the editor to it', () => {
    assert.equal($('profileName').value, 'Untouched');
    assert.equal($('profileIdLabel').textContent, 'p2');
    assert.ok(rows()[1].classList.contains('on') && !rows()[0].classList.contains('on'));
  });
  check('five tabs render; GENERAL is the landing tab', () => {
    for (const id of ['ptabGeneral', 'ptabMemory', 'ptabCache', 'ptabCompute', 'ptabApi']) assert.equal($(id).hidden, false, id);
    assert.ok($('ptabGeneral').classList.contains('on'));
    assert.ok(!$('ptabGeneralPanel').hidden && $('ptabComputePanel').hidden);
  });
  $('ptabCompute').click();
  check('tab click switches the visible tab panel', () => {
    assert.ok($('ptabCompute').classList.contains('on') && !$('ptabGeneral').classList.contains('on'));
    assert.ok(!$('ptabComputePanel').hidden && $('ptabGeneralPanel').hidden);
    assert.equal($('ptabComputePanel').querySelector('#option-ane') ? true : false, true);
  });
  check('ANE is per-profile: the selected profile owns its compute option', () => {
    const draft = w.__test.draft();
    assert.equal(draft.profiles[1].options.ane, false);   // p2 selected, p1 keeps its own value
    const on = w.document.querySelector('#ptabComputePanel [data-option-choice="ane"][data-value="true"]');
    on.click();
    assert.equal(w.__test.draft().profiles[1].options.ane, true);
    assert.equal(w.__test.draft().profiles[0].options.ane, true);
  });
  save();
  check('compute tab edit auto-saves into the selected profile', () => {
    const saved = profiles.commands.findLast(m => m.cmd === 'config.save');
    assert.equal(saved.doc.profiles[1].options.ane, true);
    assert.equal(saved.doc.profiles[0].options.ane, true);
  });
  rows()[0].click();
  $('ptabCache').click();
  check('requires-gating: an unmet prerequisite disables the dependent row', () => {
    // p1 has persistent_cache set — its cache_dir row is live.
    const p1row = w.document.querySelector('#ptabCachePanel [data-option-row="cache_dir"]');
    assert.ok(!p1row.classList.contains('unmet'));
    rows()[1].click();
    $('ptabCache').click();
    // p2: switch persistent_cache OFF via the UI — cache_dir must be gated off.
    w.document.querySelector('#ptabCachePanel [data-option-choice="persistent_cache"][data-value="false"]').click();
    assert.equal(w.__test.draft().profiles[1].options.persistent_cache, false);
    const p2row = w.document.querySelector('#ptabCachePanel [data-option-row="cache_dir"]');
    assert.ok(p2row.classList.contains('unmet'));
    assert.ok(p2row.querySelector('#option-cache_dir').disabled);
    save();   // auto-save rebaselines — the draft is clean again for the activation checks
    assert.ok(!w.__test.dirty());
  });
  rows()[0].click(); $('ptabGeneral').click();
  check('GENERAL: actions, model pill, drafter, metadata', () => {
    assert.equal($('profileName').value, 'Default');
    assert.equal($('btnProfileActivate').textContent, 'Active');
    assert.equal($('modelPillName').textContent, 'org/model');
    assert.match($('profileDrafter').textContent, /PACKAGE — baked in/);
    assert.match($('profileLaunchMeta').textContent, /Created/);
    assert.match($('profileLaunchMeta').textContent, /Used/);
  });
  check('LAUNCH PREVIEW box renders the tick argv with the restart marker hidden', () => {
    assert.equal($('profilePreviewBox').hidden, false);
    assert.match($('profilePreviewArgs').textContent, /server\.server.*org\/model/);
    assert.match($('profilePreviewArgs').textContent, /--host 127\.0\.0\.1/);
    assert.equal($('profilePreviewRestart').hidden, true);
  });
  tick({ profiles: profiles.w.__test.S().cfg.profiles.map(p => ({ ...p, preview: { args: p.preview.args, error: null, restart: true } })) });
  check('preview restart marker appears when the plan differs from the running session', () => {
    assert.equal($('profilePreviewRestart').hidden, false);
  });
  rows()[1].click();
  tick();   // the restart-marker tick above replaced the canonical previews
  check('unrunnable profile preview shows the actionable reason in the box', () => {
    assert.equal($('profilePreviewBox').hidden, false);
    assert.match($('profilePreviewArgs').textContent, /no model selected/);
    assert.ok($('profilePreviewArgs').classList.contains('err'));
  });
  rows()[0].click();
  tick({ in_flight: 7, restart_required: true });
  check('in-flight restart prompt shows the count and the confirm control', () => {
    assert.equal($('profileRestartPrompt').hidden, false);
    assert.match($('profileRestartText').textContent, /7 in-flight/);
    assert.ok($('profileRestartPrompt').contains($('btnProfileRestart')));
  });
  tick();
  check('activation commits the draft atomically (doc + active id in one write)', () => {
    rows()[1].click();
    $('btnProfileActivate').click(); profiles.drain();
    const m = profiles.commands.at(-1);
    assert.equal(m.cmd, 'config.activate');
    assert.equal(m.profileId, 'p2');
    assert.equal(m.doc.active_profile, 'p1');   // the doc as it stands; activation stamps the id
    assert.equal(w.__test.draft().activeProfile, 'p2');
    assert.equal($('btnProfileActivate').textContent, 'Active');
    assert.match($('cfgMsg').textContent, /Saved/);
  });
  check('a dirty unvalidated draft cannot activate', () => {
    change('profileName', 'Dirty name');
    assert.ok($('btnProfileActivate').disabled);
    profiles.save();
    assert.ok(!$('btnProfileActivate').disabled);
  });
  check('clone and delete rebuild the list and selection', () => {
    const before = w.__test.draft().profiles.length;
    rows()[0].click();
    $('btnProfileClone').click();
    assert.equal(w.__test.draft().profiles.length, before + 1);
    assert.match(w.__test.draft().profiles.at(-1).name, /Default copy/);
    $('btnProfileRemove').click();
    assert.equal(w.__test.draft().profiles.length, before);
    assert.equal(rows().length, before);
  });
  check('adding a profile names it sequentially with no model', () => {
    $('btnProfileAdd').click();
    const p3 = w.__test.draft().profiles.at(-1);
    assert.equal(p3.name, 'Profile 3');
    assert.equal(p3.model.source, 'none');
    assert.equal($('modelPillName').textContent, '— model unset —');
    assert.equal($('btnProfileActivate').textContent, 'Activate');
    $('btnProfileRemove').click();
  });
  check('stale option keys surface under the active tab, never on GENERAL', () => {
    $('ptabCompute').click();
    w.__test.draft().profiles[0].options.foo_bar = 'x';
    tick();
    assert.equal($('profileStaleSlot').hidden, false);
    assert.match($('profileStaleSlot').textContent, /STALE OPTIONS — 1 KEPT/);
    assert.ok($('profileStaleSlot').querySelector('#option-stale-foo_bar').disabled);
    $('ptabGeneral').click();
    tick();
    assert.equal($('profileStaleSlot').hidden, true);   // GENERAL never shows stale keys
    delete w.__test.draft().profiles[0].options.foo_bar;
    tick();
    assert.equal($('profileStaleSlot').hidden, true);
  });
  check('no unhandled DOM errors (profiles)', () => assert.deepEqual(profiles.errors, []));
} finally { profiles.close(); }

// ---- S7: version-gated tabs (a contract without the cache group) ----
const gated = panel({ optionDefs: DEFAULT_DEFS.filter(d => d.group !== 'cache') });
try {
  check('a tab whose group has no options for the resolved version is hidden, not disabled', () => {
    assert.equal(gated.$('ptabCache').hidden, true);
    for (const id of ['ptabGeneral', 'ptabMemory', 'ptabCompute', 'ptabApi']) assert.equal(gated.$(id).hidden, false, id);
  });
  gated.tick({ option_defs: DEFAULT_DEFS });
  check('tabs re-appear when a tick carries the fuller contract', () => {
    assert.equal(gated.$('ptabCache').hidden, false);
  });
} finally { gated.close(); }

// ---- S7: the model chooser ----
const chooser = panel();
try {
  const { w, $, tick, save } = chooser;
  $('modelPill').click();
  check('chooser opens over the settings with the downloaded models', () => {
    assert.equal($('modelModal').style.display, 'flex');
    assert.equal(w.document.querySelectorAll('#modelRows .model-row').length, 2);
    assert.match($('modelRows').textContent, /org\/model.*LM Studio.*1\.8 GiB/);
    assert.match($('modelRows').textContent, /org\/assembly.*LM Studio.*1\.7 GiB/);
  });
  check('source caps carry live counts', () => {
    assert.match($('modelSrcCaps').textContent, /All · 2/);
    assert.match($('modelSrcCaps').textContent, /LM Studio · 2/);
  });
  $('modelSearch').value = 'assembly';
  $('modelSearch').dispatchEvent(new w.Event('input'));
  check('search filters the downloaded models', () => {
    const rows = [...w.document.querySelectorAll('#modelRows .model-row')];
    assert.equal(rows.length, 1);
    assert.match(rows[0].textContent, /org\/assembly/);
  });
  $('modelSearch').value = 'org/model';
  $('modelSearch').dispatchEvent(new w.Event('input'));
  check('a HF id matching a downloaded model gets the MATCH tag', () => {
    assert.equal(w.document.querySelectorAll('#modelRows .model-row').length, 1);
    assert.ok(w.document.querySelector('#modelRows .match-tag'));
  });
  check('the note line explains the HF-id behavior', () => assert.match($('modelModal').textContent, /HF id matches a downloaded model/));
  $('modelSearch').value = '';
  $('modelSearch').dispatchEvent(new w.Event('input'));
  w.document.querySelector('#modelRows .model-row[data-mrow="1"]').click();
  check('OK confirms the selection into the draft, closes, and auto-saves', () => {
    $('modelOk').click();
    save();
    assert.equal($('modelModal').style.display, 'none');
    assert.deepEqual(JSON.parse(JSON.stringify(w.__test.draft().profiles[0].model)), { source: 'lmstudio', id: 'org/assembly', dir: '/fixture/models/org/assembly' });
    assert.equal(chooser.commands.findLast(m => m.cmd === 'config.save').doc.profiles[0].model.id, 'org/assembly');
    assert.equal($('modelPillName').textContent, 'org/assembly');
  });
  check('the chooser never loads the engine', () => {
    assert.ok(chooser.commands.every(m => !['start', 'restart', 'stop'].includes(m.cmd)));
  });
  $('modelPill').click();
  w.document.querySelector('#modelRows .model-row[data-mrow="0"]').click();
  check('CANCEL discards the selection', () => {
    const before = clone(w.__test.draft().profiles[0].model);
    $('modelCancel').click();
    assert.equal($('modelModal').style.display, 'none');
    assert.deepEqual(JSON.parse(JSON.stringify(w.__test.draft().profiles[0].model)), before);
  });
  $('modelPill').click();
  check('close button and Escape close without changes', () => {
    const before = clone(w.__test.draft().profiles[0].model);
    $('modelClose').click();
    assert.equal($('modelModal').style.display, 'none');
    assert.deepEqual(JSON.parse(JSON.stringify(w.__test.draft().profiles[0].model)), before);
    $('modelPill').click();
    w.document.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Escape' }));
    assert.equal($('modelModal').style.display, 'none');
    assert.deepEqual(JSON.parse(JSON.stringify(w.__test.draft().profiles[0].model)), before);
  });
  check('no unhandled DOM errors (chooser)', () => assert.deepEqual(chooser.errors, []));
} finally { chooser.close(); }

const native = readFileSync(new URL('../../Sources/main.swift', import.meta.url), 'utf8');
check('native menu exposes ordered status/settings/separator/quit actions', () => {
  assert.match(native, /sendAction\(on: \[\.leftMouseUp, \.rightMouseUp\]\)/);
  assert.match(native, /withTitle: "Open Status"[\s\S]*#selector\(openStatus\)[\s\S]*withTitle: "Settings…"[\s\S]*#selector\(openSettings\)[\s\S]*menu\.addItem\(\.separator\(\)\)[\s\S]*withTitle: "Quit SplashUI"[\s\S]*#selector\(quitApp\)/);
  assert.match(native, /func openSettings\(\)[\s\S]*?showPanel\(view: "settings"\)/);
  assert.match(native, /func openStatus\(\)[\s\S]*?showPanel\(\)/);
});

const failed = results.filter(result => !result.pass).length;
console.log(JSON.stringify({ suite: 'panel-jsdom', assertions: results.length, passed: results.length - failed, failed }));
process.exitCode = failed ? 1 : 0;
