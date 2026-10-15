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
    port: 8123, api_key: secret,
    model_folders: [
      { id: 'lmstudio', path: '/fixture/models', source: 'auto' },
      { id: 'missing', path: '/fixture/missing', source: 'manual' }
    ]
  },
  profiles: [
    { id: 'p1', name: 'Default', model: { source: 'lmstudio', id: 'org/model', dir: null },
      options: { ane: true, persistent_cache: true, max_cache_disk: '100g' }, meta: { last_used_at: null } },
    { id: 'p2', name: 'Untouched', options: { ane: false }, model: { source: 'none' }, meta: {} }
  ]
};

// This bridge fixture models D13; Swift tests + live smoke prove the real producer.
const signature = doc => JSON.stringify([doc.globals.engine, doc.globals.port,
  doc.globals.api_key, doc.profiles[0].model, doc.profiles[0].options]);
const results = [];
function check(name, body) {
  try { body(); results.push({ assertion: name, pass: true }); }
  catch (error) { results.push({ assertion: name, pass: false, error: error.message }); }
  console.log(JSON.stringify(results.at(-1)));
}
function panel({ firstRun = false } = {}) {
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
  const tick = (overrides = {}, extra = {}) => w.update({
    state: 'idle', ready: true, server: { pid: 17573, launched_by_app: false },
    cfg: {
      engine: { ...doc.globals.engine, path: doc.globals.engine.manual_path,
        version: '1.3.0', valid: true, tried: [doc.globals.engine.manual_path] },
      folders: doc.globals.model_folders.map(f => ({ ...f, present: f.id !== 'missing',
        scanning: false, models: f.id === 'lmstudio' ? [{ id: 'org/model' }] : [] })),
      api_key_masked: 'ui••••••me', first_run: firstRun && !doc.first_run_shown,
      restart_required: signature(doc) !== baseline, result: null, ...overrides
    }, ...extra
  });
  w.webkit = { messageHandlers: {
    size: { postMessage() {} },
    cmd: { postMessage(message) {
      const m = clone(message); commands.push(m);
      replies.push(() => {
        if (m.cmd === 'config.get') w.__cfgGet(clone(doc));
        if (m.cmd === 'config.validate') w.__cfgValidate({ ok: true, errors: [], warnings: [] });
        if (m.cmd === 'config.save') {
          const result = { ok: !rejectSave, errors: rejectSave ? ['rejected fixture'] : [], warnings: [] };
          if (result.ok) doc = clone(m.doc);
          w.__cfgSave(result); tick({ result });
        }
        if (m.cmd === 'config.firstRunDone') doc.first_run_shown = true;
      });
    } }
  } };
  w.eval(scripts[0][1] + '\nwindow.__test = { draft: () => CF.draft, dirty: cfDirty, doc: cfBuildDoc };');
  function drain() { while (replies.length) replies.shift()(); }
  function flushTimers() {
    const pending = [...timers.values()]; timers.clear();
    for (const callback of pending) callback();
    drain();
  }
  function change(id, value) { $(id).value = String(value); $(id).dispatchEvent(new w.Event('change')); }
  function save() { $('btnCfgSave').click(); drain(); }
  drain(); tick();
  return { w, $, tick, commands, drain, flushTimers, change, save, errors,
    doc: () => clone(doc), reject: value => { rejectSave = value; },
    restarted: () => { baseline = signature(doc); tick(); }, close: () => dom.window.close() };
}

