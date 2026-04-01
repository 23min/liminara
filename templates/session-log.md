# Session: {Session Title}

**Date:** {YYYY-MM-DD}  
**Branch:** `{branch-name}`  
**ADO:** [#{ID}](https://dev.azure.com/sdctfs/Infrastruktur/_workitems/edit/{ID})  
**PR:** {link or "none"}  
**Source:** `chatSessions/{session-id}.jsonl`

## Metadata

| Field | Value |
|-------|-------|
| Session ID | `{uuid}` |
| Created | {YYYY-MM-DD HH:MM} UTC |
| Title | {Copilot auto-title or "(untitled)"} |
| Duration | {Xh Ym} |
| Models | {comma-separated model IDs} |
| Total tokens | {N prompt + N output (N total)} |
| Tool calls | {count} |
| MCP servers | {comma-separated or "none"} |
| Content refs | {key files referenced during session} |

<!-- Metadata can be generated with: node scripts/extract-session-metadata.mjs <jsonl-path> -->

## Summary

{2-4 sentences: what was accomplished in this session}

## Work Done

- {bullet list of concrete changes}

## Decisions & Rationale

- **{Decision}:** {Why this choice was made over alternatives}

## Problems & Solutions

- **{Problem}:** {Root cause and how it was resolved}

## Pipeline & Deployment

{Deployment actions taken, environments hit, pipeline runs. Omit section if none.}

## Key Files

**Created:**
- {path}

**Modified:**
- {path}

## Follow-up

- {Items deferred or discovered for future work}
