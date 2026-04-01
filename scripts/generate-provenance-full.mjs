#!/usr/bin/env node
// generate-provenance-full.mjs — Generate provenance files with narrative content from JSONL sessions.
//
// Usage:
//   node scripts/generate-provenance-full.mjs [--dry-run] [--force] [--skip-existing]
//
// Reads each JSONL session, extracts metadata AND full conversation content,
// then writes rich provenance files with populated narrative sections.

import { readFileSync, readdirSync, writeFileSync, existsSync } from "node:fs";
import { execSync } from "node:child_process";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SESSIONS_DIR =
  "/mnt/host-workspaceStorage/4ed0a39d625c44bbf673adf18e1f0b87/chatSessions";
const PROVENANCE_DIR = resolve(__dirname, "../provenance/");
const METADATA_SCRIPT = resolve(__dirname, "extract-session-metadata.mjs");
const CONVO_SCRIPT = resolve(__dirname, "extract-session-conversation.mjs");
const LOG_PATH = resolve(PROVENANCE_DIR, "generation-full.log");

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const force = args.includes("--force");
const skipExisting = !force;

// Find existing provenance files and their session IDs
const existingSessionIds = new Set();
if (existsSync(PROVENANCE_DIR)) {
  for (const f of readdirSync(PROVENANCE_DIR)) {
    if (!f.endsWith(".md")) continue;
    const content = readFileSync(resolve(PROVENANCE_DIR, f), "utf8");
    const m = content.match(/chatSessions\/([a-f0-9-]+)\.jsonl/);
    if (m) existingSessionIds.add(m[1]);
  }
}

const files = readdirSync(SESSIONS_DIR)
  .filter((f) => f.endsWith(".jsonl"))
  .sort();

let log = `# Provenance Full Generation Log\n# Run: ${new Date().toISOString()}\n# Mode: ${dryRun ? "dry-run" : "live"}, ${force ? "force" : "skip-existing"}\n\n`;
let created = 0, skipped = 0, failed = 0;

for (const file of files) {
  const sessionId = file.replace(".jsonl", "");
  const filePath = SESSIONS_DIR + "/" + file;

  if (skipExisting && existingSessionIds.has(sessionId)) {
    log += `SKIP | ${sessionId.substring(0, 8)} | already has provenance file\n`;
    skipped++;
    process.stdout.write(`SKIP ${sessionId.substring(0, 8)} (exists)\n`);
    continue;
  }

  // Extract metadata
  let meta;
  try {
    const result = execSync(`node "${METADATA_SCRIPT}" "${filePath}" --json`, {
      encoding: "utf8",
      timeout: 30000,
    });
    meta = JSON.parse(result);
  } catch (err) {
    const msg = err.stderr ? err.stderr.trim() : err.message;
    log += `FAIL | ${sessionId.substring(0, 8)} | metadata: ${msg.substring(0, 150)}\n`;
    failed++;
    process.stdout.write(`FAIL ${sessionId.substring(0, 8)} | metadata error\n`);
    continue;
  }

  // Extract conversation
  let turns;
  try {
    const result = execSync(`node "${CONVO_SCRIPT}" "${filePath}"`, {
      encoding: "utf8",
      timeout: 60000,
      maxBuffer: 50 * 1024 * 1024, // 50MB
    });
    turns = JSON.parse(result);
  } catch (err) {
    const msg = err.stderr ? err.stderr.trim() : err.message;
    log += `FAIL | ${sessionId.substring(0, 8)} | conversation: ${msg.substring(0, 150)}\n`;
    failed++;
    process.stdout.write(`FAIL ${sessionId.substring(0, 8)} | conversation error\n`);
    continue;
  }

  // Derive a title if Copilot didn't auto-generate one
  if (meta.title === "(untitled)") {
    meta.derivedTitle = deriveTitle(turns);
  }

  // Synthesize provenance
  const md = synthesizeProvenance(meta, turns);

  // Filename
  const dateStr = meta.created.slice(0, 10);
  const displayTitle = meta.derivedTitle || meta.title;
  const slug = makeSlug(displayTitle, sessionId);
  let outName = `${dateStr}-${slug}.md`;
  if (existsSync(resolve(PROVENANCE_DIR, outName)) && !force) {
    outName = `${dateStr}-${slug}-${sessionId.substring(0, 8)}.md`;
  }

  if (dryRun) {
    log += `WOULD | ${outName} | ${turns.length} turns, ${meta.title.substring(0, 50)}\n`;
    process.stdout.write(`WOULD ${outName} (${turns.length} turns)\n`);
  } else {
    writeFileSync(resolve(PROVENANCE_DIR, outName), md);
    log += `OK    | ${outName} | ${turns.length} turns, ${meta.title.substring(0, 50)}\n`;
    process.stdout.write(`OK    ${outName} (${turns.length} turns)\n`);
  }
  created++;
}

