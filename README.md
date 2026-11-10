# 终端

浏览器里的终端，连的是这台服务器本身：以 root 走宿主自己的 sshd。Zellij（MIT）管会话：切到别的 App、关掉页面都能接回同一个会话，退出后也能恢复；手机上有触屏界面、快捷键条和屏幕键盘。

**等于把宿主的 root 交给这个插件。** 容器本身不加特权、不进宿主 PID 命名空间、不挂 Docker socket、不挂宿主根目录，能力全来自网络上的 ssh。

只给主人用：插件不注册 MCP 工具，Bot 拿不到；安装后不要打开“家人能用”。

## 安装

1. 装好插件，打开插件的网页。
2. 页面上有一条 `echo 'ssh-ed25519 …' >> ~/.ssh/authorized_keys`。以 root 在宿主上执行它：

   ```bash
   # 在宿主上，root
   echo 'ssh-ed25519 AAAA…插件页面上的整行' >> ~/.ssh/authorized_keys
   ```

   或者手动把页面上的公钥加到 root 的 `~/.ssh/authorized_keys`。
3. 点“试一次”，连上了再点“连接”。

宿主地址默认是插件网络里的网关地址（也就是这台宿主），端口 22；要连别的机器就改这两项。

## 连不上的三种情况

页面会分开说，原始错误在“详情”里：

| 现象 | 意思 | 下一步 |
| --- | --- | --- |
| 连不上 | sshd 没开或端口不对 | 在宿主上开 sshd、检查地址和端口 |
| 公钥没加 | 宿主没认这把公钥 | 把页面上的公钥加到 root 的 `authorized_keys` |
| 认证过了但被拒 | 多半是 `PermitRootLogin` 不让 root 登录 | 改成 `prohibit-password` 或 `yes` 后重启 sshd |

## 密钥

密钥是插件自己用 `ssh-keygen` 生成的，私钥只在插件的数据卷里。详情页可以撤销、重新生成；换过之后旧公钥在宿主上失效，记得去 `authorized_keys` 里换掉。主机指纹第一次连接时自己核对，不自动信任。

## 图标

Zellij 官方标志，来源和商标说明见 [NOTICE](NOTICE)。

## 开发

流程见[插件开发指南](https://github.com/geraldpeng6/wonton-docs/blob/main/develop.md)，清单和权限规则见[插件规范](https://github.com/geraldpeng6/wonton-docs/blob/main/plugin-spec.md)。

镜像在 `images/wonton-terminal/`，从上游发行的二进制构建：改了 Dockerfile 就在本机构建一次（`docker build -t ghcr.io/geraldpeng6/wonton-terminal:0.2.0 images/wonton-terminal`），开发环境用本机的同名镜像。
