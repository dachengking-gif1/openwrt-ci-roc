#!/usr/bin/env bash
set -euo pipefail

# 清除 Windows/MSYS 路径泄漏，避免 find -execdir 安全检查失败
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ==============================
#   基本路径（请自行确认）
# ==============================
# 项目根目录（你的 openwrt-ci-roc-master）
PROJECT_ROOT="/mnt/c/Users/king/Desktop/Hermes/openwrt-ci-roc-master"

# 本地克隆的 openwrt-6.x（25.12-nss）源码目录（WSL 本地 ext4 文件系统）
OPENWRT_ROOT="/home/king/openwrt-build/openwrt-6.x"

# ==============================
#   1️⃣ 先准备编译依赖（只需执行一次）
# ==============================
if ! command -v make >/dev/null 2>&1; then
  echo "=== 编译工具链已准备（跳过 apt-get） ==="
fi

# ==============================
#   2️⃣ 克隆 openwrt-6.x（25.12‑nss）分支
# ==============================
if [ -d "$OPENWRT_ROOT/.git" ]; then
  echo "=== 已存在源码，跳过更新 ==="
  cd "$OPENWRT_ROOT"
else
  echo "=== 正在克隆 openwrt-6.x 25.12‑nss 分支 ==="
  git clone --depth 1 -b 25.12-nss \
    https://github.com/laipeng668/openwrt-6.x.git "$OPENWRT_ROOT"
fi

cd "$OPENWRT_ROOT"

# ==============================
#   3️⃣ 安装 OpenWrt feeds（插件、包）
# ==============================
echo "=== 更新 & 安装 feeds ==="
./scripts/feeds update -a
./scripts/feeds install -a

# ==============================
#   4️⃣ 运行项目自带的 Roc-script.sh（加载自定义 UCI-defaults、稀疏克隆第三方包）
# ==============================
if [ -x "$PROJECT_ROOT/scripts/Roc-script.sh" ]; then
  echo "=== 执行 Roc-script.sh（加载自定义 UCI-defaults、稀疏克隆第三方包） ==="
  "$PROJECT_ROOT/scripts/Roc-script.sh"
else
  echo "⚠️ Roc-script.sh 未找到或不可执行，跳过此步。"
fi

# ==============================
# 5️⃣ 合并项目配置文件（必须在 feeds + Roc-script 之后，否则第三方包不会被识别）
# ==============================
echo "=== 合并项目专属配置 ==="
cat "$PROJECT_ROOT/configs/IPQ60XX.config"   > .config
cat "$PROJECT_ROOT/configs/General.config"  >> .config
cat "$PROJECT_ROOT/configs/Packages.config" >> .config

# Docker 相关配置（如果 Packages.config 中启用了 Docker）
if grep -q '^CONFIG_PACKAGE_docker=y' "$PROJECT_ROOT/configs/Packages.config" 2>/dev/null; then
  echo "=== 启用 Docker 内核支持 ==="
  cat >> .config << 'EOF'
# Docker 内核依赖 (OpenWrt 使用 CONFIG_KERNEL_ 前缀)
CONFIG_KERNEL_CGROUPS=y
CONFIG_KERNEL_CGROUP_DEVICE=y
CONFIG_KERNEL_CGROUP_FREEZER=y
CONFIG_KERNEL_CGROUP_NET_PRIO=y
CONFIG_KERNEL_CGROUP_PERF=y
CONFIG_KERNEL_CGROUP_SCHED=y
CONFIG_KERNEL_MEMCG=y
CONFIG_KERNEL_MEMCG_SWAP=y
CONFIG_KERNEL_VETH=y
CONFIG_KERNEL_BRIDGE=y
CONFIG_KERNEL_BRIDGE_IGMP_SNOOPING=y
CONFIG_KERNEL_BRIDGE_VLAN_FILTERING=y
CONFIG_KERNEL_NF_TABLES=y
CONFIG_KERNEL_NF_TABLES_BRIDGE=y
CONFIG_KERNEL_NF_TABLES_INET=y
CONFIG_KERNEL_NF_TABLES_IPV4=y
CONFIG_KERNEL_NF_TABLES_IPV6=y
CONFIG_KERNEL_NF_TABLES_NETDEV=y
CONFIG_KERNEL_NF_TABLES_ARP=y
CONFIG_KERNEL_SECCOMP_FILTER=y
CONFIG_KERNEL_OVERLAY_FS=y
CONFIG_KERNEL_OVERLAY_FS_REDIRECT_ALWAYS_FOLLOW=y
CONFIG_KERNEL_OVERLAY_FS_XINO_AUTO=y
EOF
fi

