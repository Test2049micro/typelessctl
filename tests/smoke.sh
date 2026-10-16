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

# help 必须包含核心子命令（防止重命名悄悄破坏接口）
HELP_OUT="$("$TC" help)"
for kw in status doctor guard settings history hub; do
  case "$HELP_OUT" in *"$kw"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: help 缺少 $kw";; esac
done

echo "smoke: $pass passed, $fail failed"
[ "$fail" = 0 ]
