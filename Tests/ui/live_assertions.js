(async () => {
  const expected = /* EXPECTED */;
  const checks = [], steps = [], started = Date.now();
  // The panel becomes key on show. Ignore unrelated physical typing/clicks
  // while this automated transaction runs; programmatic events remain real.
  const ignoredInput = [];
  for (const type of ['keydown', 'beforeinput', 'mousedown', 'click']) {
    document.addEventListener(type, event => {
      if (!event.isTrusted) return;
      ignoredInput.push({ type, target: event.target.id || event.target.tagName,
        elapsed_ms: Date.now() - started });
      event.preventDefault(); event.stopImmediatePropagation();
    }, true);
  }
  const $ = id => document.getElementById(id);
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  function check(assertion, pass, actual) { checks.push({ assertion, pass: !!pass, actual }); }
  async function until(predicate, label, timeout = 12000) {
    const deadline = Date.now() + timeout;
    while (!predicate()) {
      if (Date.now() > deadline) throw new Error('Timed out: ' + label);
      await sleep(50);
    }
  }
  function snapshot(step) {
    const value = {
      step, elapsed_ms: Date.now() - started,
      port: $('cfgPort').value, draftPort: CF.draft.port,
      manualPath: $('manualPath').value, draftManualPath: CF.draft.manualPath,
      ane: CF.draft.ane, savedAne: S.cfg.profiles[0].options.ane,
      restart_required: S.cfg.restart_required,
      footer: $('btnRestart').textContent, message: $('cfgMsg').textContent,
      enginePID: S.server && S.server.pid, launchedByApp: S.server && S.server.launched_by_app
    };
    steps.push(value);
    return value;
  }
  try {
    await until(() => window.__cfgReady && CF.draft && S && S.cfg && S.server && S.server.pid === expected.enginePID, 'draft + adopted engine');
    await until(() => S.cfg.folders && S.cfg.folders.length === expected.folderCount &&
      S.cfg.folders.every(folder => !folder.scanning), 'folder scan');
    snapshot('baseline');
    check('form port populated', $('cfgPort').value === String(expected.port), $('cfgPort').value);
    check('draft manual path matches config', CF.draft.manualPath === expected.manualPath, CF.draft.manualPath);
    check('manual input matches draft', $('manualPath').value === CF.draft.manualPath, $('manualPath').value);
    check('engine mode populated', CF.draft.engineMode === expected.engineMode, CF.draft.engineMode);
    check('ANE populated', CF.draft.ane === expected.ane && $('aneOn').classList.contains('on') === expected.ane, CF.draft.ane);
    check('engine adopted not relaunched', S.server.pid === expected.enginePID && S.server.launched_by_app === false,
      { pid: S.server.pid, launched_by_app: S.server.launched_by_app });
    check('engine resolved and valid', S.cfg.engine.valid === true && $('engPath').textContent.length > 0,
      { path: $('engPath').textContent, version: $('vCfg').textContent, valid: $('engValid').textContent });
    const rawKey = CF.doc.globals.api_key;
    const rawKeyInDOM = document.documentElement.outerHTML.includes(rawKey) ||
      Array.from(document.querySelectorAll('input')).some(input => input.value.includes(rawKey));
    check('raw key never rendered', !rawKeyInDOM, { rawKeyInDOM });
    check('key masked readonly', $('cfgKey').readOnly && $('cfgKey').value.length > 0 && $('cfgKey').value !== rawKey,
      { masked: $('cfgKey').value, readonly: $('cfgKey').readOnly });
    const folders = Array.from(document.querySelectorAll('#folderList .frow')).map(row => ({
      id: row.querySelector('.fname').textContent, status: row.querySelector('.fstat').textContent,
      modelCount: Number((row.querySelector('.fmeta').textContent.match(/(\d+) model/) || [0, 0])[1])
    }));
    check('folder rows populated', folders.length === expected.folderCount, folders);
    check('at least one configured folder present', folders.some(folder => folder.status === 'PRESENT'), folders);
    check('adoption stamps restart baseline', S.cfg.restart_required === false, S.cfg.restart_required);
    if (expected.roundTrips) {
      async function save(step, port, ane, restart) {
        if (CF.validateTimer) { clearTimeout(CF.validateTimer); CF.validateTimer = null; }
        if (CF.draft.port !== port) {
          $('cfgPort').value = String(port); $('cfgPort').dispatchEvent(new Event('change'));
        }
        if (CF.draft.ane !== ane) $(ane ? 'aneOn' : 'aneOff').click();
        if (CF.validateTimer) { clearTimeout(CF.validateTimer); CF.validateTimer = null; }
        $('btnCfgSave').click();
        // Wait for the actual save result + computed tick state, never a fixed sleep.
        await until(() => !cfDirty() && S.cfg.port === port && S.cfg.profiles[0].options.ane === ane &&
          S.cfg.restart_required === restart && $('cfgMsg').textContent.startsWith('Saved'),
          step, port === 8199 ? 3500 : 6000);
        const actual = snapshot(step);
        check(step, actual.draftPort === port && actual.ane === ane && actual.savedAne === ane &&
          actual.restart_required === restart && actual.manualPath === expected.manualPath &&
          actual.draftManualPath === expected.manualPath &&
          actual.footer === (restart ? 'RESTART TO APPLY' : 'Restart'), actual);
      }
      try {
        await save('port_8199_saved', 8199, true, true);
        await save('port_8123_restored', 8123, true, false);
        await save('ane_off_saved', 8123, false, true);
        await save('ane_on_restored', 8123, true, false);
      } finally {
        // Best effort restore through the bridge; the runner always restores exact bytes.
        if (CF.draft.port !== expected.port || CF.draft.ane !== expected.ane) {
          CF.draft.port = expected.port; CF.draft.ane = expected.ane; cfSyncForm(); cfSave();
        }
      }
      await until(() => S.server.pid === expected.enginePID, 'original engine still adopted');
      snapshot('final');
    }
  } catch (error) { check('live hook completed', false, error.message); }
  const failed = checks.filter(item => !item.pass).length;
  return JSON.stringify({ suite: 'panel-live', checks, steps, ignoredInput, assertions: checks.length,
    passed: checks.length - failed, failed });
})()
