# SPDX-License-Identifier: Apache-2.0
#
# Copyright (C) 2026 BaiduPCS-Rust OpenWrt packaging contributors
#
# OpenWrt 软件包：BaiduPCS-Rust（百度网盘第三方客户端，Rust + Vue 3）
# 上游仓库：https://github.com/komorebiCarry/BaiduPCS-Rust
#
# 设计要点：
#  * 源码取自 GitHub tag 归档（codeload），哈希已在本地校验；
#  * Web 前端（Vue 3 已构建产物，约 2.3 MB，架构无关）取自上游 Release 中的
#    linux-x86_64 发行包，作为第二个 Download 源，仅在启用
#    CONFIG_BAIDUPCS_RUST_FRONTEND 时下载/解包/安装；
#  * 后端通过 cargo 交叉编译：目标三元组由 OpenWrt 工具链推导（覆盖
#    mips/mipsel/arm/aarch64/x86_64/riscv64/powerpc 等），默认与固件工具链
#    动态链接 musl（依赖 rust/host 工具链包）；可选
#    CONFIG_BAIDUPCS_RUST_STATIC_MUSL 切换为 crt-static 全静态 musl 构建
#    （使用构建宿主上的 rustup 工具链，产物不依赖固件 libc）；
#  * 可执行文件安装到 /usr/bin，运行时资源安装到可配置的工作目录
#    （CONFIG_BAIDUPCS_RUST_WORKDIR，默认 /opt/baidupcs-rust）。

include $(TOPDIR)/rules.mk

PKG_NAME:=baidupcs-rust
PKG_VERSION:=2.4.1
PKG_RELEASE:=1

# ---------------------------------------------------------------------------
# 源码下载：GitHub tag 归档
# download.pl 会把 PKG_SOURCE_URL_FILE 追加到 URL 之后，落盘文件名为 PKG_SOURCE
# ---------------------------------------------------------------------------
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/komorebiCarry/BaiduPCS-Rust/tar.gz
PKG_SOURCE_URL_FILE:=v$(PKG_VERSION)
PKG_HASH:=f839e0035024ffd99100d2a68ce51ca09ec708b06bcaa6642f557aff8dd064ef

# 源码包内顶层目录为 BaiduPCS-Rust-$(PKG_VERSION)，与默认 PKG_BUILD_DIR 不一致，
# 这里显式对齐（解包时 tar 会按归档内顶层目录落到该路径）。
PKG_BUILD_DIR:=$(BUILD_DIR)/BaiduPCS-Rust-$(PKG_VERSION)

PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=BaiduPCS-Rust OpenWrt packaging contributors <you@example.com>
PKG_URL:=https://github.com/komorebiCarry/BaiduPCS-Rust

PKG_CONFIG_DEPENDS:= \
	CONFIG_BAIDUPCS_RUST_FRONTEND \
	CONFIG_BAIDUPCS_RUST_STATIC_MUSL \
	CONFIG_BAIDUPCS_RUST_DECRYPT_CLI \
	CONFIG_BAIDUPCS_RUST_WORKDIR

# 准备阶段产物依赖上述配置项（切换选项后自动重新 Prepare）
PKG_PREPARED_DEPENDS+=CONFIG_BAIDUPCS_RUST_FRONTEND CONFIG_BAIDUPCS_RUST_STATIC_MUSL CONFIG_BAIDUPCS_RUST_DECRYPT_CLI

# 默认（动态链接）模式需要 OpenWrt 集成 Rust 工具链：
# 位于 packages feed 的 lang/rust（提供 rust/host）。
# 若启用 CONFIG_BAIDUPCS_RUST_STATIC_MUSL，可注释掉下一行以跳过该工具链构建。
PKG_BUILD_DEPENDS:=rust/host

# Rust 不支持 mips16 指令集
PKG_BUILD_FLAGS:=no-mips16

# 让 cargo 使用构建系统 jobserver 并行
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

# ---------------------------------------------------------------------------
# 第二源文件：上游 Release 中已构建的 Web 前端（架构无关）
# （frontend/ 内为 dist 内容：index.html + assets/，与二进制的探测路径兼容）
# ---------------------------------------------------------------------------
PKG_RELEASE_URL:=https://github.com/komorebiCarry/BaiduPCS-Rust/releases/download/v$(PKG_VERSION)
FRONTEND_FILE:=BaiduPCS-Rust-v$(PKG_VERSION)-linux-x86_64.tar.gz
FRONTEND_HASH:=7cab3ff52e443371d0747f6853bee298252d2501b02abaa945b501b7a962cfe4

ifneq ($(CONFIG_BAIDUPCS_RUST_FRONTEND),)
define Download/frontend
  FILE:=$(FRONTEND_FILE)
  URL:=$(PKG_RELEASE_URL)
  URL_FILE:=$(FRONTEND_FILE)
  HASH:=$(FRONTEND_HASH)
