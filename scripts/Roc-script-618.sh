#!/usr/bin/env bash
set -Eeuo pipefail

# 修改默认IP & 固件名称 & 编译署名和时间
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='Roc'/g" package/base-files/files/bin/config_generate
luci_system_js="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
firmware_version_anchor="_('Firmware Version'), (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || ''),"
grep -Fq "$firmware_version_anchor" "$luci_system_js" || { echo "Error: LuCI firmware version anchor was not found in $luci_system_js" >&2; exit 1; }
sed -i "s#_('Firmware Version'), (L\.isObject(boardinfo\.release) ? boardinfo\.release\.description + ' / ' : '') + (luciversion || ''),# \
            _('Firmware Version'),\n \
            E('span', {}, [\n \
                (L.isObject(boardinfo.release)\n \
                ? boardinfo.release.description + ' / '\n \
                : '') + (luciversion || '') + ' / ',\n \
            E('a', {\n \
                href: 'https://github.com/laipeng668/openwrt-ci-roc/releases',\n \
                target: '_blank',\n \
                rel: 'noopener noreferrer'\n \
                }, [ 'Built by Roc $(date "+%Y-%m-%d %H:%M:%S")' ])\n \
            ]),#" "$luci_system_js"

# 调整IPQ6018的NSS q6_region内存大小(VIKINGYFY默认64MB=0x4000000，改为96MB=0x06000000)
sed -i 's/reg = <0x0 0x4ab00000 0x0 0x4000000>/reg = <0x0 0x4ab00000 0x0 0x06000000>/' target/linux/qualcommax/patches-6.18/0103-arm64-dts-ipq6018-add-reserved-memory-nodes.patch

# 完全重写0131 patch以匹配upstream kernel 6.18的完整OPP表(8个频率项,含864/1056/1200/1320/1440/1512/1608/1800MHz)
# upstream DTS已有opp-supported-hw = <0xf>对864MHz/1056MHz,但1.2GHz+仍有受限的speed-bin mask
cat > target/linux/qualcommax/patches-6.18/0131-arm64-dts-qcom-ipq6018-change-CPU-OPP-table.patch << 'PATCH'
--- a/arch/arm64/boot/dts/qcom/ipq6018.dtsi
+++ b/arch/arm64/boot/dts/qcom/ipq6018.dtsi
@@ -118,7 +118,7 @@
 		opp-1200000000 {
 			opp-hz = /bits/ 64 <1200000000>;
 			opp-microvolt = <850000>;
-			opp-supported-hw = <0x4>;
+			opp-supported-hw = <0xf>;
 			clock-latency-ns = <200000>;
 		};
@@ -125,7 +125,7 @@
 		opp-1320000000 {
 			opp-hz = /bits/ 64 <1320000000>;
 			opp-microvolt = <862500>;
-			opp-supported-hw = <0x3>;
+			opp-supported-hw = <0xf>;
 			clock-latency-ns = <200000>;
 		};
@@ -132,7 +132,7 @@
 		opp-1440000000 {
 			opp-hz = /bits/ 64 <1440000000>;
 			opp-microvolt = <925000>;
-			opp-supported-hw = <0x3>;
+			opp-supported-hw = <0xf>;
 			clock-latency-ns = <200000>;
 		};
@@ -139,7 +139,7 @@
 		opp-1512000000 {
 			opp-hz = /bits/ 64 <1512000000>;
-			opp-microvolt = <937500>;
-			opp-supported-hw = <0x2>;
+			opp-microvolt = <950000>;
+			opp-supported-hw = <0xf>;
 			clock-latency-ns = <200000>;
 		};
@@ -146,7 +146,7 @@
 		opp-1608000000 {
 			opp-hz = /bits/ 64 <1608000000>;
 			opp-microvolt = <987500>;
-			opp-supported-hw = <0x1>;
+			opp-supported-hw = <0xf>;
 			clock-latency-ns = <200000>;
 		};
@@ -153,7 +153,7 @@
 		opp-1800000000 {
 			opp-hz = /bits/ 64 <1800000000>;
 			opp-microvolt = <1062500>;
-			opp-supported-hw = <0x1>;
+			opp-supported-hw = <0xf>;
 			clock-latency-ns = <200000>;
 		};
PATCH

