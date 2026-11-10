#!/bin/sh
# 登录令牌和 SSH 密钥，放在插件自己的数据卷里，顺手把入口页填出来。
# 不带参数：只在缺失时生成（容器启动、服务起来之前）。--revalidate：服务起来以后核对，
# 令牌被吊销就换新的，再重填页面。两种都是幂等的。
set -eu

state=/data/state
token_file="$state/token"
key="$HOME/.ssh/id_ed25519"
mkdir -p "$state" "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

create_token() {
    created="$(zellij web --create-token)"
    # 输出是“Created token successfully”空行“token_N: <令牌>”。
    printf '%s' "${created##*: }" >"$token_file"
    chmod 600 "$token_file"
}

token_valid() {
    [ -s "$token_file" ] || return 1
    curl -fsS -o /dev/null -H 'Content-Type: application/json' \
        -d "{\"auth_token\":\"$(cat "$token_file")\"}" http://127.0.0.1:8082/command/login
}

render() {
    [ -s "$key.pub" ] || ssh-keygen -y -f "$key" >"$key.pub"
    # 值里可能带 |，模板里的占位符不会。
    pubkey="$(cat "$key.pub")"
    sed -e "s|__TOKEN__|$(cat "$token_file")|" \
        -e "s|__PUBKEY__|$pubkey|" \
        -e "s|__ADDKEY__|echo '$pubkey' >> ~/.ssh/authorized_keys|" \
        /opt/wonton/landing.html >/tmp/landing.html
}

if [ "${1:-}" = --revalidate ]; then
    token_valid && exit 0
    create_token
    render
    exit 0
fi

[ -s "$token_file" ] || create_token
if [ ! -s "$key" ]; then
    ssh-keygen -q -t ed25519 -N '' -C wonton-terminal -f "$key"
fi
# 公钥被删了就从私钥补回来，页面显示的就是这一行。
[ -s "$key.pub" ] || ssh-keygen -y -f "$key" >"$key.pub"
render
