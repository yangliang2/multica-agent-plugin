#!/usr/bin/env node
// claude-review.js — call Claude API to review a PR diff, post inline comments,
// and create a Check Run. Exits with code 1 if CRITICAL/HIGH issues found.
'use strict';

const https = require('https');
const http = require('http');
const fs = require('fs');

const ANTHROPIC_AUTH_TOKEN = process.env.ANTHROPIC_AUTH_TOKEN || process.env.ANTHROPIC_API_KEY || '';
const ANTHROPIC_BASE_URL = process.env.ANTHROPIC_BASE_URL || 'https://api.anthropic.com';
const GITHUB_TOKEN = process.env.GITHUB_TOKEN || '';
const GITHUB_REPO = process.env.GITHUB_REPOSITORY || '';
const PR_NUMBER = process.env.PR_NUMBER || '';
const HEAD_SHA = process.env.HEAD_SHA || '';
const AUTO_FIX_COUNT = parseInt(process.env.AUTO_FIX_COUNT || '0', 10);
const MAX_AUTO_FIX = 3;

if (!ANTHROPIC_AUTH_TOKEN || !GITHUB_TOKEN || !GITHUB_REPO || !PR_NUMBER || !HEAD_SHA) {
  console.error('Missing required env vars');
  process.exit(1);
}

// ── HTTP helpers ──────────────────────────────────────────────────────────────

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

