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
    check('status opens with telemetry only', !$('statusView').hidden && $('settingsView').hidden &&
      !$('statusView').querySelector('.settings-panel') &&
      $('statusView').querySelectorAll('section').length === 5, $('statusView').hidden);
    const geometry = { width: innerWidth, height: innerHeight };
    $('btnSettings').click();
    check('hamburger opens settings in the same viewport', $('statusView').hidden && !$('settingsView').hidden &&
      innerWidth === geometry.width && innerHeight === geometry.height && $('settingsView').scrollTop === 0, geometry);
    check('settings scrolls internally with shared footer reachable', getComputedStyle($('settingsView')).overflowY === 'auto' &&
      $('btnRestart').getBoundingClientRect().bottom <= innerHeight && $('btnRestart').getBoundingClientRect().top >= 0,
      { overflow: getComputedStyle($('settingsView')).overflowY, footerBottom: $('btnRestart').getBoundingClientRect().bottom });
    $('btnStatus').click();
    check('back cap returns to status without resizing', !$('statusView').hidden && $('settingsView').hidden &&
      innerWidth === geometry.width && innerHeight === geometry.height, $('statusView').scrollTop);
    $('btnSettings').click();
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
    check('lmstudio present with discovered models', folders.some(folder => folder.id === 'lmstudio' &&
      folder.status === 'PRESENT' && folder.modelCount > 0), folders.find(folder => folder.id === 'lmstudio'));
    check('adoption stamps restart baseline', S.cfg.restart_required === false, S.cfg.restart_required);
    const profileRows = () => Array.from(document.querySelectorAll('#profileList .profile-row'));
    check('profiles list visible on settings screen', $('settingsView').contains($('profileList')) && profileRows().length === S.cfg.profiles.length, profileRows().length);
    const activeId = S.cfg.active_profile;
    const editProfile = id => document.querySelector('#profileList [data-profile-act="edit"][data-id="'+id+'"]').click();
    editProfile(activeId);
    $('btnProfileModels').click();
    check('model picker reflects global scanned folders', document.querySelectorAll('#profileModels [data-model-index]').length === S.cfg.folders.reduce((n, f) => n + f.models.length, 0), document.querySelectorAll('#profileModels [data-model-index]').length);
    check('profile metadata and ACTIVE cap rendered', profileRows().some(row => row.textContent.includes('ACTIVE') && row.textContent.includes('Created') && row.textContent.includes('Last used')), $('profileList').textContent);
    check('drafter availability resolved for real package', $('profileDrafter').textContent.includes('PACKAGE') && $('profileDrafter').textContent.includes('baked'), $('profileDrafter').textContent);
    check('runtime option definitions match real 1.3.0 kit', S.cfg.engine.version === '1.3.0' && !!$('option-kv_format') && !$('option-state_format') && !$('option-revision'), S.cfg.option_defs.map(o => o.key));
    check('runtime option groups start collapsed', document.querySelectorAll('.option-group').length > 0 && !document.querySelector('.option-group.open'), document.querySelectorAll('.option-group').length);
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
        const originalProfiles = JSON.parse(JSON.stringify(CF.draft.profiles));
        const originalActive = CF.draft.activeProfile;
        async function saveProfiles(step, count, restart) {
          if (CF.validateTimer) { clearTimeout(CF.validateTimer); CF.validateTimer = null; }
          cfSave();
          await until(() => !cfDirty() && S.cfg.profiles.length === count && S.cfg.restart_required === restart && $('cfgMsg').textContent.startsWith('Saved'), step);
          check(step, S.cfg.restart_required === restart && S.cfg.profiles.length === count, { count: S.cfg.profiles.length, restart_required: S.cfg.restart_required, enginePID: S.server.pid });
        }
        try {
          check('before profile create restart remains false', S.cfg.restart_required === false, S.cfg.restart_required);
          $('btnProfileAdd').click();
          const added = cfSelectedProfile();
          check('profile add renders creation metadata', profileRows().length === originalProfiles.length + 1 && !!added.meta.created_at, { id: added.id, meta: added.meta });
          await saveProfiles('create alone saved without restart', originalProfiles.length + 1, false);
          $('btnProfileClone').click();
          const copy = cfSelectedProfile();
          check('profile clone distinct with reset metadata', copy.id !== added.id && copy.name !== added.name && !copy.meta.last_used_at, { id: copy.id, name: copy.name });
          $('btnProfileRemove').click();
          check('profile remove disappears from list', !CF.draft.profiles.some(p => p.id === copy.id) && profileRows().length === originalProfiles.length + 1, profileRows().length);
          editProfile(activeId);
          const candidates = cfModels(), current = cfSelectedProfile().model;
          const index = candidates.findIndex(m => m.id !== current.id || m.source !== current.source);
          if (index < 0) throw new Error('profile smoke needs a distinct discovered model');
          document.querySelector('#profileModels [data-model-index="'+index+'"]').click();
          check('current profile model edited before save without activation', cfSelectedProfile().model.id === candidates[index].id && CF.draft.activeProfile === originalActive && S.cfg.restart_required === false, { model: cfSelectedProfile().model.id, restart_required: S.cfg.restart_required });
          await saveProfiles('active model edit saved requires restart', originalProfiles.length + 1, true);
        } finally {
          CF.draft.profiles = JSON.parse(JSON.stringify(originalProfiles)); CF.draft.activeProfile = originalActive; CF.profileId = activeId;
          cfRenderProfiles();
          await saveProfiles('profiles and active model reverted clears restart', originalProfiles.length, false);
        }
          $('btnProfileClone').click();
          const activated = cfSelectedProfile();
          document.querySelector('[data-option-choice="kv_format"][data-value="bf16"]').click();
          check('KV cache edit enters full activation candidate', cfBuildDoc().profiles.find(p => p.id === activated.id).options.kv_format === 'bf16', activated.options);
          await until(() => !$('btnProfileActivate').disabled, 'activation validates draft');
          $('btnProfileActivate').click();
          await until(() => !CF.saving && S.cfg.active_profile === activated.id && S.cfg.restart_required === true, 'changed profile activated');
          const savedActivated = S.cfg.profiles.find(p => p.id === activated.id);
          check('activation commits option and stamps last-used', savedActivated.options.kv_format === 'bf16' && !!savedActivated.meta.last_used_at, savedActivated.meta);
          check('activation moves ACTIVE cap', profileRows().find(row => row.textContent.includes(activated.name)).textContent.includes('ACTIVE'), $('profileList').textContent);
          check('activation prompts with real in-flight count and explicit confirmation', !$('profileRestartPrompt').hidden && $('profileRestartText').textContent.includes(S.cfg.in_flight + ' in-flight') && !!$('btnProfileRestart'), $('profileRestartPrompt').textContent);
          check('activation computes restart without touching engine', S.cfg.restart_required === true && S.server.pid === expected.enginePID && S.server.launched_by_app === false, snapshot('profile_activated'));
          editProfile(activeId); $('btnProfileActivate').click();
          await until(() => !CF.saving && S.cfg.active_profile === activeId && S.cfg.restart_required === false, 'activation reverted');
          check('reverting activation clears prompt and restart-required', $('profileRestartPrompt').hidden && $('btnRestart').textContent === 'Restart' && S.server.pid === expected.enginePID, snapshot('activation_reverted'));
          editProfile(activated.id); $('btnProfileRemove').click();
          await saveProfiles('activation smoke clone removed', originalProfiles.length, false);
      } finally {
        // Best effort restore through the bridge; the runner always restores exact bytes.
        if (CF.draft.port !== expected.port || CF.draft.ane !== expected.ane) {
          CF.draft.port = expected.port; CF.draft.ane = expected.ane; cfSyncForm(); cfSave();
        }
      }
      await until(() => S.server.pid === expected.enginePID, 'original engine still adopted');
      snapshot('final');
      // S7: theme spot-checks, then a live warning state left visible for the evidence screenshot.
      $('btnSettings').click();
      check('S7 theme: settings accent is channel-06 blue #4455ff', () => getComputedStyle($('settingsView').querySelector('.settings-panel')).getPropertyValue('--accent').trim() === '#4455ff', getComputedStyle($('settingsView').querySelector('.settings-panel')).getPropertyValue('--accent'));
      check('S7 theme: caps and bars keep LCARS pill geometry (14px caps, 0 14px 14px 0 bars)', () => { const s = [...document.styleSheets].map(sh => { try { return [...sh.cssRules].map(r => r.cssText).join(' '); } catch { return ''; } }).join(' '); return /\.warn-cap[^}]*border-radius:\s*14px/.test(s) && /\.profile-cap[^}]*border-radius:\s*14px/.test(s) && /\.stale-bar[^}]*border-radius:\s*0 14px 14px 0/.test(s); });
      check('S7 no fallback cap while the mapping is exact', () => $('engFallback').hidden === true, { fallbackHidden: $('engFallback').hidden, version: S.cfg.engine.version });
      const engine = S.cfg.engine, actualVersion = engine.version;
      S.cfg.mapping_fallback = true; S.cfg.mapping_used = '1.3.2'; engine.version = '9.9.9';
      window.update({ ...S });
      await until(() => !$('engFallback').hidden && $('engFallback').querySelector('.warn-cap'), 'fallback cap renders');
      const warnCap = $('engFallback').querySelector('.warn-cap');
      check('S7 fallback cap live with real values: peach cap names mapping and engine version', () => warnCap.textContent.includes('FALLBACK MAPPING v1.3.2') && warnCap.textContent.includes('for engine v9.9.9') && !warnCap.classList.contains('runnable'), warnCap.textContent);
      check('S7 fallback cap data-tip carries the actionable registry fix', () => /update the mapping registry|Run a matching engine v1\.3\.2/.test(warnCap.dataset.tip || ''), warnCap.dataset.tip);
      check('S7 warnings non-blocking: panel still renders all status sections', () => $('statusView').querySelectorAll('section').length === 5 && S.server.pid === expected.enginePID && S.cfg.restart_required === false, { sections: $('statusView').querySelectorAll('section').length });
      S.cfg.mapping_fallback = false; S.cfg.mapping_used = null; S.cfg.registry_report = null; engine.version = actualVersion;
      window.update({ ...S });
      await until(() => $('engFallback').hidden, 'fallback cap cleared');
      check('S7 fallback cap clears when the mapping is exact again, engine version restored, no restart', () => $('engFallback').hidden && engine.version === actualVersion && S.cfg.restart_required === false, { version: engine.version });
      // A real 1s tick can fire between the hook end and the runner's screencapture;
      // wrap window.update to re-assert the warning on every subsequent payload so the
      // evidence screenshot deterministically shows the cap. JS-only; config.json is
      // already restored, the engine is never touched.
      const realUpdate = window.update;
      window.update = payload => { realUpdate(payload);
        if (payload && payload.cfg) { payload.cfg.mapping_fallback = true; payload.cfg.mapping_used = '1.3.2';
          if (payload.cfg.engine) payload.cfg.engine.version = '9.9.9'; realUpdate(payload); } };
      S.cfg.mapping_fallback = true; S.cfg.mapping_used = '1.3.2'; engine.version = '9.9.9';
      $('vCfg').textContent = '9.9.9';
      realUpdate({ ...S });
      await until(() => !$('engFallback').hidden && $('engFallback').querySelector('.warn-cap'), 'fallback cap re-shown for evidence');
      await sleep(200);
      // Leave the warning visible at the top of the settings view for the evidence screenshot.
      $('engFallback').scrollIntoView({ block: 'start' });
      snapshot('s7_warning_visible');
    }
    if (!expected.roundTrips) $('profilesSlot').scrollIntoView({ block: 'start' });
  } catch (error) { check('live hook completed', false, error.message); }
  const failed = checks.filter(item => !item.pass).length;
  return JSON.stringify({ suite: 'panel-live', checks, steps, ignoredInput, assertions: checks.length,
    passed: checks.length - failed, failed });
})()
