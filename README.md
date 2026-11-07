# Zellij 终端

服务器上的终端，在云吞的 App 或浏览器里打开。Zellij（MIT）负责会话：切到别的 App、关掉页面都能接回同一个会话，会话退出后也能恢复；手机上有触屏界面、快捷键条和屏幕键盘。连容器自己的 shell，也能从终端里 `ssh` 到局域网的其他机器。

只给主人用：插件不注册 MCP 工具，Bot 拿不到；安装后不要打开“家人能用”，家人就打不开这个插件的网页。容器里是普通用户，没有宿主 root，不带 Docker socket。

## 用

装好后第一次打开是入口页，上面有登录令牌和 SSH 公钥。

- 点“进入”进终端。Zellij 用这条令牌登录，浏览器里记四周；令牌同时可以给命令行客户端用（`zellij attach https://<插件地址>/<会话> --token <令牌>`）。令牌在插件的卷里，丢了就重装一次插件换新的，会话数据保留。
- 要去别的机器：把入口页的公钥加到目标主机的 `~/.ssh/authorized_keys`，在终端里 `ssh 用户@主机`。首次连接由 Zellij 显示主机指纹，你自己核对，没有自动信任。

会话和令牌都在插件的卷里；卸载时选删除数据才会一起删掉。

## 网络

容器要出网才能连局域网主机。装了代理的主机，插件的出网走核心配的出口代理；`ssh` 连私有网段本来就在 `NO_PROXY` 里，走直连。

## 图标

Zellij 官方标志，来源和商标说明见 [NOTICE](NOTICE)。

## 开发

流程见[插件开发指南](https://github.com/geraldpeng6/wonton-docs/blob/main/develop.md)，清单和权限规则见[插件规范](https://github.com/geraldpeng6/wonton-docs/blob/main/plugin-spec.md)。

镜像在 `images/wonton-terminal/`，从上游发行的二进制构建：改了 Dockerfile 就在本机构建一次（`docker build -t ghcr.io/geraldpeng6/wonton-terminal:0.1.0 images/wonton-terminal`），开发环境用本机的同名镜像。
