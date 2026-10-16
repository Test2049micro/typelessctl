#!/bin/bash
# 冒烟测试：不依赖 Typeless 安装（CI macOS runner 与真机均可跑）。
# 断言 CLI 退出码契约（0/2/4/5）与 help 输出；不触碰真实用户数据。
set -u
TC="$(cd "$(dirname "$0")/.." && pwd)/bin/typelessctl"
export TYPELESSCTL_DB="/nonexistent/typeless.db"
export TYPELESSCTL_SETTINGS="/nonexistent/app-settings.json"
export TYPELESSCTL_STATE="$(mktemp -d)"

pass=0; fail=0
t() { # t <期望退出码> <描述> <命令...>
  local want="$1" desc="$2"; shift 2
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then pass=$((pass+1));
  else fail=$((fail+1)); echo "FAIL: $desc (want=$want got=$got)"; fi
}

t 0 "help 退出码 0"        "$TC" help
t 0 "version 退出码 0"     "$TC" version
t 0 "status 无 App 也 0"   "$TC" status
t 0 "doctor 报告型命令 0"  "$TC" doctor
t 0 "guard status 0"       "$TC" guard status
t 2 "未知命令 2"           "$TC" nosuchcmd
t 2 "settings set 白名单外 2" "$TC" settings set bogusKey true
t 2 "settings set 缺参数 2"   "$TC" settings set onlyKey
t 4 "hub show 不支持 4"    "$TC" hub show
t 5 "history 无库 5"       "$TC" history list
t 5 "settings 无文件 5"    "$TC" settings list
t 1 "bootcheck 无环境 1"   "$TC" bootcheck
t 2 "history N 非数字 2"   "$TC" history list "1; SELECT 1"
t 2 "settings set 非法JSON 2" "$TC" settings set enableShowAppInDock notjson

# --- 回归：2026-10-17 review 抓出的盲区（此前 CI 全绿却漏掉这些真实故障）---
# 1. 锁必须被释放（曾因 rmdir 删非空目录 → 锁永久残留 → 守卫退化为 62s 才巡查一次）
TD="$(mktemp -d)"
TYPELESSCTL_STATE="$TD" "$TC" guard tick >/dev/null 2>&1
if [ -d "$TD/tick.lock" ]; then fail=$((fail+1)); echo "FAIL: tick 锁未释放（守卫会退化）"
else pass=$((pass+1)); fi
# 2. 首次安装：STATE_DIR 不存在时也必须能工作（曾 mkdir 永久失败 → 守卫从不巡查）
TD2="$(mktemp -d)/deep/nonexist"
TYPELESSCTL_STATE="$TD2" "$TC" guard tick >/dev/null 2>&1
if [ -d "$TD2/tick.lock" ]; then fail=$((fail+1)); echo "FAIL: STATE_DIR 缺失时锁残留"
else pass=$((pass+1)); fi
# 3. --json status 必须是合法 JSON（曾手工拼接，窗口名含反斜杠/引号即破）
if "$TC" --json status 2>/dev/null | python3 -c 'import json,sys;json.load(sys.stdin)' 2>/dev/null; then pass=$((pass+1))
else fail=$((fail+1)); echo "FAIL: --json status 输出非合法 JSON"; fi
# 4. 无 born 的残留锁必须能按目录 mtime 过期清除（否则取得锁后被杀 → 锁永久残留）
TD3="$(mktemp -d)"; mkdir -p "$TD3/tick.lock"; touch -t 202601010000 "$TD3/tick.lock"
TYPELESSCTL_STATE="$TD3" "$TC" guard tick >/dev/null 2>&1
if [ -d "$TD3/tick.lock" ]; then fail=$((fail+1)); echo "FAIL: 无 born 的陈旧锁未被 mtime 清除"
else pass=$((pass+1)); fi
# 5. 陈旧锁的清理不得误伤新锁（mtime 新鲜时必须保留）
TD4="$(mktemp -d)"; mkdir -p "$TD4/tick.lock"
TYPELESSCTL_STATE="$TD4" "$TC" guard tick >/dev/null 2>&1
if [ -d "$TD4/tick.lock" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: 新鲜锁被误清（会导致并发关窗）"; fi
# 6. 继任者锁保护：owner≠本 PID 的新鲜锁，trap 不得删（否则卡死的旧 tick 退出会放倒正在干活的锁）
TD5="$(mktemp -d)"; mkdir -p "$TD5/tick.lock"
date +%s > "$TD5/tick.lock/born"; echo 99999 > "$TD5/tick.lock/owner"
TYPELESSCTL_STATE="$TD5" "$TC" guard tick >/dev/null 2>&1
if [ -d "$TD5/tick.lock" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: 继任者锁被旧 tick 的 trap 误删"; fi
rm -rf "$TD" "$TD2" "$TD3" "$TD4" "$TD5" 2>/dev/null

# help 必须包含核心子命令（防止重命名悄悄破坏接口）
HELP_OUT="$("$TC" help)"
for kw in status doctor bootcheck guard settings history hub; do
  case "$HELP_OUT" in *"$kw"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: help 缺少 $kw";; esac
done

# --- 静态扫描：bash 3.2 里 $VAR 紧跟全角字符会被并入变量名（$now（ → unbound）---
# 作者连踩两次，钉成回归。$VAR 后紧跟非 ASCII（其后是中文括号/逗号）即违规，须写 ${VAR}。
if /usr/bin/python3 - "$TC" <<'PY'
import re,sys
bad=[]
for ln,line in enumerate(open(sys.argv[1],encoding='utf-8'),1):
    for m in re.finditer(r'(?<!\$)\$([a-zA-Z_][a-zA-Z0-9_]*)', line):
        nxt=line[m.end():m.end()+1]
        if nxt and ord(nxt)>127:
            bad.append(f"line {ln}: ${m.group(1)}{nxt}")
if bad: print("\n".join(bad)); sys.exit(1)
PY
then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: 存在 \$VAR 紧跟全角字符（bash3.2 会并名，改 \${VAR}）"; fi

echo "smoke: $pass passed, $fail failed"
[ "$fail" = 0 ]
