#!/usr/bin/env node
// extract-session-metadata.mjs — Extract metadata from a Copilot Chat JSONL session file.
//
// Usage:
//   node scripts/extract-session-metadata.mjs <path-to-jsonl>
//   node scripts/extract-session-metadata.mjs <path-to-jsonl> --json
//
// Output: Markdown metadata table (default) or JSON (--json).
//
// The JSONL format is an internal VS Code / Copilot Chat format with three line kinds:
//   kind:0 — Session header with initial requests array
//   kind:1 — Incremental request additions (new turns)
//   kind:2 — Delta updates to existing requests (tool results, responses)
//
// This script extracts: session ID, creation date, title, duration, models,
// token usage, tool call counts, MCP servers, and content references.

import { readFileSync } from "node:fs";
import { basename } from "node:path";

const args = process.argv.slice(2);
const jsonFlag = args.includes("--json");
const filePath = args.find((a) => !a.startsWith("--"));

if (!filePath) {
  console.error(
    "Usage: node scripts/extract-session-metadata.mjs <path-to-jsonl> [--json]"
  );
  process.exit(1);
}

const content = readFileSync(filePath, "utf8");
const lines = content.split("\n").filter((l) => l.trim());

if (lines.length === 0) {
  console.error("Empty file:", filePath);
  process.exit(1);
}

const header = JSON.parse(lines[0]);
if (header.kind !== 0 || !header.v) {
  console.error("Not a valid session JSONL (first line is not kind:0 header)");
  process.exit(1);
}

const v = header.v;

// --- Session ID & creation ---
const sessionId = v.sessionId || basename(filePath, ".jsonl");
const createdMs = v.creationDate;
const createdDate = createdMs ? new Date(createdMs) : null;
const title = v.customTitle || "(untitled)";

// --- Timestamps for duration ---
const timestamps = [];
for (const req of v.requests || []) {
  if (req.timestamp) timestamps.push(req.timestamp);
}
for (const line of lines) {
  try {
    const d = JSON.parse(line);
    if (d.kind === 2) {
      for (const val of Object.values(d.v || {})) {
        if (val && typeof val === "object" && val.timestamp)
          timestamps.push(val.timestamp);
      }
    }
  } catch {
    /* skip malformed lines */
  }
}
timestamps.sort((a, b) => a - b);

let durationStr = "unknown";
if (timestamps.length > 1) {
  const mins = Math.round(
    (timestamps[timestamps.length - 1] - timestamps[0]) / 60000
  );
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  durationStr = h > 0 ? `${h}h ${m}m` : `${m}m`;
}

// --- Models ---
const models = new Set();
for (const req of v.requests || []) {
  if (req.modelId) models.add(req.modelId);
}
for (const line of lines) {
  try {
    const d = JSON.parse(line);
    if (d.kind === 2) {
      for (const val of Object.values(d.v || {})) {
        if (val && typeof val === "object" && val.modelId)
          models.add(val.modelId);
      }
    }
  } catch {
    /* skip */
  }
}

// --- Token usage ---
let totalPrompt = 0;
let totalOutput = 0;
for (const line of lines) {
  if (!line.includes("promptTokens")) continue;
  try {
    const d = JSON.parse(line);
    (function walk(obj, depth) {
      if (!obj || typeof obj !== "object" || depth > 5) return;
      for (const [k, ov] of Object.entries(obj)) {
        if (k === "promptTokens" && typeof ov === "number") totalPrompt += ov;
        if (k === "outputTokens" && typeof ov === "number") totalOutput += ov;
        if (typeof ov === "object") walk(ov, depth + 1);
      }
    })(d, 0);
  } catch {
    /* skip */
  }
}

// --- Tool calls & MCP servers ---
const tools = {};
const mcpServers = new Set();

function countTool(name) {
  tools[name] = (tools[name] || 0) + 1;
  if (name.startsWith("mcp_")) {
    // Extract server prefix: mcp_ado_wit_create_work_item → mcp_ado_wit
    const parts = name.split("_");
    mcpServers.add(parts.slice(0, 3).join("_"));
  }
}

for (const req of v.requests || []) {
  if (req.toolCallRounds) {
    for (const round of req.toolCallRounds) {
      for (const tc of round.toolCalls || []) {
        if (tc.name) countTool(tc.name);
      }
    }
  }
}
for (const line of lines) {
  try {
    const d = JSON.parse(line);
    if (d.kind === 2) {
      for (const val of Object.values(d.v || {})) {
        if (val && typeof val === "object" && val.toolId) countTool(val.toolId);
      }
    }
  } catch {
    /* skip */
  }
}

const totalToolCalls = Object.values(tools).reduce((a, b) => a + b, 0);

// --- Content references ---
const fileRefs = new Set();

function extractRefs(refs) {
  for (const cr of refs || []) {
    const r = cr.reference || cr;
    let p = null;
    if (r && r.uri && r.uri.path) p = r.uri.path;
    else if (r && r.path) p = r.path;
    if (p) {
      p = p.replace(/^\/workspaces\/[^/]+\//, "");
      if (!p.includes("node_modules") && !p.startsWith("/home")) fileRefs.add(p);
    }
  }
}

for (const req of v.requests || []) {
  extractRefs(req.contentReferences);
}
for (const line of lines) {
  try {
    const d = JSON.parse(line);
    if (d.kind !== 2) continue;
    for (const val of Object.values(d.v || {})) {
      if (val && typeof val === "object") extractRefs(val.contentReferences);
    }
  } catch {
    /* skip */
  }
}

// --- Format tokens ---
function fmtTokens(n) {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + "M";
  if (n >= 1_000) return Math.round(n / 1_000) + "k";
  return String(n);
}

// --- Output ---
const result = {
  sessionId,
  created: createdDate ? createdDate.toISOString() : "unknown",
  title,
  duration: durationStr,
  models: [...models],
  promptTokens: totalPrompt,
  outputTokens: totalOutput,
  totalTokens: totalPrompt + totalOutput,
  toolCalls: totalToolCalls,
  mcpServers: [...mcpServers],
  contentRefs: [...fileRefs].sort(),
  source: `chatSessions/${basename(filePath)}`,
};

if (jsonFlag) {
  console.log(JSON.stringify(result, null, 2));
} else {
  const createdFmt = createdDate
    ? `${createdDate.toISOString().slice(0, 10)} ${createdDate.toISOString().slice(11, 16)} UTC`
    : "unknown";
  const tokensFmt = `${fmtTokens(totalPrompt)} prompt + ${fmtTokens(totalOutput)} output (${fmtTokens(totalPrompt + totalOutput)} total)`;

  console.log("## Metadata");
  console.log("");
  console.log("| Field | Value |");
  console.log("|-------|-------|");
  console.log(`| Session ID | \`${sessionId}\` |`);
  console.log(`| Created | ${createdFmt} |`);
  console.log(`| Title | ${title} |`);
  console.log(`| Duration | ~${durationStr} |`);
  console.log(
    `| Models | ${[...models].map((m) => "`" + m + "`").join(", ") || "unknown"} |`
  );
  console.log(`| Total tokens | ${tokensFmt} |`);
  console.log(`| Tool calls | ${totalToolCalls} |`);
  console.log(
    `| MCP servers | ${[...mcpServers].join(", ") || "none"} |`
  );
  console.log(
    `| Content refs | ${[...fileRefs].sort().slice(0, 5).join(", ") || "none"} |`
  );
}