endef
$(eval $(call Download,frontend))
endif

# ---------------------------------------------------------------------------
# Rust 交叉编译配置（自包含，改编自 packages feed lang/rust/rust-values.mk）
# ---------------------------------------------------------------------------
unexport RUSTC_WRAPPER

RUSTC_HOST_SUFFIX:=$(word 4, $(subst -, ,$(GNU_HOST_NAME)))
RUSTC_HOST_ARCH:=$(HOST_ARCH)-unknown-linux-$(RUSTC_HOST_SUFFIX)
CARGO_HOME:=$(DL_DIR)/cargo

# musl 固件开启栈保护时，链接 SQLite(cc-rs) 产物需要 ssp_nonshared
ifeq ($(CONFIG_USE_MUSL),y)
  ifdef CONFIG_PKG_CC_STACKPROTECTOR_REGULAR
    ifeq ($(strip $(PKG_SSP)),1)
      RUSTC_LDFLAGS+=-lssp_nonshared
    endif
  endif
  ifdef CONFIG_PKG_CC_STACKPROTECTOR_STRONG
    ifeq ($(strip $(PKG_SSP)),1)
      RUSTC_LDFLAGS+=-lssp_nonshared
    endif
  endif
endif

CARGO_RUSTFLAGS+=-Ctarget-feature=-crt-static $(RUSTC_LDFLAGS)

ifeq ($(HOST_OS),Darwin)
  ifeq ($(HOST_ARCH),arm64)
    RUSTC_HOST_ARCH:=aarch64-apple-darwin
  else ifeq ($(HOST_ARCH),x86_64)
    RUSTC_HOST_ARCH:=x86_64-apple-darwin
  endif
endif

# 目标三元组推导（与固件工具链一一对应）：
#   mips/mipsel/arm/aarch64/x86_64/i386/riscv64/powerpc ...
# 例如 mipsel-openwrt-linux-musl -> mipsel-unknown-linux-musl
ifeq ($(ARCH),mips64)
  # mips64 的 ABI（n32/n64）与 rustc 目标命名存在差异，见 README“已知限制”
  RUSTC_TARGET_ARCH:=$(REAL_GNU_TARGET_NAME)
else
  RUSTC_TARGET_ARCH:=$(subst openwrt,unknown,$(REAL_GNU_TARGET_NAME))
endif
RUSTC_TARGET_ARCH:=$(subst muslgnueabi,musleabi,$(RUSTC_TARGET_ARCH))

ifeq ($(ARCH),i386)
  RUSTC_TARGET_ARCH:=$(subst i486,i586,$(RUSTC_TARGET_ARCH))
else ifeq ($(ARCH),riscv64)
  RUSTC_TARGET_ARCH:=$(subst riscv64,riscv64gc,$(RUSTC_TARGET_ARCH))
endif

ifeq ($(ARCH),arm)
  ifeq ($(CONFIG_arm_v6)$(CONFIG_arm_v7),)
    RUSTC_TARGET_ARCH:=$(subst arm,armv5te,$(RUSTC_TARGET_ARCH))
  else ifeq ($(CONFIG_arm_v7),y)
    RUSTC_TARGET_ARCH:=$(subst arm,armv7,$(RUSTC_TARGET_ARCH))
  endif
  ifeq ($(CONFIG_HAS_FPU),y)
    RUSTC_TARGET_ARCH:=$(subst musleabi,musleabihf,$(RUSTC_TARGET_ARCH))
    RUSTC_TARGET_ARCH:=$(subst gnueabi,gnueabihf,$(RUSTC_TARGET_ARCH))
  endif
endif

# 32 位 powerpc 软浮点子目标（与 packages feed lang/rust 保持一致）
ifeq ($(ARCH),powerpc)
  ifeq ($(CONFIG_SOFT_FLOAT),y)
    RUSTC_TARGET_RUSTFLAGS+=-Ctarget-feature=-hard-float
  endif
endif

RUSTC_TARGET_UPPER:=$(subst -,_,$(call toupper,$(RUSTC_TARGET_ARCH)))

# 全静态 musl 模式（crt-static）：使用构建宿主的 rustup 工具链（自包含 musl）
ifeq ($(CONFIG_BAIDUPCS_RUST_STATIC_MUSL),y)
  CARGO_STATIC_BIN?=$${HOME}/.cargo/bin/cargo
  RUSTUP_BIN?=$${HOME}/.cargo/bin/rustup
  CARGO_STATIC_RUSTFLAGS:=-Ctarget-feature=+crt-static $(RUSTC_TARGET_RUSTFLAGS)
endif

# 体积/内存优化（路由器友好）；CONFIG_DEBUG=y 时改用 dev profile
CARGO_PROFILE:=$(if $(CONFIG_DEBUG),dev,release)

