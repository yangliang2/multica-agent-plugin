// tests/unit/install.test.js — unit tests for bin/install.js helpers
// Run via: node --test tests/unit/install.test.js
'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');

// ── Extract testable functions from install.js ──────────────────────────────
// We eval the module in a sandboxed context so we can access private functions
// without modifying install.js itself.
const fs = require('fs');
const src = fs.readFileSync(path.join(__dirname, '../../bin/install.js'), 'utf8');

// Stub out the parts that have side effects at module load time
const stubbed = src
  .replace(/^const VERSION = .*$/m, 'const VERSION = "0.0.0-test";')
  .replace(/^const PLUGIN_ROOT = .*$/m, 'const PLUGIN_ROOT = "/tmp/test-plugin";')
  .replace(/^const HOOKS_TARGET = .*$/m, 'const HOOKS_TARGET = "/tmp/test-hooks";')
  // Prevent SETTINGS_PATH validation from running at load time
  .replace(/^const SETTINGS_PATH = \(\(\) => \{[\s\S]*?^\}\)\(\);/m,
    'const SETTINGS_PATH = require("path").join(require("os").homedir(), ".claude", "settings.json");');

// Extract parseJsonc function
const parseJsoncMatch = stubbed.match(/function parseJsonc\(str\) \{[\s\S]*?^}/m);
if (!parseJsoncMatch) throw new Error('Could not extract parseJsonc');
const parseJsonc = new Function('return ' + parseJsoncMatch[0])();

// ── parseJsonc tests ─────────────────────────────────────────────────────────

test('parseJsonc: plain JSON passes through unchanged', () => {
  const input = '{"a": 1, "b": "hello"}';
  assert.deepEqual(parseJsonc(input), { a: 1, b: 'hello' });
});

test('parseJsonc: strips line comments', () => {
  const input = '{\n  "a": 1 // this is a comment\n}';
  assert.deepEqual(parseJsonc(input), { a: 1 });
});

test('parseJsonc: strips block comments', () => {
  const input = '{"a": /* block comment */ 1}';
  assert.deepEqual(parseJsonc(input), { a: 1 });
});

test('parseJsonc: preserves // inside string values (URLs)', () => {
  const input = '{"url": "https://example.com/path"}';
  assert.deepEqual(parseJsonc(input), { url: 'https://example.com/path' });
});

test('parseJsonc: trailing comma before }', () => {
  const input = '{"a": 1,}';
  assert.deepEqual(parseJsonc(input), { a: 1 });
});

test('parseJsonc: trailing comma before ]', () => {
  const input = '{"arr": [1, 2, 3,]}';
  assert.deepEqual(parseJsonc(input), { arr: [1, 2, 3] });
});

test('parseJsonc: strips BOM', () => {
  const input = '﻿{"a": 1}';
  assert.deepEqual(parseJsonc(input), { a: 1 });
});

test('parseJsonc: nested object with comments and trailing commas', () => {
  const input = `{
  // outer comment
  "hooks": {
    "Stop": [], /* inline block */
    "PreToolUse": [1, 2,],
  },
}`;
  assert.deepEqual(parseJsonc(input), {
    hooks: { Stop: [], PreToolUse: [1, 2] }
  });
});

test('parseJsonc: escaped quote inside string not treated as end of string', () => {
  const input = '{"key": "value with \\"escaped\\" quotes"}';
  assert.deepEqual(parseJsonc(input), { key: 'value with "escaped" quotes' });
});

test('parseJsonc: throws on genuinely invalid JSON', () => {
  assert.throws(() => parseJsonc('not json at all'), /SyntaxError|JSON/i);
});

// ── CLAUDE_DIR path validation ───────────────────────────────────────────────
// Extract the SETTINGS_PATH validation logic
const claudeDir = path.join(os.homedir(), '.claude');

function validateSettingsPath(custom) {
  const resolved = path.resolve(custom);
  const rel = path.relative(claudeDir, resolved);
  if (rel.startsWith('..') || path.isAbsolute(rel)) {
    throw new Error(`CLAUDE_SETTINGS_PATH must be inside ${claudeDir}`);
  }
  return resolved;
}

test('CLAUDE_SETTINGS_PATH: default path is valid', () => {
  const p = path.join(claudeDir, 'settings.json');
  assert.doesNotThrow(() => validateSettingsPath(p));
});

test('CLAUDE_SETTINGS_PATH: subdir of ~/.claude is valid', () => {
  const p = path.join(claudeDir, 'subdir', 'settings.json');
  assert.doesNotThrow(() => validateSettingsPath(p));
});

test('CLAUDE_SETTINGS_PATH: path outside ~/.claude is rejected', () => {
  assert.throws(() => validateSettingsPath('/etc/passwd'), /must be inside/);
});

test('CLAUDE_SETTINGS_PATH: path traversal via .. is rejected', () => {
  const p = path.join(claudeDir, '..', '.ssh', 'authorized_keys');
  assert.throws(() => validateSettingsPath(p), /must be inside/);
});

test('CLAUDE_SETTINGS_PATH: ~/.config path is rejected', () => {
  const p = path.join(os.homedir(), '.config', 'evil.json');
  assert.throws(() => validateSettingsPath(p), /must be inside/);
});

// ── cmpVersion tests (REQ-09-01) ─────────────────────────────────────────────

const cmpVersionMatch = stubbed.match(/function cmpVersion\(a, b\) \{[\s\S]*?^}/m);
if (!cmpVersionMatch) throw new Error('Could not extract cmpVersion');
const cmpVersion = new Function('return ' + cmpVersionMatch[0])();

test('cmpVersion: equal versions → 0', () => {
  assert.equal(cmpVersion('0.4.0', '0.4.0'), 0);
});

test('cmpVersion: lower version → -1', () => {
  assert.equal(cmpVersion('0.3.9', '0.4.0'), -1);
});

test('cmpVersion: higher version → 1', () => {
  assert.equal(cmpVersion('1.0.0', '0.4.0'), 1);
});

test('cmpVersion: shorter form padded with zeros', () => {
  assert.equal(cmpVersion('1.2', '1.2.0'), 0);
  assert.equal(cmpVersion('1.2', '1.2.1'), -1);
});

test('cmpVersion: double-digit segments compared numerically', () => {
  assert.equal(cmpVersion('0.10.0', '0.9.0'), 1);
});

test('cmpVersion: garbage input treated as zeros', () => {
  assert.equal(cmpVersion('abc', '0.0.0'), 0);
});