# ==============================
# 6️⃣ 生成完整 .config 并检查关键宏
# ==============================
echo "=== 运行 make defconfig ==="
make defconfig

echo "=== 检查关键选项是否已打开 ==="
if grep -qE "CONFIG_ECM_NSS_IPV[46]|CONFIG_PACKAGE_kmod-qca-nss-ecm" .config; then
  echo "✅ NSS ECM 相关选项已启用"
else
  echo "⚠️ 未检测到显式 ECM_NSS 选项（此分支可能默认集成），继续编译..."
fi

# ==============================
# 7️⃣ 添加 Docker 内核依赖（在 defconfig 之后，避免被覆盖）
# ==============================
if grep -q '^CONFIG_PACKAGE_docker=y' .config 2>/dev/null; then
  echo "=== 添加 Docker 内核依赖 ==="
  # VETH 在 generic 内核中默认禁用，需要手动启用
  sed -i 's/# CONFIG_VETH is not set/CONFIG_VETH=y/' target/linux/generic/config-6.12 2>/dev/null || true
  # 确保这些选项在 .config 中
  for opt in CONFIG_VETH=y CONFIG_BRIDGE=y CONFIG_BRIDGE_IGMP_SNOOPING=y CONFIG_BRIDGE_VLAN_FILTERING=y CONFIG_NF_TABLES_ARP=y CONFIG_NF_TABLES_BRIDGE=y CONFIG_NF_TABLES_INET=y CONFIG_NF_TABLES_IPV4=y CONFIG_NF_TABLES_IPV6=y CONFIG_NF_TABLES_NETDEV=y CONFIG_OVERLAY_FS=y CONFIG_OVERLAY_FS_REDIRECT_ALWAYS_FOLLOW=y CONFIG_OVERLAY_FS_XINO_AUTO=y; do
    opt_name="${opt%=*}"
    if ! grep -q "^$opt_name=" .config; then
      echo "$opt" >> .config
    fi
  done
  echo "✅ Docker 内核依赖已添加"
fi

# ==============================
#   7️⃣ 下载源码包（后续编译不会再联网）
# ==============================
echo "=== 下载源码包（make download）=== "
make download -j$(nproc)

# ==============================
#   8️⃣ 开始编译（全程日志保存在 build.log）
# ==============================
echo "=== 开始编译，请耐心等待（30‑90 分钟）=== "
time make -j8 V=s 2>&1 | tee build.log

# ==============================
#   9️⃣ 编译完成，列出产出固件路径
# ==============================
echo "=== 编译完成！固件位于： ==="
find bin/targets -type f -name "*sysupgrade.bin" -print

# 提示用户后续刷机验证
cat <<'EOF'

✅ 编译成功 🎉
请把上一步列出的 *.sysupgrade.bin 文件通过 scp/rsync 或 Web UI 上传到 JDCloud RE‑SS‑01
并使用 `sysupgrade -n <file>` 刷入。刷机后可在路由器上执行：

  cat /sys/kernel/debug/ecm/ecm_nss_ipv4/enabled
  cat /sys/kernel/debug/ecm/ecm_nss_ipv6/enabled

两个文件均应返回 `1`，此时 IPv4/IPv6 NSS 加速已生效。

如有任何编译错误，请把 `build.log`（已在当前目录下）贴给我，我会帮助定位。
EOF