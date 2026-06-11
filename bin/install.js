#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync, spawnSync } = require('child_process');

const VERSION = fs.readFileSync(path.join(__dirname, '..', 'VERSION'), 'utf8').trim();
const PLUGIN_ROOT = path.resolve(__dirname, '..');
const HOOKS_TARGET = path.join(os.homedir(), '.claude', 'hooks', 'multica');
const CLAUDE_DIR = path.join(os.homedir(), '.claude');
const SETTINGS_PATH = (() => {
  const custom = process.env.CLAUDE_SETTINGS_PATH;
  if (custom) {
    const resolved = path.resolve(custom);
    // Reject paths outside ~/.claude/ to prevent CLAUDE_SETTINGS_PATH injection
    if (!resolved.startsWith(CLAUDE_DIR + path.sep) && resolved !== path.join(CLAUDE_DIR, 'settings.json')) {
      console.error(`\x1b[31m[error]\x1b[0m CLAUDE_SETTINGS_PATH must be inside ${CLAUDE_DIR}`);
      process.exit(1);
    }
    return resolved;
  }
  return path.join(CLAUDE_DIR, 'settings.json');
})();

// Colors
const G = '\x1b[32m', Y = '\x1b[33m', R = '\x1b[31m', B = '\x1b[1m', X = '\x1b[0m';
const ok = (s) => console.log(`${G}[install]${X} ${s}`);
const warn = (s) => console.log(`${Y}[warn]${X} ${s}`);
const err = (s) => console.error(`${R}[error]${X} ${s}`);

// Parse JSONC (JSON with comments) safely — distinguishes // inside strings from line comments
function parseJsonc(str) {
  // Strip BOM
  if (str.charCodeAt(0) === 0xFEFF) str = str.slice(1);
  let result = '';
  let inString = false;
  let i = 0;
  while (i < str.length) {
    const ch = str[i];
    if (inString) {
      result += ch;
      if (ch === '\\') { result += str[++i] || ''; } // escaped char
      else if (ch === '"') { inString = false; }
      i++;
    } else if (ch === '"') {
      inString = true; result += ch; i++;
    } else if (ch === '/' && str[i + 1] === '/') {
      // line comment — skip to end of line
      while (i < str.length && str[i] !== '\n') i++;
    } else if (ch === '/' && str[i + 1] === '*') {
      // block comment — skip to */
      i += 2;
      while (i < str.length && !(str[i] === '*' && str[i + 1] === '/')) i++;
      i += 2;
    } else {
      result += ch; i++;
    }
  }
  // Strip trailing commas before } or ] (common in JSONC)
  result = result.replace(/,(\s*[}\]])/g, '$1');
  return JSON.parse(result);
}

function readSettings() {
  if (!fs.existsSync(SETTINGS_PATH)) return {};
  // Refuse to operate on symlinks to prevent reading unintended files
  const st = fs.lstatSync(SETTINGS_PATH);
  if (st.isSymbolicLink()) {
    warn(`${SETTINGS_PATH} is a symbolic link — skipping read (will create fresh)`);
    return {};
  }
  const raw = fs.readFileSync(SETTINGS_PATH, 'utf8');
  try { return JSON.parse(raw); }
  catch {
    try { return parseJsonc(raw); }
    catch (e) {
      // fail-closed: corrupt settings.json → do not silently return {}
      err(`Failed to parse ${SETTINGS_PATH}: ${e.message}`);
      err('Backup is at ' + SETTINGS_PATH + '.bak (if it exists). Fix manually and re-run.');
      process.exit(1);
    }
  }
}

function writeSettings(settings) {
  const dir = path.dirname(SETTINGS_PATH);
  fs.mkdirSync(dir, { recursive: true });
  const content = JSON.stringify(settings, null, 2) + '\n';
  // Backup existing file before writing
  if (fs.existsSync(SETTINGS_PATH)) {
    fs.copyFileSync(SETTINGS_PATH, SETTINGS_PATH + '.bak');
  }
  // Atomic write via tmp + rename
  const tmp = SETTINGS_PATH + '.tmp.' + process.pid;
  fs.writeFileSync(tmp, content, { mode: 0o600 });
  fs.renameSync(tmp, SETTINGS_PATH);
}

