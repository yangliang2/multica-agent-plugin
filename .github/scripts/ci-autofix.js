#!/usr/bin/env node
// ci-autofix.js — analyze failed CI logs, ask Claude for a patch, apply it,
// verify locally, and export workflow outputs via GITHUB_ENV.
'use strict';

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const readOptionalFile = (p) => {
  if (!p) return '';
  try { return fs.readFileSync(p, 'utf8'); } catch { return ''; }
};
const failedLog = process.env.FAILED_LOG || readOptionalFile(process.env.FAILED_LOG_FILE);
const localShellcheck = process.env.LOCAL_SHELLCHECK || readOptionalFile(process.env.LOCAL_SHELLCHECK_FILE);
const apiKey = process.env.ANTHROPIC_AUTH_TOKEN || process.env.ANTHROPIC_API_KEY || '';
const baseUrl = process.env.ANTHROPIC_BASE_URL || 'https://api.anthropic.com';
const envFile = process.env.GITHUB_ENV || '/tmp/env';
const REPO_ROOT = process.cwd();
const REPO_ROOT_REAL = fs.realpathSync(REPO_ROOT);
const ALLOWLIST_PREFIXES = ['hooks/', 'tools/', 'bin/', 'tests/'];

function randomDelimiter() {
  return `EOF_${crypto.randomBytes(8).toString('hex')}`;
}

function writeEnv(key, value) {
  const delimiter = randomDelimiter();
  fs.appendFileSync(envFile, `${key}<<${delimiter}\n${String(value)}\n${delimiter}\n`);
}

function isAllowedRelPath(rel) {
  return !rel.startsWith('..') && !path.isAbsolute(rel) &&
    ALLOWLIST_PREFIXES.some(prefix => rel.startsWith(prefix));
}

function resolveAllowedRepoPath(relPath) {
  if (typeof relPath !== 'string' || !relPath.trim()) return null;
  const normalized = relPath.replace(/\\/g, '/');
  if (!isAllowedRelPath(normalized)) return null;

  const abs = path.resolve(REPO_ROOT, normalized);
  const rel = path.relative(REPO_ROOT, abs).replace(/\\/g, '/');
  if (!isAllowedRelPath(rel)) return null;

  try {
    const stat = fs.lstatSync(abs);
    if (stat.isSymbolicLink() || !stat.isFile()) return null;

    const real = fs.realpathSync(abs);
    const realStat = fs.statSync(real);
    if (!realStat.isFile()) return null;
    const realRel = path.relative(REPO_ROOT_REAL, real).replace(/\\/g, '/');
    if (!isAllowedRelPath(realRel)) return null;
    if (realRel !== rel) return null;
  } catch {
    return null;
  }

  return { abs, rel };
}

