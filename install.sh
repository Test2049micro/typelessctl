#!/bin/bash
# typelessctl 一键安装：赋权、注册静默守卫、把命令链到 ~/.local/bin。
set -eu
cd "$(dirname "$0")"
chmod +x bin/typelessctl
bin/typelessctl guard install
mkdir -p "$HOME/.local/bin"
ln -sf "$(cd bin && pwd)/typelessctl" "$HOME/.local/bin/typelessctl"
echo
echo "完成。命令已链接：~/.local/bin/typelessctl（确保其在 PATH 中）"
echo "重启 Mac 后可运行：typelessctl bootcheck 验证开机静默三件套。"
