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
    const sel = CF.draft ? CF.draft.profiles.find(p => p.id === CF.profileId) : null;
    const value = {
      step, elapsed_ms: Date.now() - started,
      port: $('cfgPort').value, draftPort: CF.draft.port,
      manualPath: $('manualPath').value, draftManualPath: CF.draft.manualPath,
      selectedProfile: sel ? sel.id : null,
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
    check('status opens with telemetry only', !$('statusView').hidden && $('settingsView').hidden &&
      !$('statusView').querySelector('section.settings-global, section.settings-profiles') &&
      $('statusView').querySelectorAll('section').length === 5, $('statusView').hidden);
    const geometry = { width: innerWidth, height: innerHeight };
    $('btnSettings').click();
    check('hamburger opens settings in the same viewport', $('statusView').hidden && !$('settingsView').hidden &&
      innerWidth === geometry.width && innerHeight === geometry.height && $('settingsView').scrollTop === 0, geometry);
    check('settings scrolls internally with shared footer reachable', getComputedStyle($('settingsView')).overflowY === 'auto' &&
      $('btnRestart').getBoundingClientRect().bottom <= innerHeight && $('btnRestart').getBoundingClientRect().top >= 0,
      { overflow: getComputedStyle($('settingsView')).overflowY, footerBottom: $('btnRestart').getBoundingClientRect().bottom });
    check('settings header: title, back cap, engine state', $('s7Title').textContent.trim().length > 0 &&
      $('settingsHeader').contains($('btnStatus')) && $('s7EngState').textContent.length > 0,
      { title: $('s7Title').textContent, engState: $('s7EngState').textContent });
    $('btnStatus').click();
    check('back cap returns to status without resizing', !$('statusView').hidden && $('settingsView').hidden &&
      innerWidth === geometry.width && innerHeight === geometry.height, $('statusView').scrollTop);
    $('btnSettings').click();
    check('engine adopted not relaunched', S.server.pid === expected.enginePID && S.server.launched_by_app === false,
      { pid: S.server.pid, launched_by_app: S.server.launched_by_app });
    check('engine resolved and valid', S.cfg.engine.valid === true && $('engPath').textContent.length > 0 &&
      $('vCfg').textContent.length > 0 && $('engValid').textContent.length > 0,
      { path: $('engPath').textContent, version: $('vCfg').textContent, verdict: $('engValid').textContent });
    check('verdict cap is a known S7 state', ['valid', 'fallback', 'unrunnable'].some(c => $('engValid').classList.contains(c)),
      $('engValid').className);
    const rawKey = CF.doc.globals.api_key;
    const rawKeyInDOM = document.documentElement.outerHTML.includes(rawKey) ||
      Array.from(document.querySelectorAll('input')).some(input => input.value.includes(rawKey));
    check('raw key never rendered', !rawKeyInDOM, { rawKeyInDOM });
    check('key masked readonly', $('cfgKey').readOnly && $('cfgKey').value.length > 0 && $('cfgKey').value !== rawKey,
      { masked: $('cfgKey').value, readonly: $('cfgKey').readOnly });
    const folders = Array.from(document.querySelectorAll('#folderList .frow')).map(row => ({
      source: row.querySelector('.fname').textContent, status: row.querySelector('.fstat').textContent,
      modelCount: Number((row.querySelector('.fmeta').textContent.match(/(\d+) model/) || [0, 0])[1])
    }));
    check('folder rows populated', folders.length === expected.folderCount, folders);
    check('at least one configured folder present', folders.some(folder => folder.status === 'PRESENT'), folders);
    check('adoption stamps restart baseline', S.cfg.restart_required === false, S.cfg.restart_required);
    const profileRows = () => Array.from(document.querySelectorAll('#profileList .profrow'));
    check('profiles list rendered on settings screen', $('settingsView').contains($('profileList')) &&
      profileRows().length === S.cfg.profiles.length, profileRows().length);
    check('active profile marked with the selection dot', S.cfg.active_profile !== null &&
      profileRows().some(row => row.querySelector('.profdot.on') !== null), $('profileList').textContent);
    check('five profile tabs present', document.querySelectorAll('#settingsView [data-ptab]').length === 5,
      document.querySelectorAll('#settingsView [data-ptab]').length);

    // S7 whole-document contract check — one pass over the app's full config doc:
    // the app's own validator (schema + normalize + the option contract) judges the
    // entire document, every profile, every global. This covers every setting
    // (ANE included) simultaneously; no per-setting DOM assertions.
    if (CF.validateTimer) { clearTimeout(CF.validateTimer); CF.validateTimer = null; }
    CF.validationID = (CF.validationID || 0) + 1;
    CF.validationBaseline = JSON.stringify(CF.draft);
    cmd('config.validate', { doc: cfBuildDoc(), validation_id: CF.validationID });
    await until(() => cfgValidateResult && cfgValidateResult.validation_id === CF.validationID, 'whole-doc validate', 15000);
    const sameJSON = (a, b) => JSON.stringify(a) === JSON.stringify(b);
    const verdicts = new Set((cfgValidateResult.profiles || []).map(v => v.id));
    const ids = CF.draft.profiles.map(p => p.id);
    const built = cfBuildDoc();
    const g = built.globals, og = CF.doc.globals;
    const globalsIntact = g.port === og.port && g.host === og.host && g.api_key === og.api_key &&
      g.web_ui === og.web_ui && sameJSON(g.allowed_hosts, og.allowed_hosts) &&
      sameJSON(g.allowed_origins, og.allowed_origins) && sameJSON(g.model_folders, og.model_folders) &&
      g.engine.mode === og.engine.mode && g.engine.manual_path === og.engine.manual_path;
    const profilesIntact = built.profiles.length === CF.doc.profiles.length && built.profiles.every(p => {
      const o = CF.doc.profiles.find(x => x.id === p.id);
      return o && o.model.source === p.model.source && (o.model.id ?? null) === (p.model.id ?? null) &&
        sameJSON(o.options, p.options);
    });
    check('whole doc validates against the contract (all globals + every profile)',
      cfgValidateResult.ok === true && cfgValidateResult.errors.length === 0,
      { errors: cfgValidateResult.errors, warnings: cfgValidateResult.warnings });
    check('whole doc round-trips unchanged through draft + rebuild',
      globalsIntact && profilesIntact && (built.active_profile ?? null) === (CF.doc.active_profile ?? null),
      { profiles: built.profiles.length, optionDefs: (CF.optionDefs || S.cfg.option_defs || []).length });
    check('per-profile verdicts cover every profile', verdicts.size === ids.length && ids.every(id => verdicts.has(id)), [...verdicts]);

    if (expected.roundTrips) {
      async function save(step, port, restart) {
        if (CF.validateTimer) { clearTimeout(CF.validateTimer); CF.validateTimer = null; }
        if (CF.draft.port !== port) {
          $('cfgPort').value = String(port); $('cfgPort').dispatchEvent(new Event('change'));
        }
        if (CF.validateTimer) { clearTimeout(CF.validateTimer); CF.validateTimer = null; }
        // S7: there is no save button — a passing validation auto-saves the dirty draft.
        CF.validationID = (CF.validationID || 0) + 1;
        CF.validationBaseline = JSON.stringify(CF.draft);
        cmd('config.validate', { doc: cfBuildDoc(), validation_id: CF.validationID });
        // Wait for the actual save result + computed tick state, never a fixed sleep.
        await until(() => !cfDirty() && S.cfg.port === port && S.cfg.restart_required === restart &&
          $('cfgMsg').textContent.startsWith('Saved'),
          step, port === 8199 ? 3500 : 6000);
        const actual = snapshot(step);
        check(step, actual.draftPort === port && actual.restart_required === restart &&
          actual.manualPath === expected.manualPath && actual.draftManualPath === expected.manualPath &&
          actual.footer === (restart ? 'Restart to apply' : 'Restart'), actual);
      }
      await save('port_8199_saved', 8199, true);
      await save('port_8123_restored', 8123, false);
      await until(() => S.server.pid === expected.enginePID, 'original engine still adopted');
      snapshot('final');

      // S7: a live warning state left visible for the evidence screenshot — the
      // verdict cap's fallback state. JS-only: config.json is already restored,
      // the engine is never touched.
      const engine = S.cfg.engine, actualVersion = engine.version, actualVerdict = engine.verdict,
        actualReason = engine.verdict_reason, actualMappingUsed = S.cfg.mapping_used, actualReport = S.cfg.registry_report;
      const fakeWarning = () => { S.cfg.mapping_used = '1.3.2'; S.cfg.registry_report = { missing_in_kit: ['--no-such-flag'] };
        engine.version = '9.9.9'; engine.verdict = 'fallback'; engine.verdict_reason = null; };
      const restoreWarning = () => { S.cfg.mapping_used = actualMappingUsed; S.cfg.registry_report = actualReport;
        engine.version = actualVersion; engine.verdict = actualVerdict; engine.verdict_reason = actualReason; };
      fakeWarning(); window.update({ ...S });
      await until(() => $('engValid').classList.contains('fallback'), 'fallback cap renders');
      const cap = $('engValid');
      check('S7 verdict cap renders the fallback state with the registry fix tip',
        cap.textContent.includes('FALLBACK MAPPING') && /Run a matching engine v1\.3\.2|update the mapping registry/.test(cap.dataset.tip || ''),
        { text: cap.textContent, tip: cap.dataset.tip });
      restoreWarning(); window.update({ ...S });
      await until(() => !$('engValid').classList.contains('fallback'), 'verdict cap restored');
      // A real 1s tick can fire between the hook end and the runner's screencapture;
      // wrap window.update to re-assert the warning on every subsequent payload so the
      // evidence screenshot deterministically shows the cap.
      const realUpdate = window.update;
      window.update = payload => { realUpdate(payload);
        if (payload && payload.cfg) {
          payload.cfg.mapping_used = '1.3.2'; payload.cfg.registry_report = { missing_in_kit: ['--no-such-flag'] };
          if (payload.cfg.engine) { payload.cfg.engine.version = '9.9.9'; payload.cfg.engine.verdict = 'fallback'; payload.cfg.engine.verdict_reason = null; }
          realUpdate(payload);
        } };
      fakeWarning();
      $('vCfg').textContent = '9.9.9';
      realUpdate({ ...S });
      await until(() => $('engValid').classList.contains('fallback'), 'fallback cap re-shown for evidence');
      await sleep(200);
      // Leave the warning visible at the top of the engine panel for the evidence screenshot.
      cap.scrollIntoView({ block: 'start' });
      snapshot('s7_warning_visible');
    }
  } catch (error) { check('live hook completed', false, error.message); }
  const failed = checks.filter(item => !item.pass).length;
  return JSON.stringify({ suite: 'panel-live', checks, steps, ignoredInput, assertions: checks.length,
    passed: checks.length - failed, failed });
})()