async function main() {
  if (!apiKey) throw new Error('Missing ANTHROPIC_AUTH_TOKEN / ANTHROPIC_API_KEY');

  const readAllowedFile = (p) => {
    const resolved = resolveAllowedRepoPath(p);
    if (!resolved) return '';
    const stat = fs.statSync(resolved.abs);
    if (!stat.isFile()) return '';
    return fs.readFileSync(resolved.abs, 'utf8');
  };
  const stopSh = readAllowedFile('hooks/stop.sh');
  const sessionStartSh = readAllowedFile('hooks/session-start.sh');
  const preToolSh = readAllowedFile('hooks/pre-tool.sh');

  const prompt = `You are an expert bash developer. A CI pipeline has failed. Analyze the failure and produce ONLY the minimal fix.

## CI failure log (last 200 lines)
${failedLog}

## Local shellcheck output
${localShellcheck}

## hooks/stop.sh (current)
${stopSh.slice(0, 8000)}

## hooks/session-start.sh (current)
${sessionStartSh.slice(0, 8000)}

## hooks/pre-tool.sh (current)
${preToolSh.slice(0, 3000)}

## Instructions
Produce a JSON response with this exact structure:
{
  "analysis": "one sentence explaining root cause",
  "patches": [
    {
      "file": "hooks/stop.sh",
      "old": "exact string to replace (must match file exactly)",
      "new": "replacement string"
    }
  ]
}

Rules:
- Only fix what the CI log specifically reports as an error or warning
- Each patch "old" must be a unique string that exists verbatim in the file
- Prefer the smallest possible change
- If nothing can be fixed automatically, return {"analysis": "...", "patches": []}
- Return ONLY valid JSON, no markdown, no explanation outside JSON`;

  const parsedBase = new URL(baseUrl);
  const useHttps = parsedBase.protocol === 'https:';
  const transport = useHttps ? https : http;
  const hostname = parsedBase.hostname;
  const port = parsedBase.port || (useHttps ? 443 : 80);
  const pathPrefix = parsedBase.pathname.replace(/\/$/, '');

  const body = JSON.stringify({
    model: 'claude-haiku-4-5-20251001',
    max_tokens: 2048,
    messages: [{ role: 'user', content: prompt }]
  });

  const res = await new Promise((resolve, reject) => {
    const req = transport.request({
      hostname,
      port,
      path: pathPrefix + '/v1/messages',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Length': Buffer.byteLength(body),
      },
    }, (resp) => {
      let data = '';
      resp.on('data', (c) => data += c);
      resp.on('end', () => resolve({ status: resp.statusCode, body: data }));
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });

  if (res.status !== 200) {
    throw new Error(`Claude API error: HTTP ${res.status}`);
  }

  let fix;
  try {
    const payload = JSON.parse(res.body);
    const text = payload.content?.[0]?.text || '';
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (!jsonMatch) throw new Error('missing JSON object');
    fix = JSON.parse(jsonMatch[0]);
  } catch (e) {
    throw new Error(`Failed to parse Claude response: ${e.message}`);
  }

  let applied = 0;
  const failures = [];
  const modifiedFiles = [];
  const originalContents = new Map();
  for (const p of (fix.patches || [])) {
    try {
      const resolved = resolveAllowedRepoPath(p.file);
      if (!resolved) {
        failures.push(`${p.file || '<missing>'}: path not allowed`);
        continue;
      }
      const content = fs.readFileSync(resolved.abs, 'utf8');
      if (!content.includes(p.old)) {
        failures.push(`${resolved.rel}: old string not found`);
        continue;
      }
      if (!originalContents.has(resolved.abs)) originalContents.set(resolved.abs, content);
      fs.writeFileSync(resolved.abs, content.replace(p.old, p.new), 'utf8');
      applied += 1;
      if (!modifiedFiles.includes(resolved.rel)) modifiedFiles.push(resolved.rel);
    } catch (e) {
      failures.push(`${p.file || '<missing>'}: ${e.message}`);
    }
  }

  if (failures.length > 0) {
    for (const [abs, content] of originalContents) {
      fs.writeFileSync(abs, content, 'utf8');
    }
    writeEnv('FIX_ANALYSIS', `auto-fix failed: ${failures.join('; ')}`);
    writeEnv('MODIFIED_FILES', '');
    fs.appendFileSync(envFile, `PATCHES_APPLIED=0\n`);
    throw new Error(`Failed to apply ${failures.length} patch(es)`);
  }

  fs.appendFileSync(envFile, `PATCHES_APPLIED=${applied}\n`);
  writeEnv('FIX_ANALYSIS', fix.analysis || 'auto-fix');
  writeEnv('MODIFIED_FILES', modifiedFiles.join('\n'));
}

main().catch((e) => {
  fs.appendFileSync(envFile, 'PATCHES_APPLIED=0\n');
  writeEnv('FIX_ANALYSIS', `ci-autofix failed: ${e.message}`);
  writeEnv('MODIFIED_FILES', '');
  console.error(e.message);
  process.exit(1);
});
