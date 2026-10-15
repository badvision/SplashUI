import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { once } from 'node:events';
import { createHash } from 'node:crypto';
import { chmodSync, closeSync, existsSync, mkdtempSync, openSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../..');
const roundTrips = process.argv.includes('--round-trips');
assert.ok(process.argv.slice(2).every(arg => arg === '--round-trips'), 'usage: live_smoke.sh [--round-trips]');
assert.equal(process.platform, 'darwin', 'live smoke requires macOS and a graphical login');
const configPath = process.env.SPLASHUI_CONFIG || join(homedir(), 'Library/Application Support/SplashUI/config.json');
assert.equal(process.env.SPLASHUI_CONFIG, undefined, 'the app uses its standard config path; overrides are not supported');
const binary = join(root, 'build/SplashUI.app/Contents/MacOS/splash-launcher');
assert.ok(existsSync(binary), 'run ./build.sh first');
const original = readFileSync(configPath), mode = statSync(configPath).mode & 0o777;
const doc = JSON.parse(original), hash = data => createHash('sha256').update(data).digest('hex');
const originalHash = hash(original), port = doc.globals.port;
if (roundTrips) {
  assert.equal(port, 8123, 'round-trip fixture must begin at port 8123');
  assert.equal(doc.profiles[0].options.ane, true, 'round-trip fixture must begin with ANE enabled');
}
function pids(name) {
  try { return execFileSync('pgrep', ['-x', name], { encoding: 'utf8' }).trim().split(/\s+/).filter(Boolean); }
  catch (error) { if (error.status === 1) return []; throw error; }
}
assert.deepEqual(pids('splash-launcher'), [], 'quit existing SplashUI app first (never stop the engine)');
function listeners() {
  return [...new Set(execFileSync('lsof', ['-nP', '-t', `-iTCP:${port}`, '-sTCP:LISTEN'], { encoding: 'utf8' }).trim().split(/\s+/))];
}
const enginePIDs = listeners();
assert.equal(enginePIDs.length, 1, 'exactly one engine must already be listening');
const enginePID = Number(enginePIDs[0]);
const directory = mkdtempSync('/tmp/splashui-live-');
chmodSync(directory, 0o700);
const output = join(directory, 'result.json'), evidence = join(directory, 'evidence.png');
writeFileSync(join(directory, 'config.before.json'), original, { mode: 0o600 });
const expected = { port, enginePID, roundTrips, manualPath: doc.globals.engine.manual_path || '',
  engineMode: doc.globals.engine.mode, ane: doc.profiles[0].options.ane,
  folderCount: doc.globals.model_folders.length };
const hookPath = join(directory, 'assertions.js');
writeFileSync(hookPath, readFileSync(join(here, 'live_assertions.js'), 'utf8')
  .replace('/* EXPECTED */', JSON.stringify(expected)), { mode: 0o600 });
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function engineHealth() {
  process.kill(enginePID, 0);
  const url = `http://127.0.0.1:${port}/v1/models`;
  const authenticated = await fetch(url, { headers: { 'x-api-key': doc.globals.api_key }, signal: AbortSignal.timeout(2000) });
  await authenticated.arrayBuffer();
  const anonymous = await fetch(url, { signal: AbortSignal.timeout(2000) });
  await anonymous.arrayBuffer();
  assert.equal(authenticated.status, 200, 'engine must keep serving with key');
  assert.equal(anonymous.status, 401, 'engine must reject missing key');
  return { pid: enginePID, with_key: authenticated.status, without_key: anonymous.status };
}
let app, cleaned = false, interrupted = false;
function restore() {
  writeFileSync(configPath, original, { mode }); chmodSync(configPath, mode);
}
async function cleanup() {
  if (cleaned) return;
  cleaned = true;
  // Terminate only the app PID launched here; never send the bridge's Stop command.
  if (app && app.exitCode === null && app.signalCode === null) {
    const exited = once(app, 'exit'); app.kill('SIGTERM');
    await Promise.race([exited, sleep(2500)]);
    if (app.exitCode === null && app.signalCode === null) { app.kill('SIGKILL'); await exited; }
  }
  restore();
}
for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(signal, () => {
  interrupted = true;
  cleanup().then(() => process.exit(130));
});
process.on('exit', () => { if (app) { try { app.kill('SIGTERM'); } catch {} } restore(); });
try {
  const initialHealth = await engineHealth();
  const log = openSync(join(directory, 'app.log'), 'w', 0o600);
  try {
    app = spawn(binary, [], { env: { ...process.env, SPLASHUI_SMOKE: '1', SPLASHUI_SMOKE_CHANNEL: '06',
      SPLASHUI_SMOKE_JS: hookPath, SPLASHUI_SMOKE_OUT: output }, stdio: ['ignore', log, log] });
  } finally { closeSync(log); }
  const deadline = Date.now() + 45000;
  let changedPortAt = null, nextHealthAt = 0, samples = 0;
  while (!existsSync(output)) {
    assert.ok(!interrupted, 'interrupted');
    assert.equal(app.exitCode, null, 'app exited before producing assertions');
    assert.ok(Date.now() < deadline, `timed out; app log: ${join(directory, 'app.log')}`);
    const savedPort = JSON.parse(readFileSync(configPath, 'utf8')).globals.port;
    if (savedPort === 8199) changedPortAt ??= Date.now(); else changedPortAt = null;
    assert.ok(changedPortAt === null || Date.now() - changedPortAt < 4500, '8199 window exceeded 4.5s watchdog');
    if (Date.now() >= nextHealthAt) { await engineHealth(); samples++; nextHealthAt = Date.now() + 400; }
    await sleep(50);
  }
  const result = JSON.parse(readFileSync(output, 'utf8'));
  for (const item of result.checks || []) console.log(JSON.stringify(item));
  for (const step of result.steps || []) console.log(JSON.stringify({ step }));
  assert.equal(result.suite, 'panel-live', `unexpected hook result: ${JSON.stringify(result)}`);
  assert.equal(result.failed, 0, 'live DOM assertions failed');
  assert.ok(result.assertions >= (roundTrips ? 16 : 12), 'hook must execute every requested assertion');
  execFileSync('screencapture', ['-x', evidence]); // Evidence only; never parsed or compared.
  await cleanup();
  assert.equal(hash(readFileSync(configPath)), originalHash, 'config must be restored byte-identical');
  assert.deepEqual(listeners(), enginePIDs, 'original engine PID must still own the port');
  assert.deepEqual(pids('splash-launcher'), [], 'no stray app processes');
  const finalHealth = await engineHealth();
  const summary = { suite: result.suite, assertions: result.assertions, failed: 0,
    engine_samples: samples, initialHealth, finalHealth, config_sha256: originalHash,
    config_restored: true, evidence, output, app_processes: [] };
  writeFileSync(join(directory, 'summary.json'), JSON.stringify(summary, null, 2) + '\n');
  console.log(JSON.stringify(summary));
} catch (error) {
  await cleanup();
  console.error(JSON.stringify({ suite: 'panel-live', failed: 1, error: error.message,
    config_restored: hash(readFileSync(configPath)) === originalHash, output, directory }));
  process.exitCode = 1;
}