// REQ-09-01: semver-ish comparison ("1.2.3" vs "0.4.0") → -1 | 0 | 1
function cmpVersion(a, b) {
  const pa = String(a).split('.').map(n => parseInt(n, 10) || 0);
  const pb = String(b).split('.').map(n => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = pa[i] || 0, y = pb[i] || 0;
    if (x !== y) return x < y ? -1 : 1;
  }
  return 0;
}

function getCmdVersion(cmd) {
  const r = spawnSync(cmd, ['--version'], { encoding: 'utf8' });
  if (r.error) return null;
  const m = ((r.stdout || '') + (r.stderr || '')).match(/(\d+\.\d+\.\d+)/);
  return m ? m[1] : '';
}

// REQ-09-04: daemon deployments have MULTICA_AGENT_SESSION=1 or MULTICA_WORKDIR
// set; shell-profile and "restart Claude Code" guidance does not apply there.
function isDaemonMode() {
  return process.env.MULTICA_AGENT_SESSION === '1' || !!process.env.MULTICA_WORKDIR;
}

const HEALTH_PATH = path.join(HOOKS_TARGET, 'install-health.json');

// REQ-09-03: machine-readable install diagnostics, written next to the hooks
// (stable location; the install runs outside any multica workdir, so the
// AC's workdir-relative .multica/ path is not resolvable at install time).
function writeHealth(steps) {
  const health = {
    timestamp: new Date().toISOString(),
    plugin_version: VERSION,
    os: `${os.platform()} ${os.release()}`,
    node: process.version,
    shell: detectShell(),
    daemon_mode: isDaemonMode(),
    multica_version: getCmdVersion('multica'),
    python3_version: getCmdVersion('python3'),
    git_version: getCmdVersion('git'),
    steps,
  };
  try {
    fs.mkdirSync(HOOKS_TARGET, { recursive: true });
    fs.writeFileSync(HEALTH_PATH, JSON.stringify(health, null, 2) + '\n');
    ok(`Install health written to ${HEALTH_PATH}`);
  } catch (e) {
    warn(`Could not write install health: ${e.message}`);
  }
  return health;
}

function detectShell() {
  const shell = process.env.SHELL || '';
  if (shell.includes('zsh')) return 'zsh';
  if (shell.includes('fish')) return 'fish';
  return 'bash';
}

function getShellProfile(shell) {
  const home = os.homedir();
  if (shell === 'zsh') return path.join(home, '.zshrc');
  if (shell === 'fish') return path.join(home, '.config', 'fish', 'config.fish');
  // bash: prefer .bashrc, fallback to .bash_profile
  const bashrc = path.join(home, '.bashrc');
  return fs.existsSync(bashrc) ? bashrc : path.join(home, '.bash_profile');
}

function installHooks() {
  // Copy hooks to stable location
  fs.mkdirSync(HOOKS_TARGET, { recursive: true });
  const hooksDir = path.join(PLUGIN_ROOT, 'hooks');
  const scripts = fs.readdirSync(hooksDir).filter(f => f.endsWith('.sh'));
  for (const script of scripts) {
    const src = path.join(hooksDir, script);
    const dst = path.join(HOOKS_TARGET, script);
    fs.copyFileSync(src, dst);
    fs.chmodSync(dst, 0o755);
  }
  ok(`Hooks copied to ${HOOKS_TARGET}`);
}

