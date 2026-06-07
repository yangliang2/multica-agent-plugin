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
  const shell = detectShell();
  const profile = getShellProfile(shell);
  const exportLine = `\nexport MULTICA_PLUGIN_ROOT="${PLUGIN_ROOT}"`;
  const agentLine = `\nexport MULTICA_AGENT_SESSION=0  # disable multica hooks in non-daemon sessions`;

  try {
    const existing = fs.existsSync(profile) ? fs.readFileSync(profile, 'utf8') : '';
    if (existing.includes('MULTICA_PLUGIN_ROOT')) {
      ok(`MULTICA_PLUGIN_ROOT already set in ${profile}`);
      return;
    }
    fs.appendFileSync(profile, exportLine + agentLine + '\n');
    ok(`MULTICA_PLUGIN_ROOT added to ${profile}`);
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

function verify() {
  console.log(`\n${B}multica-agent-plugin v${VERSION} — verify${X}\n`);
  checkDeps();

  console.log(`\n${B}--- Hooks ---${X}`);
  const scripts = ['stop.sh', 'pre-tool.sh', 'session-start.sh'];
  for (const s of scripts) {
    const p = path.join(HOOKS_TARGET, s);
    fs.existsSync(p) ? ok(`${s}: found at ${p}`) : warn(`${s}: NOT found at ${p} — run install`);
  }

  console.log(`\n${B}--- Settings ---${X}`);
  const settings = readSettings();
  const hooks = settings.hooks || {};
  for (const event of ['Stop', 'PreToolUse', 'SessionStart']) {
    const groups = hooks[event] || [];
    const registered = groups.some(g =>
      Array.isArray(g.hooks) && g.hooks.some(h => h.command && h.command.includes('multica'))
    );
    registered ? ok(`${event}: registered`) : warn(`${event}: NOT registered — run install`);
  }
  console.log('');
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
  const depsOk = checkDeps();
  if (!depsOk) {
    warn('Some required dependencies are missing. Install them and re-run.');
  }
  console.log('');
  installHooks();
  mergeHooksToSettings();
  writePluginRoot();
  console.log(`\n${G}${B}Installation complete.${X}`);
  console.log(`Run: node bin/install.js --verify  to confirm\n`);
}
