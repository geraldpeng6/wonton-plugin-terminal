#!/bin/sh
# Zellij 里的默认 shell：直接以 root ssh 到宿主。连不上就说明原因并留在容器里，不静默退出。
cfg=/data/state/host
host="$(sed -n 1p "$cfg" 2>/dev/null)"
port="$(sed -n 2p "$cfg" 2>/dev/null)"

if [ -z "$host" ]; then
    host="$(python3 - <<'PY'
import sys
sys.path.insert(0, "/opt/wonton")
from server import default_host
print(default_host())
PY
)"
fi
port="${port:-22}"

if [ ! -s "$HOME/.ssh/id_ed25519" ]; then
    printf '\n还没有 SSH 密钥。回到入口页生成一把，再把公钥加到宿主的 authorized_keys。\n\n'
    exec bash
fi

printf '\n以 root 连接 %s:%s ……（首次连接会显示主机指纹，核对后输 yes）\n\n' "$host" "$port"
ssh -p "$port" "root@$host"
code=$?
if [ "$code" != 0 ]; then
    printf '\nssh 退出码 %s。公钥加过了吗？入口页的“试一次”会说清是哪一类失败。\n\n' "$code"
fi
exec bash