function mergeHooksToSettings() {
  const settings = readSettings();
  if (!settings.hooks) settings.hooks = {};

  const hookDefs = [
    { event: 'Stop', script: 'stop.sh' },
    { event: 'PreToolUse', script: 'pre-tool.sh' },
    { event: 'SessionStart', script: 'session-start.sh', matcher: 'startup|clear|compact' },
  ];

  let changed = false;
  for (const { event, script, matcher } of hookDefs) {
    const cmd = path.join(HOOKS_TARGET, script);
    if (!settings.hooks[event]) settings.hooks[event] = [];

    // Idempotency: check if already registered
    const exists = settings.hooks[event].some(group =>
      Array.isArray(group.hooks) &&
      group.hooks.some(h => h.command && h.command.includes('multica') && h.command.includes(script))
    );
    if (exists) continue;

    const hookEntry = { type: 'command', command: cmd };
    const group = matcher ? { matcher, hooks: [hookEntry] } : { hooks: [hookEntry] };
    settings.hooks[event].push(group);
    changed = true;
  }

  if (changed) {
    writeSettings(settings);
    ok(`Hooks registered to: ${SETTINGS_PATH}`);
  } else {
    ok(`Hooks already registered in: ${SETTINGS_PATH}`);
  }
}

function writePluginRoot() {
  if (isDaemonMode()) {
    // REQ-09-04: daemon processes don't read interactive shell profiles
    warn('Daemon mode detected (MULTICA_AGENT_SESSION/MULTICA_WORKDIR set).');
    warn(`Skipping shell profile. Set in the daemon startup environment instead:`);
    warn(`  MULTICA_PLUGIN_ROOT="${PLUGIN_ROOT}"  MULTICA_AGENT_SESSION=1`);
    return;
  }
  const shell = detectShell();
  const profile = getShellProfile(shell);
  // REQ-09-02: fish uses set -gx, not export
  const lines = shell === 'fish'
    ? `\nset -gx MULTICA_PLUGIN_ROOT "${PLUGIN_ROOT}"\nset -gx MULTICA_AGENT_SESSION 0  # disable multica hooks in non-daemon sessions\n`
    : `\nexport MULTICA_PLUGIN_ROOT="${PLUGIN_ROOT}"\nexport MULTICA_AGENT_SESSION=0  # disable multica hooks in non-daemon sessions\n`;

  try {
    const existing = fs.existsSync(profile) ? fs.readFileSync(profile, 'utf8') : '';
    if (existing.includes('MULTICA_PLUGIN_ROOT')) {
      ok(`MULTICA_PLUGIN_ROOT already set in ${profile}`);
      return;
    }
    // REQ-09-02: backup before modifying the user's profile
    if (existing) fs.writeFileSync(profile + '.bak', existing);
    fs.mkdirSync(path.dirname(profile), { recursive: true });
    fs.appendFileSync(profile, lines);
    ok(`MULTICA_PLUGIN_ROOT added to ${profile} (backup: ${profile}.bak)`);
    warn(`Run: source ${profile}  (or open a new terminal)`);
  } catch (e) {
    warn(`Could not write to ${profile}: ${e.message}`);
    warn(`Manually add: export MULTICA_PLUGIN_ROOT="${PLUGIN_ROOT}"`);
  }
}

function checkDeps() {
  console.log(`\n${B}--- Dependencies ---${X}`);
  const deps = [
    { cmd: 'multica', purpose: 'required — all CLI calls', vflag: '--version' },
    { cmd: 'python3', purpose: 'required — staleness detection', vflag: '--version' },
    { cmd: 'git', purpose: 'required — learnings sync', vflag: '--version' },
    { cmd: 'jq', purpose: 'optional — model routing', vflag: '--version' },
  ];
  let allOk = true;
  for (const { cmd, purpose, vflag } of deps) {
    const r = spawnSync(cmd, [vflag], { encoding: 'utf8' });
    if (r.error) {
      warn(`${cmd}: MISSING — ${purpose}`);
      if (cmd !== 'jq') allOk = false;
    } else {
      const ver = (r.stdout || r.stderr || '').split('\n')[0].trim();
      ok(`${cmd}: OK (${ver}) — ${purpose}`);
    }
  }
  return allOk;
}

