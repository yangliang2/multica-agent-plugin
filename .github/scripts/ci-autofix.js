#!/usr/bin/env node
// ci-autofix.js — analyze failed CI logs, ask Claude for a patch, apply it,
// verify locally, and export workflow outputs via GITHUB_ENV.
'use strict';

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');

const failedLog = process.env.FAILED_LOG || '';
const localShellcheck = process.env.LOCAL_SHELLCHECK || '';
const apiKey = process.env.ANTHROPIC_AUTH_TOKEN || process.env.ANTHROPIC_API_KEY || '';
const baseUrl = process.env.ANTHROPIC_BASE_URL || 'https://api.anthropic.com';
const envFile = process.env.GITHUB_ENV || '/tmp/env';
const REPO_ROOT = process.cwd();
const ALLOWLIST_PREFIXES = ['hooks/', 'tools/', 'bin/', 'tests/', '.github/'];

function randomDelimiter() {
  return `EOF_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
}

function writeEnv(key, value) {
  const delimiter = randomDelimiter();
  fs.appendFileSync(envFile, `${key}<<${delimiter}\n${String(value)}\n${delimiter}\n`);
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
  if (!apiKey) throw new Error('Missing ANTHROPIC_AUTH_TOKEN / ANTHROPIC_API_KEY');

  const readFile = (p) => { try { return fs.readFileSync(p, 'utf8'); } catch { return ''; } };
  const stopSh = readFile('hooks/stop.sh');
  const sessionStartSh = readFile('hooks/session-start.sh');
  const preToolSh = readFile('hooks/pre-tool.sh');

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

  let fix = { analysis: 'parse error', patches: [] };
  if (res.status === 200) {
    try {
      const payload = JSON.parse(res.body);
      const text = payload.content?.[0]?.text || '';
      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (jsonMatch) fix = JSON.parse(jsonMatch[0]);
    } catch {
      // keep default
    }
  }

  let applied = 0;
  const modifiedFiles = [];
  for (const p of (fix.patches || [])) {
    try {
      const resolved = resolveAllowedRepoPath(p.file);
      if (!resolved) continue;
      const content = fs.readFileSync(resolved.abs, 'utf8');
      if (!content.includes(p.old)) continue;
      fs.writeFileSync(resolved.abs, content.replace(p.old, p.new), 'utf8');
      applied += 1;
      if (!modifiedFiles.includes(resolved.rel)) modifiedFiles.push(resolved.rel);
    } catch {
      // ignore file-level failures
    }
  }

  fs.appendFileSync(envFile, `PATCHES_APPLIED=${applied}\n`);
  writeEnv('FIX_ANALYSIS', fix.analysis || 'auto-fix');
  writeEnv('MODIFIED_FILES', modifiedFiles.join('\n'));
}

main().catch((e) => {
  fs.appendFileSync(envFile, 'PATCHES_APPLIED=0\n');
  writeEnv('FIX_ANALYSIS', `ci-autofix failed: ${e.message}`);
  writeEnv('MODIFIED_FILES', '');
  process.exit(0);
});
