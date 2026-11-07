# shellcheck shell=bash
# 跟着插件走的冒烟探针。网页、身份、数据三项都真的请求插件。

# 入口页出现（没有 Zellij 会话 Cookie 时 / 落到入口页），页面上有登录令牌和 SSH 公钥。
web_assert() { grep -q '登录令牌' && grep -q 'ssh-ed25519'; }

# 身份就是核心网关：带主人会话能拿到入口页，而页面的令牌是真的能登录的（Zellij 回 200）。
identity_check() {
    local page token
    page="$(web_get /__wonton)" || { echo "取入口页失败：$page"; return 1; }
    token="$(sed -n 's#.*id="token">\([^<]*\)</code>.*#\1#p' <<<"$page")"
    [[ -n "$token" ]] || { echo "入口页里没有令牌：$(head -c 200 <<<"$page")"; return 1; }
    curl -sS --noproxy '*' -o /dev/null -f -H 'Content-Type: application/json' \
        -d "{\"auth_token\":\"$token\"}" "$SMOKE_WEB_URL/command/login" ||
        { echo "页面里的令牌登录不了 Zellij"; return 1; }
}

# 数据：令牌、SSH 密钥和会话快照都在插件卷里。写一条标记，同时记下当前令牌；重装、升级后都还在才算数。
web_container() { printf 'wonton-%s--dev-zellij-terminal--web' "$SMOKE_INSTANCE"; }

data_write() {
    local marker
    marker="$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    printf '%s\n' "$marker" >"$SMOKE_STATE"
    docker exec -u 0 "$(web_container)" sh -c "printf %s '$marker' > /data/state/smoke-marker && cat /data/state/token" \
        >>"$SMOKE_STATE" ||
        { echo "写标记失败"; return 1; }
}

data_check() {
    local marker token want
    { read -r marker; read -r token; } <"$SMOKE_STATE"
    want="$(docker exec -u 0 "$(web_container)" cat /data/state/smoke-marker 2>&1)" ||
        { echo "标记读不到：$want"; return 1; }
    [[ "$want" == "$marker" ]] || { echo "标记对不上：$want != $marker"; return 1; }
    [[ -n "$token" ]] || return 0
    docker exec -u 0 "$(web_container)" sh -c 'cat /data/state/token' 2>/dev/null |
        grep -qxF "$token" || { echo "登录令牌变了"; return 1; }
}