// REQ-09-01: structured verification — PASS/FAIL per check, remediation steps,
// exit 0 only if every check passes.
function verify() {
  console.log(`\n${B}multica-agent-plugin v${VERSION} — verify${X}\n`);
  const checks = [];
  const add = (name, pass, remedy) => checks.push({ name, pass, remedy });

  // Dependencies + minimum multica version
  const MULTICA_MIN = '0.4.0';
  const mver = getCmdVersion('multica');
  add(`multica CLI present and >= ${MULTICA_MIN}`,
    mver !== null && mver !== '' && cmpVersion(mver, MULTICA_MIN) >= 0,
    'npm install -g @multica/cli');
  add('python3 present', getCmdVersion('python3') !== null,
    'install python3 >= 3.8 via your package manager');
  add('git present', getCmdVersion('git') !== null,
    'install git 2.x via your package manager');

  // Hooks installed and executable
  for (const s of ['stop.sh', 'pre-tool.sh', 'session-start.sh']) {
    const p = path.join(HOOKS_TARGET, s);
    let execOk = false;
    try { fs.accessSync(p, fs.constants.X_OK); execOk = true; } catch (e) { /* missing or not executable */ }
    add(`hook ${s} exists and is executable`, execOk,
      'npx github:yangliang2/multica-agent-plugin');
  }

  // Hook registrations in settings.json
  let settings = {};
  try { settings = readSettings(); } catch (e) { /* readSettings exits on corrupt file */ }
  const hooks = settings.hooks || {};
  for (const event of ['Stop', 'PreToolUse', 'SessionStart']) {
    const groups = hooks[event] || [];
    const registered = groups.some(g =>
      Array.isArray(g.hooks) && g.hooks.some(h => h.command && h.command.includes('multica'))
    );
    add(`${event} hook registered in settings.json`, registered,
      'npx github:yangliang2/multica-agent-plugin');
  }

  // Shell profile (skipped in daemon mode — REQ-09-04)
  if (isDaemonMode()) {
    ok('daemon mode: shell profile check skipped (set MULTICA_PLUGIN_ROOT in daemon env)');
  } else {
    const profile = getShellProfile(detectShell());
    const inProfile = fs.existsSync(profile)
      && fs.readFileSync(profile, 'utf8').includes('MULTICA_PLUGIN_ROOT');
    add(`MULTICA_PLUGIN_ROOT exported in ${profile}`, inProfile,
      `add: export MULTICA_PLUGIN_ROOT="${PLUGIN_ROOT}" (or re-run the installer)`);
  }

  // Install health report (REQ-09-03)
  if (fs.existsSync(HEALTH_PATH)) {
    try {
      const h = JSON.parse(fs.readFileSync(HEALTH_PATH, 'utf8'));
      const failed = (h.steps || []).filter(s => !s.ok).map(s => s.name);
      ok(`last install: ${h.timestamp} (v${h.plugin_version})${failed.length ? ` — failed steps: ${failed.join(', ')}` : ''}`);
    } catch (e) { warn(`install-health.json unreadable: ${e.message}`); }
  }

  console.log('');
  let failures = 0;
  for (const c of checks) {
    if (c.pass) {
      console.log(`${G}PASS${X}  ${c.name}`);
    } else {
      failures++;
      console.log(`${R}FAIL${X}  ${c.name}`);
      console.log(`      remedy: ${c.remedy}`);
    }
  }
  console.log(`\n${failures === 0 ? G + 'All checks passed.' : R + `${failures} check(s) failed.`}${X}\n`);
  process.exitCode = failures === 0 ? 0 : 1;
}

