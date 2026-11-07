#!/bin/sh
# 登录令牌和 SSH 密钥，放在插件自己的数据卷里。每次启动都核对，幂等：
# 令牌被吊销或数据卷丢了就重新生成，密钥只在缺失时生成（换掉它，目标主机上的 authorized_keys 要跟着换）。
set -eu

state=/data/state
token_file="$state/token"
key="$HOME/.ssh/id_ed25519"
mkdir -p "$state" "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

token_valid() {
    [ -s "$token_file" ] || return 1
    curl -fsS -o /dev/null -H 'Content-Type: application/json' \
        -d "{\"auth_token\":\"$(cat "$token_file")\"}" http://127.0.0.1:8082/command/login
}

if ! token_valid; then
    created="$(zellij web --create-token)"
    # 输出是“Created token successfully”空行“token_N: <令牌>”。
    printf '%s' "${created##*: }" >"$token_file"
    chmod 600 "$token_file"
fi

if [ ! -s "$key" ]; then
    ssh-keygen -q -t ed25519 -N '' -C wonton-terminal -f "$key"
fi
# 公钥被删了就从私钥补回来，页面显示的就是这一行。
[ -s "$key.pub" ] || ssh-keygen -y -f "$key" >"$key.pub"