CARGO_PROFILE_VARS:= \
	CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 \
	CARGO_PROFILE_RELEASE_DEBUG=false \
	CARGO_PROFILE_RELEASE_DEBUG_ASSERTIONS=false \
	CARGO_PROFILE_RELEASE_LTO=true \
	CARGO_PROFILE_RELEASE_OPT_LEVEL=z \
	CARGO_PROFILE_RELEASE_OVERFLOW_CHECKS=true \
	CARGO_PROFILE_RELEASE_PANIC=unwind \
	CARGO_PROFILE_RELEASE_RPATH=false

# cc-rs（rusqlite bundled 的 SQLite）按目标编译需要交叉 CC
CARGO_CC_VARS:= \
	TARGET_CC=$(TARGET_CC_NOCACHE) \
	TARGET_CFLAGS="$(TARGET_CFLAGS)" \
	CC_$(RUSTC_TARGET_UPPER)=$(TARGET_CC_NOCACHE) \
	CFLAGS_$(RUSTC_TARGET_UPPER)="$(TARGET_CFLAGS)" \
	AR_$(RUSTC_TARGET_UPPER)=$(TARGET_AR) \
	CC=$(HOSTCC_NOCACHE)

# 动态链接模式：用 OpenWrt 工具链链接
CARGO_DYNAMIC_VARS:= \
	$(CARGO_CC_VARS) \
	CARGO_TARGET_$(RUSTC_TARGET_UPPER)_LINKER=$(TARGET_CC_NOCACHE) \
	RUSTFLAGS="$(CARGO_RUSTFLAGS) $(RUSTC_TARGET_RUSTFLAGS)" \
	LDFLAGS="$(RUSTC_LDFLAGS)"

# 静态链接模式：rust-lld 自包含链接，仅注入 +crt-static（严格限定目标三元组）
CARGO_STATIC_VARS:= \
	$(CARGO_CC_VARS) \
	CARGO_TARGET_$(RUSTC_TARGET_UPPER)_RUSTFLAGS="$(CARGO_STATIC_RUSTFLAGS)"

CARGO_INSTALL_VARS:= \
	$(CARGO_PROFILE_VARS) \
	MAKEFLAGS="$(PKG_JOBS)" \
	CARGO_HOME=$(CARGO_HOME)

# $(1): cargo 二进制路径
# $(2): 注入的环境变量
# $(3): 待编译 crate 相对于 PKG_BUILD_DIR 的路径
define Build/Compile/Crate
	+$(CARGO_INSTALL_VARS) $(2) \
	$(1) install -v \
		--locked \
		--target $(RUSTC_TARGET_ARCH) \
		--profile $(CARGO_PROFILE) \
		--root $(PKG_INSTALL_DIR) \
		--path "$(PKG_BUILD_DIR)/$(3)" \
		$(if $(filter --jobserver%,$(PKG_JOBS)),,-j1)
endef

# 静态/动态模式选择必须放在 define 之外（make 条件指令不能出现在
# Build/Compile 这类会被展开进 recipe 的 define 内部，否则行首会被
# 附加 tab，导致 ifneq 变成 shell 行，进而报 "extraneous else"）。
ifeq ($(CONFIG_BAIDUPCS_RUST_STATIC_MUSL),y)
  BAIDUPCS_CARGO_BIN:=$(CARGO_STATIC_BIN)
  BAIDUPCS_CARGO_VARS:=$(CARGO_STATIC_VARS)
else
  BAIDUPCS_CARGO_BIN:=$(STAGING_DIR_HOST)/bin/cargo
  BAIDUPCS_CARGO_VARS:=$(CARGO_DYNAMIC_VARS)
endif

define Build/Compile/StaticPrep
	+test -x "$(CARGO_STATIC_BIN)" || { \
		echo "ERROR: 启用 CONFIG_BAIDUPCS_RUST_STATIC_MUSL 需要在构建宿主上安装 rustup 工具链"; \
		echo "       (curl https://sh.rustup.rs -sSf | sh)，详见包内 README.md"; exit 1; }; \
	( cd $(PKG_BUILD_DIR)/backend && $(RUSTUP_BIN) target add $(RUSTC_TARGET_ARCH) ) || true
endef

define Build/Compile
	$(if $(filter y,$(CONFIG_BAIDUPCS_RUST_STATIC_MUSL)),$(call Build/Compile/StaticPrep))
	$(call Build/Compile/Crate,$(BAIDUPCS_CARGO_BIN),$(BAIDUPCS_CARGO_VARS),backend)
	$(if $(filter y,$(CONFIG_BAIDUPCS_RUST_DECRYPT_CLI)),$(call Build/Compile/Crate,$(BAIDUPCS_CARGO_BIN),$(BAIDUPCS_CARGO_VARS),decrypt-cli))