function ghApi(path, method = 'GET', body = null) {
  const opts = {
    url: `https://api.github.com/repos/${GITHUB_REPO}${path}`,
    method,
    headers: {
      'Authorization': `Bearer ${GITHUB_TOKEN}`,
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'multica-code-review',
      'Content-Type': 'application/json',
    },
  };
  return request(opts, body ? JSON.stringify(body) : null);
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

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  // 1. Create a pending Check Run
  const checkRes = await ghApi('/check-runs', 'POST', {
    name: 'Claude Code Review',
    head_sha: HEAD_SHA,
    status: 'in_progress',
    started_at: new Date().toISOString(),
    output: { title: 'Reviewing…', summary: 'Claude is analyzing the diff.' },
  });
  const checkData = JSON.parse(checkRes.body);
  const checkRunId = checkData.id;
  if (!checkRunId) {
    console.error('Failed to create check run:', checkRes.body);
    process.exit(1);
  }
  console.log(`Check run created: ${checkRunId}`);

  // 2. Fetch PR diff
  const diffRes = await request({
    url: `https://api.github.com/repos/${GITHUB_REPO}/pulls/${PR_NUMBER}`,
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${GITHUB_TOKEN}`,
      'Accept': 'application/vnd.github.v3.diff',
      'User-Agent': 'multica-code-review',
    },
  });
  const diff = diffRes.body.slice(0, 24000); // cap to avoid token overflow

  // 3. Fetch PR file list for position mapping
  const filesRes = await ghApi(`/pulls/${PR_NUMBER}/files`);
  const files = JSON.parse(filesRes.body);

  // 4. Call Claude
  const prompt = `You are an expert code reviewer. Review the following pull request diff and identify issues.

## Diff
\`\`\`diff
${diff}
\`\`\`

## Instructions
Respond with a JSON object (no markdown, no explanation outside JSON):
{
  "summary": "2-3 sentence overall assessment",
  "severity": "CRITICAL|HIGH|MEDIUM|LOW",  // highest severity found
  "issues": [
    {
      "severity": "CRITICAL|HIGH|MEDIUM|LOW",
      "file": "path/to/file.sh",
      "line": 42,          // line number in the NEW file (right side of diff)
      "title": "short title",
      "body": "explanation and suggested fix"
    }
  ]
}

Severity definitions:
- CRITICAL: security vulnerability, data loss, broken functionality
- HIGH: significant bug, dangerous pattern, will likely cause production issues
- MEDIUM: code quality issue, logic flaw, missing error handling
- LOW: style, naming, minor improvement

Only report genuine issues. If the code is clean, return an empty issues array with severity "LOW".
Focus on: shell injection, path traversal, missing validation, logic errors, broken error handling.
Limit to the 10 most important issues.`;

  console.log('Calling Claude API...');
  const claudeRes = await claudeApi([{ role: 'user', content: prompt }]);
  if (claudeRes.status !== 200) {
    console.error('Claude API error:', claudeRes.body);
    await completeCheck(checkRunId, 'failure', 'Claude API error', 'Failed to reach Claude API.');
    process.exit(1);
  }

  let review;
  try {
    const resp = JSON.parse(claudeRes.body);
    const text = resp.content?.[0]?.text || '';
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    review = JSON.parse(jsonMatch[0]);
  } catch (e) {
    console.error('Failed to parse Claude response:', e.message);
    await completeCheck(checkRunId, 'failure', 'Parse error', 'Could not parse Claude review output.');
    process.exit(1);
  }

  console.log(`Review complete. Severity: ${review.severity}. Issues: ${review.issues?.length || 0}`);

  // 5. Build position map: file → (new_line → diff_position)
  const posMap = buildPositionMap(files);

  // 6. Post inline PR review comments
  const reviewComments = [];
  for (const issue of (review.issues || [])) {
    const pos = posMap[issue.file]?.[issue.line];
    if (pos !== undefined) {
      reviewComments.push({
        path: issue.file,
        position: pos,
        body: `**[${issue.severity}] ${issue.title}**\n\n${issue.body}`,
      });
    }
  }

  // Determine review event
  const hasCriticalOrHigh = ['CRITICAL', 'HIGH'].includes(review.severity) &&
    (review.issues || []).some(i => ['CRITICAL', 'HIGH'].includes(i.severity));
  const reviewEvent = hasCriticalOrHigh ? 'REQUEST_CHANGES' : 'COMMENT';

  const autoFixNote = hasCriticalOrHigh && AUTO_FIX_COUNT < MAX_AUTO_FIX
    ? `\n\n🤖 Auto-fix will be attempted (attempt ${AUTO_FIX_COUNT + 1}/${MAX_AUTO_FIX}).`
    : hasCriticalOrHigh && AUTO_FIX_COUNT >= MAX_AUTO_FIX
    ? `\n\n⚠️ Auto-fix limit (${MAX_AUTO_FIX}) reached. Manual intervention required.`
    : '';

  const reviewBody = `## Claude Code Review\n\n${review.summary}${autoFixNote}`;

  await ghApi(`/pulls/${PR_NUMBER}/reviews`, 'POST', {
    commit_id: HEAD_SHA,
    body: reviewBody,
    event: reviewEvent,
    comments: reviewComments,
  });
  console.log(`Posted review (${reviewEvent}) with ${reviewComments.length} inline comment(s)`);

  // 7. Complete Check Run
  const conclusion = hasCriticalOrHigh ? 'failure' : 'success';
  const issueLines = (review.issues || [])
    .map(i => `- **[${i.severity}]** \`${i.file}:${i.line}\` — ${i.title}`)
    .join('\n');
  await completeCheck(
    checkRunId,
    conclusion,
    `Code Review: ${review.severity} — ${review.issues?.length || 0} issue(s)`,
    `${review.summary}\n\n${issueLines || '_No issues found._'}`,
  );

  // 8. Write findings to file for auto-fix job to consume
  fs.writeFileSync('/tmp/review-findings.json', JSON.stringify(review, null, 2));

  console.log(`Check run completed: ${conclusion}`);
  process.exit(hasCriticalOrHigh ? 1 : 0);
}

function buildPositionMap(files) {
  const map = {};
  for (const file of files) {
    map[file.filename] = {};
    const patch = file.patch || '';
    let position = 0;
    let newLine = 0;
    for (const line of patch.split('\n')) {
      position++;
      if (line.startsWith('@@')) {
        const m = line.match(/@@ -\d+(?:,\d+)? \+(\d+)/);
        if (m) newLine = parseInt(m[1], 10) - 1;
      } else if (line.startsWith('-')) {
        // deleted line — no new line number
      } else {
        newLine++;
        map[file.filename][newLine] = position;
      }
    }
  }
  return map;
}

async function completeCheck(checkRunId, conclusion, title, summary) {
  await ghApi(`/check-runs/${checkRunId}`, 'PATCH', {
    status: 'completed',
    completed_at: new Date().toISOString(),
    conclusion,
    output: { title, summary },
  });
}

main().catch((e) => { console.error(e); process.exit(1); });
