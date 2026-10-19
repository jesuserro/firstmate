#!/usr/bin/env bash
set -u

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-pi-cold-resume)
EXT="$ROOT/.pi/extensions/fm-primary-pi-watch.ts"

make_fixture() {
  local repo=$1
  mkdir -p "$repo/.pi/extensions/lib" "$repo/node_modules/@earendil-works/pi-coding-agent" \
    "$repo/node_modules/@earendil-works/pi-tui" "$repo/node_modules/typebox" "$repo/bin"
  cp "$EXT" "$repo/.pi/extensions/fm-primary-pi-watch.ts"
  cp "$ROOT/.pi/extensions/lib/fm-branch-dispatch.ts" "$repo/.pi/extensions/lib/fm-branch-dispatch.ts"
  cp "$ROOT/.pi/extensions/lib/fm-native-contract.ts" "$repo/.pi/extensions/lib/fm-native-contract.ts"
  cp "$ROOT/.pi/extensions/lib/fm-async-exec.ts" "$repo/.pi/extensions/lib/fm-async-exec.ts"
  cp "$ROOT/.pi/extensions/lib/fm-calm-visibility.ts" "$repo/.pi/extensions/lib/fm-calm-visibility.ts"
  cp "$ROOT/.pi/extensions/lib/fm-operational-input.ts" "$repo/.pi/extensions/lib/fm-operational-input.ts"
  cp "$ROOT/.pi/extensions/lib/fm-pi-home-binding.ts" "$repo/.pi/extensions/lib/fm-pi-home-binding.ts"
  cat > "$repo/node_modules/@earendil-works/pi-coding-agent/package.json" <<'JSON'
{"name":"@earendil-works/pi-coding-agent","type":"module","exports":"./index.js"}
JSON
  cat > "$repo/node_modules/@earendil-works/pi-coding-agent/index.js" <<'JS'
export function getMarkdownTheme() { return {}; }
export class UserMessageComponent { render() { return []; } invalidate() {} }
JS
  cat > "$repo/node_modules/@earendil-works/pi-tui/package.json" <<'JSON'
{"name":"@earendil-works/pi-tui","type":"module","exports":"./index.js"}
JSON
  cat > "$repo/node_modules/@earendil-works/pi-tui/index.js" <<'JS'
export class Box { addChild() {} clear() {} setBgFn() {} }
export class Container {}
export class Text {}
JS
  cat > "$repo/node_modules/typebox/package.json" <<'JSON'
{"name":"typebox","type":"module","exports":"./index.js"}
JSON
  cat > "$repo/node_modules/typebox/index.js" <<'JS'
export const Type = { Object(properties) { return { type: "object", properties, additionalProperties: false }; } };
JS
  cat > "$repo/bin/fm-lock.sh" <<'SH'
#!/usr/bin/env bash
set -u
if [ "${FM_LOCK_TEST_MODE:-stale}" = live ]; then
  printf '%s\n' "live owner refusal" >&2
  exit 1
fi
printf '%s\n' "$PPID" > "$FM_STATE_OVERRIDE/.lock"
printf '%s\n' 'lock acquired: harness pid' "$PPID"
SH
  chmod +x "$repo/bin/fm-lock.sh"
  cat > "$repo/bin/fm-watch-arm.sh" <<'SH'
#!/usr/bin/env bash
printf 'watcher: started pid=%s recovery-generation=test-generation\n' "$PPID"
sleep 1
SH
  chmod +x "$repo/bin/fm-watch-arm.sh"
}

