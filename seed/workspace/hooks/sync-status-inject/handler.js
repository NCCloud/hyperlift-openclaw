import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const NOTE_PREFIX = "<!-- Runtime state (auto-injected):";
const notePattern = /^<!-- Runtime state \(auto-injected\):[^\n]*-->\n\n/;

// Sync is on iff ~/.openclaw/.git exists. init.sh creates that directory only
// after a successful clone, so its presence is a reliable indicator that sync
// is fully set up.
function detectSyncState() {
  return fs.existsSync(path.join(os.homedir(), ".openclaw", ".git"));
}

// Fires on agent:bootstrap — runs before every agent turn's system prompt is
// assembled. Pure in-process; no LLM round-trip, no chat pollution.
// Overhead: ~15 tokens of AGENTS.md prefix per turn.
const handler = async (event) => {
  // Ignore any other events this handler might receive.
  if (event?.type !== "agent" || event?.action !== "bootstrap") return;
  const files = event?.context?.bootstrapFiles;
  if (!Array.isArray(files)) return;

  const syncOn = detectSyncState();
  // HTML comment — safe inside Markdown, renderer ignores it; only the LLM reads it.
  const note = `${NOTE_PREFIX} git sync is currently ${syncOn ? "ON" : "OFF"} -->\n\n`;

  // We only annotate AGENTS.md. SOUL.md, USER.md, etc. stay untouched.
  const idx = files.findIndex((f) => f?.name === "AGENTS.md");
  if (idx < 0) return;
  const current = files[idx];
  if (typeof current?.content !== "string") return;

  // Bootstrap cache holds the same object references across invocations. Mutating
  // current.content would stack injections across turns. Strip any prior note,
  // then emit a NEW object so the cached entry's content stays untouched for any
  // other consumer.
  const stripped = current.content.replace(notePattern, "");
  files[idx] = { ...current, content: note + stripped };
};

export default handler;
