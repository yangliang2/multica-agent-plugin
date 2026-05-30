#!/usr/bin/env node
// claude-autofix.js — read review findings, call Claude to generate patches,
// apply + verify, then commit and push.
'use strict';

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ANTHROPIC_AUTH_TOKEN = process.env.ANTHROPIC_AUTH_TOKEN || process.env.ANTHROPIC_API_KEY || '';
const ANTHROPIC_BASE_URL = process.env.ANTHROPIC_BASE_URL || 'https://api.anthropic.com';

if (!ANTHROPIC_AUTH_TOKEN) {
  console.error('Missing ANTHROPIC_AUTH_TOKEN');
  process.exit(1);
}

function request(opts, body) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(opts.url);
    const useHttps = parsed.protocol === 'https:';
    const transport = useHttps ? https : http;
    const options = {
      hostname: parsed.hostname,
      port: parsed.port || (useHttps ? 443 : 80),
      path: parsed.pathname + (parsed.search || ''),
      method: opts.method || 'GET',
      headers: opts.headers || {},
    };
    if (body) options.headers['Content-Length'] = Buffer.byteLength(body);
    const req = transport.request(options, (res) => {
      let data = '';
      res.on('data', (c) => data += c);
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

function claudeApi(messages, maxTokens = 4096) {
  const base = ANTHROPIC_BASE_URL.replace(/\/$/, '');
  const body = JSON.stringify({
    model: 'claude-sonnet-4-6',
    max_tokens: maxTokens,
    messages,
  });
  return request({
    url: `${base}/v1/messages`,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': ANTHROPIC_AUTH_TOKEN,
      'anthropic-version': '2023-06-01',
    },
  }, body);
}

const readFile = (p) => { try { return fs.readFileSync(p, 'utf8'); } catch { return ''; } };
const REPO_ROOT = process.cwd();
const ALLOWLIST_PREFIXES = ['hooks/', 'tools/', 'bin/', 'tests/', '.github/'];

function randomDelimiter() {
  return `EOF_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
}

function writeMultilineEnv(file, key, value) {
  const delimiter = randomDelimiter();
  fs.appendFileSync(file, `${key}<<${delimiter}\n${String(value)}\n${delimiter}\n`);
}

function resolveAllowedRepoPath(relPath) {
  if (typeof relPath !== 'string' || !relPath.trim()) return null;
  const normalized = relPath.replace(/\\/g, '/');
  if (!ALLOWLIST_PREFIXES.some(p => normalized.startsWith(p))) return null;
  const abs = path.resolve(REPO_ROOT, normalized);
  const rel = path.relative(REPO_ROOT, abs).replace(/\\/g, '/');
  if (rel.startsWith('..') || path.isAbsolute(rel)) return null;
  if (!ALLOWLIST_PREFIXES.some(p => rel.startsWith(p))) return null;
  return { abs, rel };
}

async function main() {
  // 1. Load review findings
  const findings = JSON.parse(readFile('/tmp/review-findings.json') || '{"issues":[]}');
  const issues = (findings.issues || []).filter(i => ['CRITICAL', 'HIGH'].includes(i.severity));

  const env = process.env.GITHUB_ENV || '/tmp/env';
  const writeEnv = (key, value) => writeMultilineEnv(env, key, value);

  if (issues.length === 0) {
    console.log('No CRITICAL/HIGH issues to fix.');
    fs.writeFileSync(env, 'PATCHES_APPLIED=0\n', { flag: 'a' });
    writeEnv('FIX_ANALYSIS', 'no issues to fix');
    writeEnv('MODIFIED_FILES', '');
    process.exit(0);
  }

  // 2. Read affected files
  const affectedFiles = [...new Set(issues.map(i => i.file))];
  const fileContents = {};
  for (const f of affectedFiles) {
    fileContents[f] = readFile(f);
  }

  // 3. Build prompt
  const issueList = issues.map(i =>
    `[${i.severity}] ${i.file}:${i.line} — ${i.title}\n${i.body}`
  ).join('\n\n');

  const fileContext = affectedFiles.map(f =>
    `### ${f}\n\`\`\`\n${fileContents[f].slice(0, 6000)}\n\`\`\``
  ).join('\n\n');

  const prompt = `You are an expert bash developer. Fix the following code review issues.

## Issues to fix
${issueList}

## Affected files
${fileContext}

## Instructions
Produce a JSON response (no markdown, no explanation outside JSON):
{
  "analysis": "one sentence summarizing what was fixed",
  "patches": [
    {
      "file": "hooks/stop.sh",
      "old": "exact string to replace (must match file exactly, include enough context to be unique)",
      "new": "replacement string"
    }
  ]
}

Rules:
- Fix only the reported issues — do not refactor unrelated code
- Each "old" must be a unique string that exists verbatim in the file
- Prefer the smallest possible change that fixes the issue
- If an issue cannot be safely auto-fixed, omit it from patches
- Return ONLY valid JSON`;

  console.log('Calling Claude API for fixes...');
  const res = await claudeApi([{ role: 'user', content: prompt }]);
  if (res.status !== 200) {
    console.error('Claude API error:', res.body);
    process.exit(1);
  }

  let fix;
  try {
    const resp = JSON.parse(res.body);
    const text = resp.content?.[0]?.text || '';
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    fix = JSON.parse(jsonMatch[0]);
  } catch (e) {
    console.error('Failed to parse Claude response:', e.message);
    process.exit(1);
  }

  console.log(`Analysis: ${fix.analysis}`);
  console.log(`Patches: ${fix.patches?.length || 0}`);

  // 4. Apply patches
  let applied = 0;
  const modifiedFiles = [];
  for (const p of (fix.patches || [])) {
    const resolved = resolveAllowedRepoPath(p.file);
    if (!resolved) { console.log(`  SKIP ${p.file}: path not allowed`); continue; }
    const content = readFile(resolved.abs);
    if (!content) { console.log(`  SKIP ${resolved.rel}: not found`); continue; }
    if (!content.includes(p.old)) { console.log(`  SKIP ${resolved.rel}: old string not found`); continue; }
    fs.writeFileSync(resolved.abs, content.replace(p.old, p.new), 'utf8');
    console.log(`  PATCHED ${resolved.rel}`);
    applied++;
    if (!modifiedFiles.includes(resolved.rel)) modifiedFiles.push(resolved.rel);
  }

  if (applied === 0) {
    console.log('No patches applied.');
    fs.appendFileSync(env, `PATCHES_APPLIED=0\n`);
    writeEnv('FIX_ANALYSIS', fix.analysis || 'no patches applied');
    writeEnv('MODIFIED_FILES', '');
    process.exit(0);
  }

  // 5. Verify
  try {
    execSync('bash -n hooks/stop.sh hooks/session-start.sh hooks/pre-tool.sh', { stdio: 'inherit' });
    execSync('shellcheck -S warning hooks/*.sh tools/*.sh uninstall.sh', { stdio: 'inherit' });
    execSync('npm test', { stdio: 'inherit' });
    console.log('Verification passed.');
  } catch (e) {
    console.error('Verification failed — reverting patches');
    execSync('git checkout -- .', { stdio: 'inherit' });
    fs.appendFileSync(env, `PATCHES_APPLIED=0\n`);
    writeEnv('FIX_ANALYSIS', 'verification failed after patch');
    writeEnv('MODIFIED_FILES', '');
    process.exit(1);
  }

  // 6. Write env for commit step
  fs.appendFileSync(env, `PATCHES_APPLIED=${applied}\n`);
  writeEnv('FIX_ANALYSIS', fix.analysis || 'auto-fix');
  writeEnv('MODIFIED_FILES', modifiedFiles.join('\n'));
  process.exit(0);
}

main().catch((e) => { console.error(e); process.exit(1); });