endef

# ---------------------------------------------------------------------------
# 准备阶段：解包源码 +（可选）解包 Web 前端资源
# ---------------------------------------------------------------------------
define Build/Prepare
	$(call Build/Prepare/Default)
ifneq ($(CONFIG_BAIDUPCS_RUST_FRONTEND),)
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/frontend
	$(TAR) -C $(PKG_BUILD_DIR)/frontend --strip-components=2 -xzf $(DL_DIR)/$(FRONTEND_FILE) \
		'BaiduPCS-Rust-v$(PKG_VERSION)-linux-x86_64/frontend'
endif
endef

BAIDUPCS_WORKDIR:=$(if $(call qstrip,$(CONFIG_BAIDUPCS_RUST_WORKDIR)),$(call qstrip,$(CONFIG_BAIDUPCS_RUST_WORKDIR)),/opt/baidupcs-rust)

# ---------------------------------------------------------------------------
# 包定义
# ---------------------------------------------------------------------------
define Package/baidupcs-rust
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=File Transfer
  TITLE:=BaiduPCS-Rust: web client for Baidu Netdisk
  URL:=$(PKG_URL)
  # 与 packages feed lang/rust 支持的架构列表一致
  DEPENDS:=@(aarch64||arm||i386||loongarch64||mips||mips64||mips64el||mipsel||powerpc||powerpc64||riscv64||x86_64) @!USE_RUST_TOOLCHAIN
endef

define Package/baidupcs-rust/description
  BaiduPCS-Rust 是一个使用 Rust + Vue 3 构建的百度网盘第三方客户端，提供
  多线程下载、多账号管理、自动备份、分享同步、离线下载、客户端侧加密，
  并内置 Web 管理界面（默认端口 18888）与访问密码/TOTP 双因素认证。
  本包将后端安装为 /usr/bin/baidu-netdisk-rust，通过 procd 托管、
  开机自启；运行时数据（config/ db wal logs downloads）位于工作目录
  （默认 $(BAIDUPCS_WORKDIR)，可在 menuconfig 或 UCI 中修改）。
endef

define Package/baidupcs-rust/config
	source "$(SOURCE)/Config.in"
endef

define Package/baidupcs-rust/conffiles
/etc/config/baidupcs-rust
endef

define Package/baidupcs-rust/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/bin/baidu-netdisk-rust $(1)/usr/bin/
ifneq ($(CONFIG_BAIDUPCS_RUST_DECRYPT_CLI),)
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/bin/decrypt-cli $(1)/usr/bin/
endif
ifneq ($(CONFIG_BAIDUPCS_RUST_FRONTEND),)
	$(INSTALL_DIR) $(BAIDUPCS_WORKDIR)/frontend
	$(CP) $(PKG_BUILD_DIR)/frontend/. $(BAIDUPCS_WORKDIR)/frontend/
endif
	$(INSTALL_DIR) $(1)/etc/init.d $(1)/etc/config
	$(INSTALL_BIN) ./files/baidupcs-rust.init $(1)/etc/init.d/baidupcs-rust
	$(INSTALL_CONF) ./files/baidupcs-rust.conf $(1)/etc/config/baidupcs-rust
endef

# 可选 LuCI 集成页（菜单 + 内嵌 Web UI 的客户端视图），单独成包，
# 在 menuconfig 的 LuCI -> Applications 中选择
define Package/luci-app-baidupcs-rust
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI page for BaiduPCS-Rust
  URL:=$(PKG_URL)
  DEPENDS:=+baidupcs-rust +luci-base
  PKGARCH:=all
endef

define Package/luci-app-baidupcs-rust/description
  在 LuCI “服务”菜单中提供 BaiduPCS-Rust 页面：内嵌显示其 Web 管理界面
  （iframe），并提供服务状态快捷入口。实际的功能配置仍在
  BaiduPCS-Rust 自带 Web UI 中完成。
endef

define Package/luci-app-baidupcs-rust/install
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./files/luci-app/menu.d/luci-app-baidupcs-rust.json \
		$(1)/usr/share/luci/menu.d/luci-app-baidupcs-rust.json
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/baidupcs-rust
	$(INSTALL_DATA) ./files/luci-app/htdocs/luci-static/resources/view/baidupcs-rust/page.js \
		$(1)/www/luci-static/resources/view/baidupcs-rust/page.js
endef

define Package/luci-app-baidupcs-rust/postinst
[ -n "$${IPKG_INSTROOT}" ] || { \
	rm -f /tmp/luci-indexcache-* /tmp/luci-indexcache.*; \
	/etc/init.d/rpcd reload 2>/dev/null; \
	exit 0; \
}
endef

$(eval $(call BuildPackage,baidupcs-rust))
$(eval $(call BuildPackage,luci-app-baidupcs-rust))