function removeFromShellProfile() {
  const shell = detectShell();
  const profile = getShellProfile(shell);
  if (!fs.existsSync(profile)) return;
  try {
    let content = fs.readFileSync(profile, 'utf8');
    const before = content;
    // Remove the export lines written by writePluginRoot()
    content = content.replace(/\nexport MULTICA_PLUGIN_ROOT="[^"]*"\n?/g, '\n');
    content = content.replace(/\nexport MULTICA_AGENT_SESSION=0[^\n]*\n?/g, '\n');
    // fish variants (set -gx)
    content = content.replace(/\nset -gx MULTICA_PLUGIN_ROOT "[^"]*"\n?/g, '\n');
    content = content.replace(/\nset -gx MULTICA_AGENT_SESSION 0[^\n]*\n?/g, '\n');
    // Collapse runs of blank lines left behind
    content = content.replace(/\n{3,}/g, '\n\n');
    if (content !== before) {
      fs.writeFileSync(profile, content, 'utf8');
      ok(`Removed MULTICA exports from ${profile}`);
    } else {
      ok(`No MULTICA exports found in ${profile}`);
    }
  } catch (e) {
    warn(`Could not clean ${profile}: ${e.message}`);
    warn(`Manually remove MULTICA_PLUGIN_ROOT and MULTICA_AGENT_SESSION lines from ${profile}`);
  }
}

function uninstall() {
  console.log(`\n${B}multica-agent-plugin — uninstall${X}\n`);

  // Remove hooks dir
  if (fs.existsSync(HOOKS_TARGET)) {
    fs.rmSync(HOOKS_TARGET, { recursive: true });
    ok(`Removed ${HOOKS_TARGET}`);
  }

  // Remove from settings.json
  const settings = readSettings();
  if (settings.hooks) {
    for (const event of Object.keys(settings.hooks)) {
      settings.hooks[event] = (settings.hooks[event] || []).filter(group =>
        !(Array.isArray(group.hooks) &&
          group.hooks.some(h => h.command && h.command.includes('multica')))
      );
      if (settings.hooks[event].length === 0) delete settings.hooks[event];
    }
    if (Object.keys(settings.hooks).length === 0) delete settings.hooks;
    writeSettings(settings);
    ok(`Hooks removed from ${SETTINGS_PATH}`);
  }

  // M4: remove export lines written to shell profile
  removeFromShellProfile();
  console.log('');
}

// Main
const args = process.argv.slice(2);
if (args.includes('--verify')) {
  verify();
} else if (args.includes('--uninstall')) {
  uninstall();
} else if (args.includes('--help') || args.includes('-h')) {
  console.log(`multica-agent-plugin v${VERSION}

Usage: npx github:yangliang2/multica-agent-plugin [options]

Options:
  (no args)    Install hooks and configure environment
  --verify     Check installation status
  --uninstall  Remove hooks and clean up
  --help       Show this help

Environment:
  CLAUDE_SETTINGS_PATH  Override settings.json path (default: ~/.claude/settings.json)
`);
} else {
  console.log(`\n${B}multica-agent-plugin v${VERSION} — install${X}\n`);
  // REQ-09-03: record each install step for install-health.json
  const steps = [];
  const step = (name, fn) => {
    try {
      const r = fn();
      steps.push({ name, ok: r !== false, detail: '' });
    } catch (e) {
      steps.push({ name, ok: false, detail: e.message });
      err(`${name} failed: ${e.message}`);
    }
  };

  step('check-dependencies', () => {
    const depsOk = checkDeps();
    if (!depsOk) warn('Some required dependencies are missing. Install them and re-run.');
    return depsOk;
  });
  console.log('');
  step('install-hooks', installHooks);
  step('register-settings', mergeHooksToSettings);
  step('shell-profile', writePluginRoot);
  writeHealth(steps);

  const failedSteps = steps.filter(s => !s.ok);
  if (failedSteps.length) {
    warn(`Completed with ${failedSteps.length} failed step(s): ${failedSteps.map(s => s.name).join(', ')}`);
    warn(`Details in ${HEALTH_PATH}`);
  } else {
    console.log(`\n${G}${B}Installation complete.${X}`);
  }
  if (isDaemonMode()) {
    // REQ-09-04: no interactive Claude Code to restart in daemon deployments
    console.log(`Daemon deployment: ensure MULTICA_PLUGIN_ROOT and MULTICA_AGENT_SESSION=1 are set in the daemon's environment.`);
  } else {
    console.log(`Restart Claude Code (or open a new terminal) to activate the hooks.`);
  }
  console.log(`Run: node bin/install.js --verify  to confirm\n`);
}