run_case() {
  local mode=$1 expected=$2
  local repo="$TMP_ROOT/repo-$mode" home="$TMP_ROOT/home-$mode" session="$TMP_ROOT/session-$mode.jsonl"
  local primary_pid current_pid
  primary_pid=$([[ "$mode" = stale ]] && echo 99999999 || ([[ "$mode" = replaced ]] && echo 77777777 || echo 2))
  current_pid=$([[ "$mode" = stale ]] && echo 99999999 || ([[ "$mode" = replaced ]] && echo 88888888 || echo 1))
  mkdir -p "$home/state" "$home/config"
  chmod 700 "$home" "$home/state" "$home/config"
  make_fixture "$repo"
  : > "$session"
  chmod 600 "$session"
  if [ "$mode" = manual ]; then
    rm -f "$home/state/.lock"
  else
    printf '%s\n' "$current_pid" > "$home/state/.lock"
  fi
  FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" FM_STATE_OVERRIDE="$home/state" FM_MODE="$mode" FM_SESSION="$session" FM_PRIMARY_PID="$primary_pid" FM_EXPECTED="$expected" PLUGIN="$repo/.pi/extensions/fm-primary-pi-watch.ts" NODE_NO_WARNINGS=1 \
    node --input-type=module <<'EOF'
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
import { existsSync, readFileSync, writeFileSync } from "node:fs";

const handlers = new Map();
const entries = process.env.FM_MODE === "manual" ? [] : [
  { type: "custom", customType: "firstmate-pi-home-binding", data: { schema: "firstmate.pi-home-binding.v1", home: process.env.FM_HOME } },
  { type: "custom", customType: "firstmate-pi-primary-lock", data: { schema: "firstmate.pi-primary-lock.v1", home: process.env.FM_HOME, sessionFile: process.env.FM_SESSION, lockPid: process.env.FM_PRIMARY_PID } },
];
const manager = {
  getSessionFile: () => process.env.FM_SESSION,
  getEntries: () => entries,
  getHeader: () => ({ timestamp: process.env.FM_MODE === "manual" ? new Date().toISOString() : "2020-01-01T00:00:00.000Z" }),
};
let tool;
const pi = {
  on(event, handler) { handlers.set(event, handler); },
  registerCommand() {},
  registerTool(candidate) { if (candidate.name === "fm_watch_arm_pi") tool = candidate; },
  appendEntry(customType, data) { entries.push({ type: "custom", customType, data }); },
  sendUserMessage: async () => {},
};
const mod = await import(pathToFileURL(process.env.PLUGIN).href);
const bindingMod = await import(pathToFileURL(`${process.env.PLUGIN.replace('/fm-primary-pi-watch.ts', '/lib/fm-pi-home-binding.ts')}`).href);
const bindingProbe = bindingMod.resolvePiHome({ sessionManager: manager }, process.env.FM_HOME, "startup");
if (process.env.FM_MODE !== "manual" && (!bindingProbe.ok || !bindingProbe.primary)) throw new Error(`fixture primary claim probe failed: ${JSON.stringify(bindingProbe)} helper=${readFileSync(pathToFileURL(`${process.env.PLUGIN.replace('/fm-primary-pi-watch.ts', '/lib/fm-pi-home-binding.ts')}`).pathname, 'utf8').includes('primaryType')} manager=${manager.getSessionFile()} resolved=${resolve(manager.getSessionFile())} entry=${JSON.stringify(entries[1])}`);
mod.default(pi);
await handlers.get("session_start")({ reason: "startup" }, { sessionManager: manager });
if (process.env.FM_MODE === "manual") {
  if (existsSync(`${process.env.FM_HOME}/state/.pi-watch-extension-loaded`)) throw new Error("free startup published a marker");
  writeFileSync(`${process.env.FM_HOME}/state/.lock`, `${process.pid}\n`);
  const armed = await tool.execute("manual-native-arm", {}, undefined, undefined, {});
  if (!armed.details?.ok || !entries.some((entry) => entry.customType === "firstmate-pi-primary-lock")) {
    throw new Error(`manual arm did not record primary claim: ${JSON.stringify(armed.details)} entries=${JSON.stringify(entries)}`);
  }
  process.exit(0);
}
const lock = readFileSync(`${process.env.FM_HOME}/state/.lock`, "utf8").trim();
if (process.env.FM_EXPECTED === "reclaimed" && lock !== String(process.pid)) throw new Error(`stale lock was not reclaimed: ${lock}`);
if (process.env.FM_EXPECTED === "refused") {
  const expected = process.env.FM_MODE === "replaced" ? "88888888" : "1";
  if (lock !== expected) throw new Error(`refused lock was changed: ${lock}`);
  if (existsSync(`${process.env.FM_HOME}/state/.pi-watch-extension-loaded`)) throw new Error("live-owner refusal published a marker");
}
EOF
  return $?
}

run_case stale reclaimed
run_case live refused
run_case replaced refused
run_case manual manual
printf 'ok - restored Pi cold resume reclaims only a dead owner and refuses a live owner\n'