const p = panel();
try {
  const { w, $, tick, commands, drain, change, save } = p;
  check('default screen is telemetry-only status', () => {
    assert.ok(!$('statusView').hidden && $('settingsView').hidden);
    assert.equal($('statusView').querySelector('.settings-panel'), null);
    assert.deepEqual([...$('statusView').querySelectorAll('section')].map(s => s.dataset.channel), ['01', '02', '03', '04', '05']);
  });
  check('telemetry performance, engine and requests remain intact', () => {
    assert.equal($('toks').closest('section').dataset.channel, '01');
    assert.equal($('ane').closest('section').dataset.channel, '02');
    assert.equal($('recentTable').querySelectorAll('th').length, 6);
  });
  check('hamburger switches views without bridging or losing draft', () => {
    const count = commands.length, draft = w.__test.draft();
    $('statusView').scrollTop = 90;
    $('btnSettings').click();
    assert.ok($('statusView').hidden && !$('settingsView').hidden);
    assert.equal($('settingsView').scrollTop, 0);
    assert.equal(commands.length, count);
    assert.equal(w.__test.draft(), draft);
    assert.equal($('btnSettings').querySelectorAll('span').length, 3);
  });
  check('all S5 controls live on the settings screen', () => {
    for (const id of ['capAuto', 'capManual', 'manualPath', 'engValid', 'folderList', 'cfgPort', 'cfgKey', 'aneOn', 'btnCfgSave', 'cfgMsg'])
      assert.ok($('settingsView').contains($(id)), id);
    assert.ok($('settingsView').contains($('profilesSlot')));
    assert.ok(!$('settingsView').contains($('footer')) && !$('statusView').contains($('footer')));
  });
  check('STATUS back cap resets scroll and returns to telemetry', () => {
    $('settingsView').scrollTop = 120;
    $('btnStatus').click();
    assert.ok(!$('statusView').hidden && $('settingsView').hidden);
    assert.equal($('statusView').scrollTop, 0);
    $('btnSettings').click();
    assert.equal($('settingsView').scrollTop, 0);
  });
  check('config.get uses the object-body bridge', () => assert.deepEqual(commands[0], { cmd: 'config.get' }));
  check('draft populated from the raw ConfigDoc', () => assert.equal(w.__test.draft().manualPath, '/fixture/kit-1.3.0'));
  check('manual input agrees with draft immediately after cfInit', () => assert.equal($('manualPath').value, w.__test.draft().manualPath));
  check('manual input enabled and radio selected', () => assert.ok(!$('manualPath').disabled && $('capManual').classList.contains('on')));
  check('port and ANE populated', () => assert.ok($('cfgPort').value === '8123' && $('aneOn').classList.contains('on')));
  check('initial draft is clean', () => assert.equal(w.__test.dirty(), false));
  check('raw API key absent from DOM text, attributes and input properties', () => {
    assert.ok(!w.document.documentElement.outerHTML.includes(secret));
    assert.ok([...w.document.querySelectorAll('input')].every(input => !input.value.includes(secret)));
  });
  check('API key is masked and readonly', () => assert.ok($('cfgKey').readOnly && $('cfgKey').value.length > 0 && $('cfgKey').value !== secret));
  check('adopted PID rendered without claiming app ownership', () => assert.ok($('pidNum').textContent === '17573' && $('envPill').textContent === 'EXTERNAL'));
  check('engine path/version/valid status populated', () => assert.ok($('engPath').textContent === '/fixture/kit-1.3.0' && $('vCfg').textContent === '1.3.0' && $('engValid').textContent === 'VALID'));
  check('folder rows match ConfigDoc', () => assert.equal(w.document.querySelectorAll('#folderList .frow').length, 2));
  check('folder status/count reflects tick', () => assert.match($('folderList').textContent, /lmstudioPRESENT1 model.*missingMISSING0 models/));
  tick({ folders: [{ id: 'lmstudio', scanning: true, present: true, models: [] }] });
  check('scanning folder uses SCANNING state', () => assert.match($('folderList').textContent, /SCANNING/));
  tick();
  w.document.querySelector('#folderList [data-act="scan"]').click(); drain();
  check('scan bridges the selected folder ID', () => assert.deepEqual(commands.at(-1), { cmd: 'config.scan', id: 'lmstudio' }));
  change('cfgPort', 8199);
  check('port edit makes draft dirty', () => assert.equal(w.__test.dirty(), true));
  change('cfgPort', 8123);
  check('returning to baseline clears dirty without saving', () => assert.equal(w.__test.dirty(), false));
  const savesBefore = commands.filter(m => m.cmd === 'config.save').length;
  save();
  check('clean save does not send a write', () => assert.equal(commands.filter(m => m.cmd === 'config.save').length, savesBefore));
  change('cfgPort', 8199); p.flushTimers();
  check('debounced validation sends the candidate ConfigDoc', () => assert.equal(commands.findLast(m => m.cmd === 'config.validate').doc.globals.port, 8199));
  save();
  const saved = commands.findLast(m => m.cmd === 'config.save').doc;
  check('save emits full ConfigDoc shape, not tick cfg shape', () => assert.ok(saved.schema_version === 1 && saved.profiles.length === 2 && saved.active_profile === 'p1' && !('restart_required' in saved)));
  check('save preserves raw key without rendering it', () => assert.equal(saved.globals.api_key, secret));
  check('save preserves extensions, metadata, options and other profiles', () => {
    assert.deepEqual(saved.future_extension, fixture.future_extension);
    assert.deepEqual(saved.profiles[1], fixture.profiles[1]);
    assert.deepEqual(saved.profiles[0], fixture.profiles[0]);
  });
  check('successful save rebases draft', () => assert.equal(w.__test.dirty(), false));
  check('changed running plan shows restart-required footer', () => assert.equal($('btnRestart').textContent, 'RESTART TO APPLY'));
  check('successful save reports restart to apply', () => assert.match($('cfgMsg').textContent, /restart to apply/));
  change('cfgPort', 8123); save();
  check('restoring adopted port clears restart-required', () => assert.equal($('btnRestart').textContent, 'Restart'));
  $('aneOff').click(); save();
  check('ANE off round-trips false and requires restart', () => assert.ok(p.doc().profiles[0].options.ane === false && $('btnRestart').textContent === 'RESTART TO APPLY'));
  $('aneOn').click(); save();
  check('ANE on restores baseline and clears restart-required', () => assert.ok(p.doc().profiles[0].options.ane === true && $('btnRestart').textContent === 'Restart'));
  $('aneOff').click(); save(); p.restarted();
  check('successful restart baseline clears the footer', () => assert.equal($('btnRestart').textContent, 'Restart'));
  change('cfgPort', 8199); p.reject(true); save();
  check('failed save retains dirty draft and renders errors', () => assert.ok(w.__test.dirty() && $('cfgMsg').textContent.includes('rejected fixture')));
  check('failed save does not mutate persisted config', () => assert.equal(p.doc().globals.port, 8123));
  p.reject(false);
  const edited = clone(w.__test.draft());
  w.__cfgGet(clone(fixture));
  check('repeated config.get cannot clobber unsaved edits', () => assert.deepEqual(clone(w.__test.draft()), edited));
  $('capAuto').click();
  check('Auto disables manual input and saves null manual_path', () => assert.ok($('manualPath').disabled && w.__test.doc().globals.engine.manual_path === null));
  $('capManual').click(); change('manualPath', '/fixture/another-kit');
  check('manual path change updates draft and candidate', () => assert.equal(w.__test.doc().globals.engine.manual_path, '/fixture/another-kit'));
  $('btnBrowseEngine').click(); drain();
  check('engine browse uses correct context', () => assert.deepEqual(commands.at(-1), { cmd: 'browse', context: 'engine' }));
  tick({ picked: { context: 'engine', path: '/fixture/picked-kit' } });
  check('engine picker synchronizes draft and input', () => assert.ok(w.__test.draft().manualPath === '/fixture/picked-kit' && $('manualPath').value === '/fixture/picked-kit'));
  $('btnBrowseFolder').click(); drain();
  check('folder browse uses correct context', () => assert.deepEqual(commands.at(-1), { cmd: 'browse', context: 'model_folder' }));
  tick({ picked: { context: 'model_folder', path: '/fixture/added-models' } });
  $('btnAddFolder').click(); tick();
  check('folder add creates manual row and clears path', () => assert.ok(w.__test.draft().folders.at(-1).source === 'manual' && $('folderPath').value === '' && $('folderList').textContent.includes('folder3')));
  w.document.querySelector('#folderList [data-act="del"][data-i="2"]').click(); tick();
  check('folder delete removes the selected draft row', () => assert.equal(w.__test.draft().folders.length, 2));
  w.update({ state: 'idle', ready: true, server: { pid: 17573, launched_by_app: false } });
  check('telemetry-only tick retains cfg state', () => assert.equal($('vCfg').textContent, '1.3.0'));
  check('ordinary session does not show first-run modal', () => assert.notEqual($('cfgModal').style.display, 'flex'));
  check('no unhandled DOM errors', () => assert.deepEqual(p.errors, []));
} finally { p.close(); }

for (const button of ['modalDismiss', 'modalCta']) {
  const first = panel({ firstRun: true });
  try {
    check(`${button}: first-run modal appears`, () => assert.equal(first.$('cfgModal').style.display, 'flex'));
    first.$(button).click(); first.drain();
    check(`${button}: dismissal bridges persistence`, () => assert.ok(first.doc().first_run_shown && first.commands.at(-1).cmd === 'config.firstRunDone'));
    first.tick({ first_run: true });
    check(`${button}: stale first_run tick cannot reopen modal`, () => assert.equal(first.$('cfgModal').style.display, 'none'));
    if (button === 'modalCta') check('first-run CTA opens settings screen', () => assert.ok(!first.$('settingsView').hidden && first.$('statusView').hidden));
  } finally { first.close(); }
}
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