# 清除内核构建缓存，强制重新应用修改后的 patch
rm -rf build_dir/target-*/linux-*

# 开启BBR拥塞控制算法及FQ队列(需内核支持，kernel 6.18已包含BBRv1)
sed -i 's/# CONFIG_TCP_CONG_BBR is not set/CONFIG_TCP_CONG_BBR=y/' target/linux/generic/config-6.18
sed -i 's/DEFAULT_TCP_CONG="cubic"/DEFAULT_TCP_CONG="bbr"/' target/linux/generic/config-6.18
sed -i 's/CONFIG_DEFAULT_CUBIC=y/# CONFIG_DEFAULT_CUBIC is not set/' target/linux/generic/config-6.18
sed -i '/^CONFIG_TCP_CONG_BBR=y/a CONFIG_DEFAULT_BBR=y' target/linux/generic/config-6.18
sed -i 's/# CONFIG_NET_SCH_FQ is not set/CONFIG_NET_SCH_FQ=y/' target/linux/generic/config-6.18

# 设置系统默认使用BBR
mkdir -p package/base-files/files/etc/sysctl.d
echo "net.core.default_qdisc=fq" >> package/base-files/files/etc/sysctl.d/bbr.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> package/base-files/files/etc/sysctl.d/bbr.conf
echo "net.ipv4.tcp_fastopen=3" >> package/base-files/files/etc/sysctl.d/bbr.conf

# 调整zram交换分区大小(默认公式ram_size/2048=934MB过大，改为256MB)
sed -i 's/echo $(( ram_size \/ 2048 ))/echo 256/' package/system/zram-swap/files/zram.init

# 移除要替换的包
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/luci/applications/luci-app-wechatpush
rm -rf feeds/luci/applications/luci-app-appfilter
rm -rf feeds/luci/applications/luci-app-frpc
rm -rf feeds/luci/applications/luci-app-frps
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/packages/net/open-app-filter
rm -rf feeds/packages/net/ariang
rm -rf feeds/packages/net/aria2
rm -rf feeds/packages/net/nginx
rm -rf feeds/packages/net/frp
rm -rf feeds/packages/lang/golang

# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
  local branch="$1"
  local repourl="$2"
  local repodir
  shift 2

  repodir="$(basename "${repourl%.git}")"
  rm -rf "$repodir"
  git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl" "$repodir"
  (
    cd "$repodir"
    git sparse-checkout set "$@"
    mv -f "$@" ../package
  )
  rm -rf "$repodir"
}

# Aria2 & nginx & Go & frp & Argon & OpenList & Lucky & wechatpush & OpenAppFilter & 集客无线AC控制器 & 雅典娜LED控制
git_sparse_clone aria2 https://github.com/laipeng668/packages net/aria2
mv -f package/aria2 feeds/packages/net/aria2
git_sparse_clone nginx https://github.com/laipeng668/packages net/nginx
mv -f package/nginx feeds/packages/net/nginx
git_sparse_clone ariang https://github.com/laipeng668/packages net/ariang
mv -f package/ariang feeds/packages/net/ariang
git_sparse_clone master https://github.com/laipeng668/packages lang/golang
mv -f package/golang feeds/packages/lang/golang
git_sparse_clone frp-binary-toml https://github.com/laipeng668/packages net/frp
mv -f package/frp feeds/packages/net/frp
git_sparse_clone frp-toml https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps
mv -f package/luci-app-frpc feeds/luci/applications/luci-app-frpc
mv -f package/luci-app-frps feeds/luci/applications/luci-app-frps
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon feeds/luci/themes/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config feeds/luci/applications/luci-app-argon-config
git clone --depth=1 https://github.com/laipeng668/luci-app-openlist2 package/openlist2
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git clone --depth=1 https://github.com/tty228/luci-app-wechatpush package/luci-app-wechatpush
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter
git clone --depth=1 https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led

### PassWall & OpenClash ###

# 移除 OpenWrt Feeds 自带的核心库
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages

# 移除 OpenWrt Feeds 过时的LuCI版本
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-openclash
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2 package/luci-app-passwall2
git clone --depth=1 https://github.com/vernesong/OpenClash package/luci-app-openclash
./scripts/feeds update -a
./scripts/feeds install -a
