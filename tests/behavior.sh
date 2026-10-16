#!/bin/bash
# 行为级测试：在沙箱里真跑 settings/export，验证"改了原文件没、权限对不对、备份在不在"，
# 而不只是退出码。smoke.sh 测契约，本文件测副作用。
set -u
TC="$(cd "$(dirname "$0")/.." && pwd)/bin/typelessctl"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); }
nope() { fail=$((fail+1)); echo "FAIL: $1"; }

# --- 假环境：App Support 目录 + settings + 带 history_v2 的库 ---
AS="$SB/AppSupport/Typeless"; mkdir -p "$AS"
printf '{"enableShowAppInDock":false,"historyDurationSeconds":-1,"launchAtSystemStartup":true}\n' > "$AS/app-settings.json"
sqlite3 "$AS/typeless.db" "CREATE TABLE history_v2(id text primary key, created_at text, updated_at text, mode text, status text, duration real, app_version text, refined_text text, audio_local_path text);
INSERT INTO history_v2 VALUES('a','2026-01-01 00:00:00','2026-01-01','m','s',1.0,'v','hello text','/x');" 2>/dev/null || { echo "沙箱 sqlite 不可用，behavior 测试中止"; exit 77; }
export TYPELESSCTL_SETTINGS="$AS/app-settings.json"
export TYPELESSCTL_DB="$AS/typeless.db"
export TYPELESSCTL_STATE="$SB/state"

# === settings set: 成功路径写对 + 留备份 ===
"$TC" settings set enableShowAppInDock true >/dev/null 2>&1 && ok || nope "set 合法值应成功"
val="$(python3 -c "import json;print(json.load(open('$AS/app-settings.json'))['enableShowAppInDock'])" 2>/dev/null)"
[ "$val" = "True" ] && ok || nope "写入后值应为 true，实为 '$val'"
ls "$SB/state"/app-settings.*.bak >/dev/null 2>&1 && ok || nope "应留有备份文件"

# === 非法 JSON：原文件不动 + 退出码 2 ===
before="$(cat "$AS/app-settings.json")"
"$TC" settings set launchAtSystemStartup not_a_json >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok || nope "非法 JSON 应退 2，实为 $rc"
[ "$(cat "$AS/app-settings.json")" = "$before" ] && ok || nope "非法 JSON 后原文件不应被改"

# === 原文件权限在写后保持（原子替换不得放宽权限）===
chmod 600 "$AS/app-settings.json"
"$TC" settings set launchAtSystemStartup true >/dev/null 2>&1
perm="$(stat -f '%Lp' "$AS/app-settings.json" 2>/dev/null)"
[ "$perm" = "600" ] && ok || nope "写后权限应保持 600，实为 $perm"

# === history export: 目标文件权限 600（与 umask 无关）===
( umask 022; "$TC" history export "$SB/e.csv" >/dev/null 2>&1 )
eperm="$(stat -f '%Lp' "$SB/e.csv" 2>/dev/null)"
[ "$eperm" = "600" ] && ok || nope "导出文件应 600，实为 $eperm"
grep -q "hello text" "$SB/e.csv" && ok || nope "导出内容应含数据"

# === history export 失败不得截断既有目标 ===
printf 'PRECIOUS\n' > "$SB/exist.csv"
TYPELESSCTL_DB="$SB/empty.db" sqlite3 "$SB/empty.db" "CREATE TABLE t(x)" 2>/dev/null
TYPELESSCTL_DB="$SB/empty.db" "$TC" history export "$SB/exist.csv" >/dev/null 2>&1; rc=$?
[ "$rc" = 5 ] && ok || nope "表缺失应退 5，实为 $rc"
[ "$(cat "$SB/exist.csv")" = "PRECIOUS" ] && ok || nope "导出失败不得动既有目标文件"

# === history list N 校验（注入面）===
"$TC" history list "1;DROP TABLE history_v2" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok || nope "恶意 N 应退 2，实为 $rc"
sqlite3 "$AS/typeless.db" "SELECT count(*) FROM history_v2" >/dev/null 2>&1 && ok || nope "表不应被动过"

echo "behavior: $pass passed, $fail failed"
[ "$fail" = 0 ]
