# BaiduPCS-Rust 的 OpenWrt 软件包

为开源项目 [BaiduPCS-Rust](https://github.com/komorebiCarry/BaiduPCS-Rust)
（Rust + Vue 3 百度网盘第三方客户端）编写的 OpenWrt buildroot 软件包适配。

- 上游版本：v2.4.1（后端 crate：`baidu-netdisk-rust`，源码包 sha256 已内置校验）
- 许可证：Apache-2.0
- 二进制：`/usr/bin/baidu-netdisk-rust`（可选附加 `/usr/bin/decrypt-cli`）
- 服务：procd 托管，`/etc/init.d/baidupcs-rust`，开机自启、崩溃自动拉起
- Web 管理界面：默认 `http://<路由器 IP>:18888/`

---

## 1. 目录结构

```
package/baidupcs-rust/
├── Makefile                    # 软件包主构建文件
├── Config.in                   # menuconfig 编译选项
├── README.md                   # 本文件
└── files/
    ├── baidupcs-rust.init      # -> /etc/init.d/baidupcs-rust（procd 启动脚本）
    ├── baidupcs-rust.conf      # -> /etc/config/baidupcs-rust（UCI 模板）
    └── luci-app/               # 可选 LuCI 集成页
        ├── menu.d/luci-app-baidupcs-rust.json
        └── htdocs/luci-static/resources/view/baidupcs-rust/page.js
```

安装后运行时目录（默认 `/opt/baidupcs-rust`，可在 menuconfig/UCI 修改）：

```
/opt/baidupcs-rust/
├── frontend/        # Web UI 静态资源（随包安装）
├── config/          # app.toml + baidu-pcs.db(SQLite) + encryption.json 等敏感数据
├── wal/             # 任务断点/元数据 WAL
├── logs/            # 滚动日志
└── downloads/       # 默认下载目录（建议改到 USB 硬盘/extroot）
```

> 程序按 **当前工作目录** 读取 `./config/app.toml` 与 `./frontend`（二进制自带
> 多级探测，最终回退到 exe 同级目录），因此 init 脚本把工作目录设为 procd
> `cwd`，所有数据自然集中到该目录，便于备份与 extroot 迁移。

## 2. 集成进 OpenWrt 编译流程

### 前置条件

1. 需要启用 **packages feed**（提供 Rust 工具链包 `rust/host`）：
   ```sh
   # 在 OpenWrt 顶层目录
   echo 'src-git packages https://git.openwrt.org/feed/packages.git' >> feeds.conf.default
   ./scripts/feeds update -a
   ./scripts/feeds install -a
   ```
2. 构建宿主需可访问 crates.io（首次 `cargo` 拉取依赖，`--locked` 固定版本；
   CARGO_HOME 位于 `dl/cargo`，可复用）与 github.com（源码与前端 Release 包）。
3. 编译大项目（tokio + axum + rusqlite，LTO + codegen-units=1）峰值内存约
   2–4 GB，请保证内存/交换空间充足。

### 方式一：直接放入 package 目录（最简单）

```sh
cp -r package/baidupcs-rust <openwrt-topdir>/package/
```

### 方式二：作为自定义 feed 集成

```sh
# 在自定义 feed 仓库根目录放置 package/baidupcs-rust/ 后：
echo 'src-git mypkgs https://github.com/you/my-openwrt-packages.git' \
    >> feeds.conf.default
./scripts/feeds update mypkgs
./scripts/feeds install baidupcs-rust
```

### menuconfig 选项路径

```
make menuconfig
├── Network ──> File Transfer ──> baidupcs-rust      # 主包
└── LuCI ──> 3. Applications ──> luci-app-baidupcs-rust   # 可选 LuCI 页

# 选中主包后，在包自身的 "BaiduPCS-Rust 编译选项" 子菜单中可配置：
#   [*] 捆绑内置 Web UI 静态资源
#   [ ] 编译并安装独立解密工具 decrypt-cli
#   [ ] 全静态 musl 链接（crt-static，需构建宿主 rustup）
#   运行时工作目录（默认 /opt/baidupcs-rust）
```

### 编译与安装

```sh
make package/baidupcs-rust/{clean,compile} V=s -j$(nproc)
# 产物：bin/packages/<arch>/baidupcs-rust_2.4.1-r1_<arch>.ipk
#       bin/packages/<arch>/luci-app-baidupcs-rust_*.ipk
```

部署到已运行的路由器：

```sh
opkg install baidupcs-rust_*.ipk
opkg install luci-app-baidupcs-rust_*.ipk     # 可选
```

首次启动：

```sh
mkdir -p /opt/baidupcs-rust/downloads   # 若工作目录在 extroot，请先挂载
uci set baidupcs-rust.main.enabled=1
uci set baidupcs-rust.main.download_dir='/mnt/sda1/downloads'
uci set baidupcs-rust.main.fs_default_path='/mnt/sda1'
uci commit baidupcs-rust
/etc/init.d/baidupcs-rust regenerate    # 用 UCI 生成 app.toml（覆盖已有文件）
/etc/init.d/baidupcs-rust enable && /etc/init.d/baidupcs-rust start
```

## 3. 功能覆盖与 OpenWrt 下的使用方式

本项目所有网盘功能都通过内置 Web UI（REST API `/api/v1/*` +
WebSocket `/api/v1/ws`）提供，OpenWrt 包不裁剪功能，按如下入口使用：

| 功能模块 | 入口（Web UI，端口默认 18888） | OpenWrt 配置入口 |
| --- | --- | --- |
| 登录授权（二维码 / Cookie / 多账号） | 登录页扫码，或在“账号”页粘贴 Cookie | `/opt/baidupcs-rust/config/`（会话与凭据持久化） |
| 文件浏览/搜索/新建/删除/复制/移动/重命名 | “网盘”页 | — |
| 下载（多线程分片、断点续传、文件夹/批量、冲突策略、限速） | “下载”页 | `[download]`（app.toml，由 UCI 首次生成） |
| 上传（文件/文件夹、秒传、批量、冲突策略） | “上传”页 | `[filesystem].allowed_paths` 白名单（UCI `fs_allowed_paths`） |
| 转存（个人/企业版分享链接 + 提取码，目标账号/目录选择） | “转存”页 | — |
| 分享管理（创建、改有效期、取消、次数统计） | “分享”页 | — |
| 分享同步（订阅分享，定时/cron 增量转存/下载，包含/排除规则） | “分享同步”页 | 订阅与运行历史存 SQLite |
| 离线下载（HTTP/磁力/ed2k，自动下载到本地） | “离线下载”页 | — |
| 自动备份（本地⇄云端双向，文件监听 + 定时轮询） | “自动备份”页 | 建议把监听目录放在 extroot，避免 FAT/NTFS 监听事件缺失 |
| 客户端侧加密（AES-256-GCM，下载自动解密） | “设置 → 加密” | 务必备份 `config/encryption.json` 与 `baidu-pcs.db` |
| Web 访问认证（密码 / TOTP 双因素） | “设置 → Web 认证” | `config/app.toml [web_auth]` |
| 消息通知（Gotify / Webhook） | “设置 → 消息通知” | `[notification]` |
| 网络代理（HTTP/SOCKS5、自动回退） | “设置 → 代理” | `[network.proxy]` |
| 资源配额/预算（多账号线程分配） | “设置 → 预算” | `[multi_account_budget]` |
| 独立解密 CLI（menuconfig 勾选后） | 终端：`decrypt-cli <参数>` | 密钥来自 `config/encryption.json` |

服务管理：

```sh
/etc/init.d/baidupcs-rust status     # procd 状态 + /health 健康检查
/etc/init.d/baidupcs-rust regenerate # 用 UCI 重建 app.toml（覆盖 Web 界面设置）
/etc/init.d/baidupcs-rust restart
```

> 配置优先级：**首次**由 UCI 生成 `config/app.toml`；之后 app.toml 为准
> （Web 界面会直接写回它，且大量运行时状态本就存在 SQLite/app.toml 中）。

## 4. 端口与网络配置

- `18888/tcp`（`[server] host/port`）：HTTP API + WebSocket + Web UI，
  同端口同源，无需额外 CORS/反代即可使用。
- 默认仅 LAN 可达（OpenWrt lan zone 默认放行 input）。WAN 暴露属于
  opt-in：`uci set baidupcs-rust.main.expose_wan=1` 后启动时自动创建
  firewall 规则 `baidupcs_wan_web`（不推荐；公网请配合 Web 认证/TOTP，
  并建议用 nginx/https 反代）。
- 下载走百度网盘 CDN 直连，无需在防火墙放行入站规则；程序出站访问
  `*.baidu.com`、CDN 域名即可。
- WebSocket 地址：`ws://<host>:18888/api/v1/ws`（实时任务进度）。

## 5. 交叉编译机制说明

- **默认（动态 musl）**：`PKG_BUILD_DEPENDS:=rust/host`（packages feed
  `lang/rust`）。目标三元组由固件工具链推导，例如
  `mipsel-openwrt-linux-musl → mipsel-unknown-linux-musl`、
  `aarch64 → aarch64-unknown-linux-musl`、ARM 依 v5te/v7 与 FPU 得到
  `musleabi/musleabihf` 变体；链接器指向 OpenWrt 交叉 GCC，产物动态链接
  固件 musl libc（`-crt-static`），体积小且与固件 ABI 完全一致。
- **可选全静态（crt-static）**：改用构建宿主 rustup 工具链（自动遵循上游
  `rust-toolchain.toml` 固定的 1.87.0），`rustup target add` 补齐目标 std，
  以 `+crt-static` 产出自包含二进制，不依赖固件 libc，可跨固件复用。
- 依赖注意：上游 reqwest 使用 **rustls + webpki-roots**（内置 CA），无
  OpenSSL 依赖、无需系统 ca-bundle；rusqlite 为 bundled（cc-rs 编译
  SQLite，Makefile 已注入交叉 CC/AR）；libc crate 提供 Unix 系统调用。

## 6. 已知限制与常见问题

限制：

1. **资源需求**：空闲内存 100–200 MB，下载峰值 200–500 MB；ipk 体积约
   10–20 MB（前端另计 ~2.3 MB）。适用于 256 MB+ 内存的路由器/软路由或
   extroot 方案；小闪存 16/32 MB 设备基本放不下。
2. **mips64**：ABI（n32/n64）与 rustc 目标命名存在历史差异，动态模式在
   mips64 上不可用；请启用全静态模式（或自行修正三元组为
   `mips64*-unknown-linux-muslabi64`）。
3. **时间显示**：如需本地时区时间，安装 `zoneinfo-*` 相关包并设置
   `/etc/TZ`。
4. **构建需网络**：cargo 按 Cargo.lock 拉取依赖；离线构建需自行
   `cargo vendor` 后挂 `.cargo/config.toml`（或利用新版 OpenWrt 的
   cargo-vendor 基建）。
5. 上游主要在 Windows/Docker 测试，Linux ARM/MIPS 属社区测试范围。

排查：

| 现象 | 处理 |
| --- | --- |
| 服务未启动 | `/etc/init.d/baidupcs-rust status`；`logread \| grep baidupcs` 查看日志 |
| Web 打不开 | 确认 `enabled=1`、端口 18888 未被占用（`netstat -ltnp`）；检查是否误改了 workdir 但未 `regenerate` |
| 启动即退出（下载目录无权限） | app.toml `[download] download_dir` 需可写；挂载的 FAT/NTFS 注意 umask |
| 登录后无法浏览 | 会话过期，重新扫码；代理设置错误时在“设置 → 代理”回退直连 |
| 下载慢/0 速度 | CDN 链接刷新机制会自动处理；检查路由器时间是否正确 |
| cargo 构建内存不足 | 关闭并行/加 swap；或临时调低 LTO |
| 前端 404/空白 | 未勾选“捆绑 Web UI”时需自行放置 frontend/ 资源 |

## 7. 与其他部署方式的对比

| 方式 | 优点 | 缺点 |
| --- | --- | --- |
| **本包（buildroot 集成）** | 与固件 ABI 一致、procd 守护开机自启、UCI 统一管理、可随固件镜像分发、hash 校验供应链安全 | 编译耗时长（首次需构建 Rust 工具链与依赖树）；需 packages feed；交叉编译环境搭建门槛 |
| **直接下载官方静态二进制** | 零编译、几分钟可用 | 官方 Release 仅提供 glibc 动态版（x86_64/arm64），在 musl 固件上需额外装 glibc 或兼容层；无 procd/UCI/LuCI 集成，升级手工；无哈希锁定 |
| **Docker**（上游官方推荐） | 环境隔离、升级方便 | 大多数路由器无 Docker；镜像 ~150 MB，内存/存储开销大 |
| **自行裸装** | 灵活 | 服务、日志、升级、备份等生命周期全部手工维护 |

适配的实际适用场景：把一台内存/存储宽裕的 OpenWrt 主机（软路由、
x86/nanopi 类设备、带 USB 硬盘的 NAS 路由器）变成常驻的网盘下载/备份
节点：白天自动备份家庭照片，夜间满速拉取分享资源，全部通过
procd + UCI + LuCI 纳管，随固件可复现地重建。
