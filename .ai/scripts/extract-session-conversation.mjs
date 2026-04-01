#!/usr/bin/env node
// extract-session-conversation.mjs — Extract full conversation from a Copilot JSONL session file.
//
// Usage:
//   node scripts/extract-session-conversation.mjs <path-to-jsonl>
//
// Outputs a JSON array of conversation turns with user messages, agent responses,
// tool calls, and file operations.

import { readFileSync } from "node:fs";

const filePath = process.argv[2];
if (!filePath) {
  console.error("Usage: node scripts/extract-session-conversation.mjs <path-to-jsonl>");
  process.exit(1);
}

const content = readFileSync(filePath, "utf8");
const lines = content.split("\n").filter((l) => l.trim());

if (lines.length === 0) {
  console.error("Empty file");
  process.exit(1);
}

const header = JSON.parse(lines[0]);
if (header.kind !== 0 || !header.v) {
  console.error("Not a valid session JSONL");
  process.exit(1);
}

const v = header.v;
const turns = [];

// ── Step 1: Get header request messages ──────────────────────────

const headerRequests = v.requests || [];
const headerUserMsgs = {};
for (let i = 0; i < headerRequests.length; i++) {
  const req = headerRequests[i];
  if (req.message?.text) {
    headerUserMsgs[i] = cleanUserMessage(req.message.text);
  }
}

// ── Step 2: Extract result entries from kind:1 lines ─────────────

const resultEntries = {};
for (const line of lines) {
  let d;
  try {
    d = JSON.parse(line);
  } catch {
    continue;
  }
  if (d.kind !== 1) continue;
  const k = d.k;
  if (!Array.isArray(k) || k[0] !== "requests" || k[2] !== "result") continue;
  const reqIdx = k[1];
  resultEntries[reqIdx] = d.v;
}

// ── Step 3: Extract user messages from kind:2 deltas ─────────────

const deltaUserMsgs = {};
for (const line of lines) {
  let d;
  try {
    d = JSON.parse(line);
  } catch {
    continue;
  }
  if (d.kind !== 2) continue;
  for (const [k, val] of Object.entries(d.v || {})) {
    if (val && typeof val === "object" && val.message?.text) {
      deltaUserMsgs[parseInt(k)] = cleanUserMessage(val.message.text);
    }
  }
}

// ── Step 4: Build conversation turns ─────────────────────────────

// Collect all request indices
const allIndices = new Set([
  ...Object.keys(headerUserMsgs).map(Number),
  ...Object.keys(resultEntries).map(Number),
  ...Object.keys(deltaUserMsgs).map(Number),
]);

for (const idx of [...allIndices].sort((a, b) => a - b)) {
  const result = resultEntries[idx];
  const meta = result?.metadata || {};

  // User message: prefer delta, then header, then rendered from result
  let userMsg =
    deltaUserMsgs[idx] ||
    headerUserMsgs[idx] ||
    extractUserFromRendered(meta.renderedUserMessage);

  // Agent response text from toolCallRounds
  let agentText = "";
  const toolNames = [];
  const fileOps = { created: [], modified: [], terminal: [] };

  for (const round of meta.toolCallRounds || []) {
    if (round.response) agentText += round.response + "\n";
    for (const tc of round.toolCalls || []) {
      toolNames.push(tc.name);
      try {
        const args = JSON.parse(tc.arguments || "{}");
        const strip = (p) => p.replace(/.*\/Treehouse\//, "");
        if (tc.name === "copilot_createFile" && args.filePath)
          fileOps.created.push(strip(args.filePath));
        if (tc.name === "create_file" && args.filePath)
          fileOps.created.push(strip(args.filePath));
        if (
          (tc.name === "copilot_replaceString" ||
            tc.name === "copilot_multiReplaceString" ||
            tc.name === "replace_string_in_file" ||
            tc.name === "multi_replace_string_in_file") &&
          args.filePath
        )
          fileOps.modified.push(strip(args.filePath));
        if (
          (tc.name === "run_in_terminal" || tc.name === "copilot_runInTerminal") &&
          args.command
        )
          fileOps.terminal.push(args.command.substring(0, 120));
      } catch {
        /* skip */
      }
    }
  }

  // Also get agent text from kind:0 header response parts
  if (!agentText && headerRequests[idx]) {
    for (const p of headerRequests[idx].response || []) {
      if (
        p.kind === "thinking" ||
        p.kind === "toolInvocationSerialized" ||
        p.kind === "textEditGroup"
      )
        continue;
      if (p.value && typeof p.value === "string") agentText += p.value;
    }
  }

  if (!userMsg && !agentText) continue; // skip empty turns

  turns.push({
    index: idx,
    user: userMsg || "",
    agent: agentText.trim(),
    tools: [...new Set(toolNames)],
    toolCount: toolNames.length,
    filesCreated: [...new Set(fileOps.created)],
    filesModified: [...new Set(fileOps.modified)],
    terminalCommands: fileOps.terminal,
  });
}

console.log(JSON.stringify(turns, null, 2));

// ── Helpers ──────────────────────────────────────────────────────

function cleanUserMessage(text) {
  if (!text) return "";
  // Extract content from <userRequest> tags if present
  const reqMatch = text.match(/<userRequest>\s*([\s\S]*?)\s*<\/userRequest>/);
  if (reqMatch) return reqMatch[1].trim();
  // Strip HTML/XML tags and system context
  let clean = text.replace(/<[^>]*>/g, " ").trim();
  // If it starts with system context, try to find the user part
  if (clean.startsWith("Information about") || clean.startsWith("The current date")) {
    // Look for the last substantive line
    const contextLines = clean.split("\n");
    const userLines = contextLines.filter(
      (l) =>
        l.trim() &&
        !l.startsWith("Information about") &&
        !l.startsWith("The current date") &&
        !l.startsWith("Terminal:") &&
        !l.startsWith("Last Command:") &&
        !l.startsWith("Cwd:") &&
        !l.startsWith("Exit Code:") &&
        !l.includes("reminderInstructions") &&
        !l.includes("editorContext") &&
        !l.includes("workspace_info") &&
        l.length > 3
    );
    clean = userLines.join(" ").trim();
  }
  // Truncate if still too long
  if (clean.length > 500) clean = clean.substring(0, 500) + "...";
  return clean;
}

function extractUserFromRendered(parts) {
  if (!parts || !Array.isArray(parts)) return "";
  let text = "";
  for (const p of parts) {
    if (p.text) text += p.text;
  }
  return cleanUserMessage(text);
}