log += `\n# Summary: ${created} ${dryRun ? "would create" : "created"}, ${skipped} skipped, ${failed} failed out of ${files.length}\n`;
writeFileSync(LOG_PATH, log);
process.stdout.write(`\nDone: ${created} ${dryRun ? "would create" : "created"}, ${skipped} skipped, ${failed} failed\n`);
process.stdout.write(`Log: ${LOG_PATH}\n`);

// ─── Synthesis ──────────────────────────────────────────────────

function deriveTitle(turns) {
  // Try to derive a meaningful title from conversation content
  for (const t of turns) {
    if (!t.user || t.user.length < 5) continue;
    let msg = t.user.trim();
    // Skip generic messages
    if (/^(yes|no|ok|continue|resume|go|do it|\/)$/i.test(msg)) continue;
    // Skip very long messages (likely context dumps)
    if (msg.length > 200) msg = msg.substring(0, 200);
    // Clean up and capitalize
    msg = msg.replace(/\s+/g, " ").trim();
    // Take first sentence or phrase
    const firstSentence = msg.match(/^[^.!?\n]+/)?.[0] || msg;
    if (firstSentence.length >= 8) {
      return firstSentence.substring(0, 80).trim();
    }
  }
  // Fallback: use first agent response summary
  for (const t of turns) {
    if (!t.agent || t.agent.length < 50) continue;
    const firstLine = t.agent.split("\n").find((l) => l.trim().length > 15);
    if (firstLine) {
      return firstLine.replace(/^#+\s*/, "").replace(/\*\*/g, "").substring(0, 80).trim();
    }
  }
  return null;
}

function synthesizeProvenance(meta, turns) {
  const dateStr = meta.created.slice(0, 10);
  const createdFmt = `${dateStr} ${meta.created.slice(11, 16)} UTC`;
  const displayTitle = meta.derivedTitle || (meta.title !== "(untitled)" ? meta.title : "Untitled Session");
  const tokensFmt = `${fmtTokens(meta.promptTokens)} prompt + ${fmtTokens(meta.outputTokens)} output (${fmtTokens(meta.totalTokens)} total)`;

  const isMinimal = meta.toolCalls === 0 && meta.totalTokens === 0 && turns.length <= 2;

  // ── Summary ──
  const summary = buildSummary(turns, meta);

  // ── Work Done ──
  const workDone = buildWorkDone(turns);

  // ── Decisions ──
  const decisions = buildDecisions(turns);

  // ── Problems ──
  const problems = buildProblems(turns);

  // ── Key Files ──
  const keyFiles = buildKeyFiles(turns);

  // ── Follow-up ──
  const followUp = buildFollowUp(turns);

  let md = `# Session: ${displayTitle}

**Date:** ${dateStr}  
**Source:** \`chatSessions/${meta.sessionId}.jsonl\`

## Metadata

| Field | Value |
|-------|-------|
| Session ID | \`${meta.sessionId}\` |
| Created | ${createdFmt} |
| Title | ${meta.title}${meta.derivedTitle ? " (derived: " + meta.derivedTitle + ")" : ""} |
| Duration | ~${meta.duration} |
| Models | ${meta.models.map((m) => "`" + m + "`").join(", ") || "unknown"} |
| Total tokens | ${tokensFmt} |
| Tool calls | ${meta.toolCalls} |
| MCP servers | ${meta.mcpServers.join(", ") || "none"} |
| Content refs | ${meta.contentRefs.slice(0, 5).join(", ") || "none"} |

`;

  if (isMinimal) {
    md += `## Summary\n\nMinimal session — no significant tool usage or output recorded.\n`;
    if (turns.length > 0 && turns[0].user) {
      md += `\n**First message:** "${turns[0].user.substring(0, 200)}"\n`;
    }
    return md;
  }

  md += `## Summary\n\n${summary}\n\n`;
  md += `## Work Done\n\n${workDone}\n\n`;

  if (decisions) {
    md += `## Decisions & Rationale\n\n${decisions}\n\n`;
  }

  if (problems) {
    md += `## Problems & Solutions\n\n${problems}\n\n`;
  }

  md += `## Key Files\n\n${keyFiles}\n\n`;

  if (followUp) {
    md += `## Follow-up\n\n${followUp}\n`;
  }

  return md;
}

function buildSummary(turns, meta) {
  // Use the first agent response that has substantial text
  for (const t of turns) {
    if (t.agent.length > 100) {
      // Take first paragraph
      const paras = t.agent.split("\n\n").filter((p) => p.trim().length > 20);
      if (paras.length > 0) {
        let summary = paras[0].trim();
        // Remove markdown headers from the summary line
        summary = summary.replace(/^#+\s*/, "");
        if (summary.length > 500) summary = summary.substring(0, 500) + "...";
        return summary;
      }
    }
  }
  // Fallback: list user messages
  const msgs = turns
    .filter((t) => t.user)
    .slice(0, 3)
    .map((t) => `"${t.user.substring(0, 100)}"`)
    .join("; ");
  return `Session topics: ${msgs || meta.title}`;
}

function buildWorkDone(turns) {
  const bullets = [];

  // Collect substantial agent actions
  for (const t of turns) {
    // Skip turns with no tools or agent text
    if (t.toolCount === 0 && t.agent.length < 50) continue;

    // Look for bullet-point summaries in agent text
    const agentLines = t.agent.split("\n");
    for (const line of agentLines) {
      const trimmed = line.trim();
      // Capture markdown bullets that describe actions
      if (
        trimmed.match(/^[-*]\s+\*\*/) || // bold bullets
        trimmed.match(/^[-*]\s+[A-Z]/) || // regular sentence bullets
        trimmed.match(/^[-*]\s+`/) || // code reference bullets
        trimmed.match(/^\d+\.\s+/) // numbered items
      ) {
        const clean = trimmed
          .replace(/^[-*]\s+/, "- ")
          .replace(/^\d+\.\s+/, "- ");
        if (clean.length > 10 && clean.length < 200 && !bullets.includes(clean)) {
          bullets.push(clean);
        }
      }
    }
  }

  // Also add file operation summaries
  const allCreated = [...new Set(turns.flatMap((t) => t.filesCreated))];
  const allModified = [...new Set(turns.flatMap((t) => t.filesModified))];

  if (allCreated.length > 0 && bullets.length < 30) {
    for (const f of allCreated.slice(0, 10)) {
      const b = `- Created \`${f}\``;
      if (!bullets.some((existing) => existing.includes(f))) bullets.push(b);
    }
  }

  // Deduplicate and limit
  const unique = [];
  const seen = new Set();
  for (const b of bullets) {
    const norm = b.toLowerCase().replace(/[^a-z0-9]/g, "").substring(0, 50);
    if (!seen.has(norm)) {
      seen.add(norm);
      unique.push(b);
    }
  }

  if (unique.length === 0) {
    // Fallback: summarize from user messages
    const msgs = turns
      .filter((t) => t.user && t.toolCount > 0)
      .slice(0, 8)
      .map((t) => `- ${t.user.substring(0, 120)}`);
    return msgs.join("\n") || "- No detailed work items extracted from agent responses.";
  }

  return unique.slice(0, 25).join("\n");
}

function buildDecisions(turns) {
  const decisions = [];

  for (const t of turns) {
    if (t.agent.length < 50) continue;
    const agentLines = t.agent.split("\n");
    for (let i = 0; i < agentLines.length; i++) {
      const line = agentLines[i].trim();
      // Look for decision patterns
      if (
        line.match(/\*\*.*(?:decision|chose|decided|approach|strategy|instead|rather than|opted)/i) ||
        line.match(/^[-*]\s+\*\*(?:No|Yes|Use|Drop|Skip|Keep|Prefer|Switch)/i)
      ) {
        const clean = line.replace(/^[-*]\s+/, "- ");
        if (clean.length > 15 && clean.length < 300) decisions.push(clean);
      }
    }
  }

  if (decisions.length === 0) return "";
  return [...new Set(decisions)].slice(0, 10).join("\n");
}

function buildProblems(turns) {
  const problems = [];

  for (const t of turns) {
    if (t.agent.length < 50) continue;
    const agentLines = t.agent.split("\n");
    for (let i = 0; i < agentLines.length; i++) {
      const line = agentLines[i].trim();
      if (
        line.match(
          /\*\*.*(?:problem|issue|error|bug|fail|broke|fix|root cause|regression|workaround)/i
        ) ||
        line.match(/^[-*]\s+\*\*(?:Fix|Error|Bug|Issue|Problem|Root cause)/i)
      ) {
        const clean = line.replace(/^[-*]\s+/, "- ");
        if (clean.length > 15 && clean.length < 300) problems.push(clean);
      }
    }
  }

  if (problems.length === 0) return "";
  return [...new Set(problems)].slice(0, 10).join("\n");
}

function buildKeyFiles(turns) {
  const allCreated = [...new Set(turns.flatMap((t) => t.filesCreated))].sort();
  const allModified = [...new Set(turns.flatMap((t) => t.filesModified))].sort();

  let md = "";
  if (allCreated.length > 0) {
    md += "**Created:**\n";
    for (const f of allCreated.slice(0, 15)) md += `- \`${f}\`\n`;
  }
  if (allModified.length > 0) {
    if (md) md += "\n";
    md += "**Modified:**\n";
    for (const f of allModified.slice(0, 20)) md += `- \`${f}\`\n`;
  }

  if (!md) md = "No file operations detected in tool calls.";
  return md;
}

function buildFollowUp(turns) {
  // Check last few turns for follow-up mentions
  const items = [];
  for (const t of turns.slice(-5)) {
    const lines = t.agent.split("\n");
    for (const line of lines) {
      const trimmed = line.trim();
      if (
        trimmed.match(
          /(?:follow.?up|TODO|next step|deferred|backlog|future|later|pending)/i
        ) &&
        trimmed.match(/^[-*]/)
      ) {
        const clean = trimmed.replace(/^[-*]\s+/, "- ");
        if (clean.length > 10 && clean.length < 200) items.push(clean);
      }
    }
  }
  if (items.length === 0) return "";
  return [...new Set(items)].slice(0, 8).join("\n");
}

// ── Helpers ─────────────────────────────────────────────────────

function makeSlug(title, sessionId) {
  if (!title || title === "(untitled)") return sessionId.substring(0, 8);
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .substring(0, 50);
}

function fmtTokens(n) {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + "M";
  if (n >= 1_000) return Math.round(n / 1_000) + "k";
  return String(n);
}
