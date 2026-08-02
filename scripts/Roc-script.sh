#!/usr/bin/env bash
set -Eeuo pipefail

# 修改默认IP & 固件名称 & 编译署名和时间
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='Roc'/g" package/base-files/files/bin/config_generate

# 调整NSS驱动q6_region内存区域预留大小（ipq6018.dtsi默认预留85MB，ipq6018-512m.dtsi默认预留55MB，带WiFi必须至少预留54MB，以下分别是改成预留16MB、32MB、64MB和96MB）
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x01000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x02000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x04000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x06000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi

# 解除IPQ60XX 1.5GHz的硬件限制
sed -i 's/opp-supported-hw = <0x2>;/opp-supported-hw = <0xffffffff>;/' target/linux/qualcommax/patches-6.12/0038-v6.16-arm64-dts-qcom-ipq6018-add-1.5GHz-CPU-Frequency.patch
# 调节IPQ60XX的1.5GHz频率电压(从0.9375V提高到0.95V，过低可能导致不稳定，过高可能增加功耗和发热，具体数值需要根据实际情况调整)
#  sed -i 's/opp-microvolt = <937500>;/opp-microvolt = <950000>;/' target/linux/qualcommax/patches-6.12/0038-v6.16-arm64-dts-qcom-ipq6018-add-1.5GHz-CPU-Frequency.patch

# 移除要替换的包
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/luci/applications/luci-app-wechatpush
rm -rf feeds/luci/applications/luci-app-appfilter
rm -rf feeds/luci/applications/luci-app-ddns
rm -rf feeds/luci/applications/luci-app-frpc
rm -rf feeds/luci/applications/luci-app-frps
rm -rf feeds/luci/applications/luci-app-upnp
rm -rf feeds/luci/applications/luci-app-wol
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/packages/net/open-app-filter
rm -rf feeds/packages/net/ddns-scripts
rm -rf feeds/packages/net/miniupnpd
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
    for dir in "$@"; do
      mv -f "$dir" "../package/$(basename "$dir")"
    done
  )
  rm -rf "$repodir"
}

# Nginx & Go & DDNS & frp & UPnP & Wol & Argon & OpenList & Lucky & wechatpush & OpenAppFilter & 集客无线AC控制器 & 雅典娜LED控制
git_sparse_clone nginx https://github.com/laipeng668/packages net/nginx
mv -f package/nginx feeds/packages/net/nginx
git_sparse_clone master https://github.com/laipeng668/packages lang/golang
mv -f package/golang feeds/packages/lang/golang
git_sparse_clone master https://github.com/laipeng668/packages net/ddns-scripts
mv -f package/ddns-scripts feeds/packages/net/ddns-scripts
git_sparse_clone master https://github.com/laipeng668/luci applications/luci-app-ddns
mv -f package/luci-app-ddns feeds/luci/applications/luci-app-ddns
git_sparse_clone frp-binary-toml https://github.com/laipeng668/packages net/frp
mv -f package/frp feeds/packages/net/frp
git_sparse_clone frp-toml https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps
mv -f package/luci-app-frpc feeds/luci/applications/luci-app-frpc
mv -f package/luci-app-frps feeds/luci/applications/luci-app-frps
git_sparse_clone master https://github.com/immortalwrt/packages net/miniupnpd
mv -f package/miniupnpd feeds/packages/net/miniupnpd
git_sparse_clone master https://github.com/immortalwrt/luci applications/luci-app-upnp
mv -f package/luci-app-upnp feeds/luci/applications/luci-app-upnp
git_sparse_clone master https://github.com/immortalwrt/luci applications/luci-app-wol
mv -f package/luci-app-wol feeds/luci/applications/luci-app-wol
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon feeds/luci/themes/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config feeds/luci/applications/luci-app-argon-config
git clone --depth=1 https://github.com/laipeng668/luci-app-openlist2 package/openlist2
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git clone --depth=1 https://github.com/tty228/luci-app-wechatpush package/luci-app-wechatpush
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter
git clone --depth=1 https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led

### PassWall2 ###

# 移除 OpenWrt Feeds 自带的核心库
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages

# 移除 OpenWrt Feeds 过时的LuCI版本
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-passwall2
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2 package/luci-app-passwall2

./scripts/feeds update -i -a
./scripts/feeds install -a

# 调整 cpufreq 启动优先级为 95
sed -i 's/^START=15$/START=95/' package/emortal/cpufreq/files/cpufreq.init

# 固件版本信息（在 feeds install 之后执行，避免被 feeds 重新注册覆盖）
luci_system_js="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
firmware_version_anchor="_('Firmware Version'), (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || ''),"
grep -Fq "$firmware_version_anchor" "$luci_system_js" || { echo "Error: LuCI firmware version anchor was not found in $luci_system_js" >&2; exit 1; }
sed -i "s#_('Firmware Version'), (L\\.isObject(boardinfo\\.release) ? boardinfo\\.release\\.description + ' / ' : '') + (luciversion || ''),# \
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

# ============================================================
# 首次启动配置（必须在 feeds install 之后，否则会被覆盖）
# ============================================================

### 系统优化 ###

# 内核启用 TCP BBR 支持，并设为默认算法，同时添加 FQ qdisc 支持
grep -qF 'CONFIG_TCP_CONG_BBR=y' target/linux/qualcommax/ipq60xx/config-default || \
  echo -e "CONFIG_TCP_CONG_BBR=y\nCONFIG_DEFAULT_BBR=y\nCONFIG_DEFAULT_TCP_CONG=\"bbr\"\nCONFIG_NET_SCH_FQ=y" >> target/linux/qualcommax/ipq60xx/config-default

# TCP BBR + 降低 swappiness
mkdir -p package/base-files/files/etc
grep -qF "net.ipv4.tcp_congestion_control=bbr" package/base-files/files/etc/sysctl.conf 2>/dev/null || cat >> package/base-files/files/etc/sysctl.conf << 'EOF'

# 系统优化
net.ipv4.tcp_congestion_control=bbr
vm.swappiness=10
net.core.default_qdisc=fq
EOF

# NSS 专用 sysctl 优化（TCP/UDP 缓冲区 + 内存保留 + VM 回收策略）
cat > package/base-files/files/etc/sysctl.d/90-nss-optimization.conf << 'EOF'
vm.min_free_kbytes=32768
vm.vfs_cache_pressure=50
vm.dirty_ratio=20
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.netdev_budget=600
net.netfilter.nf_conntrack_max=65535
EOF

# 默认 PPPoE 拨号配置
cat > package/base-files/files/etc/uci-defaults/97-pppoe-config << 'EOF'
#!/bin/sh

uci set network.wan.proto='pppoe'
uci set network.wan.username='15013389968@139.gd'
uci set network.wan.password='389968'
uci set network.wan.ipv6='auto'

uci commit network
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/97-pppoe-config

# 默认 WiFi SSID 和密码（config_generate 生成后覆盖）
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/98-wifi-config << 'EOF'
#!/bin/sh

# radio0 = 5G, radio1 = 2.4G
uci set wireless.default_radio0.ssid='AP_5G'
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.default_radio0.key='a1b2c3d4'

uci set wireless.default_radio1.ssid='AP'
uci set wireless.default_radio1.encryption='psk2'
uci set wireless.default_radio1.key='a1b2c3d4'

uci commit wireless
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/98-wifi-config

# 无线稳定性参数（ath11k/QCN9074 兼容性加固）
cat > package/base-files/files/etc/uci-defaults/98-wifi-stability << 'EOF'
#!/bin/sh

for radio in radio0 radio1; do
  uci set wireless.${radio}.disassoc_low_ack='0'
  uci set wireless.${radio}.skip_inactivity_poll='1'
  uci set wireless.${radio}.max_inactivity='300'
  uci set wireless.${radio}.ieee80211w='1'
  uci set wireless.${radio}.mobility_domain='1234'
  uci set wireless.${radio}.ft_over_ds='1'
  uci set wireless.${radio}.ft_psk_generate_local='1'
  uci set wireless.${radio}.he_bss_color='1'
  uci set wireless.${radio}.he_bss_color_disabled='0'
done

uci commit wireless
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/98-wifi-stability

cat > package/base-files/files/etc/uci-defaults/99-nss-optimize << 'EOF'
#!/bin/sh

# 防火墙 Flow Offloading（FW3/FW4 通用 uci 接口）
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='1'

# PassWall2 使用 nftables 模式（FW4），首次启动时 config 可能尚未创建
uci -q get passwall2.@global_forwarding[0] >/dev/null 2>&1 || \
  uci -q add passwall2 global_forwarding >/dev/null 2>&1 || true
uci set passwall2.@global_forwarding[0].prefer_nft='1'

# 激活 ECM NSS 连接卸载
if command -v uci >/dev/null 2>&1 && uci get ecm.@ecm[0].enable_ecm >/dev/null 2>&1; then
  uci set ecm.global.acceleration_engine='nss'
  uci set ecm.@ecm[0].enable_ecm=1
  uci set ecm.@ecm[0].enable_nss=1
  uci set ecm.@ecm[0].enable_tcp=1
  uci set ecm.@ecm[0].enable_udp=1
fi

# IRQ 均衡：启用 irqbalance 服务（动态调整中断分配）
uci -q set irqbalance.@irqbalance[0].enabled='1' 2>/dev/null || \
  { uci -q add irqbalance irqbalance >/dev/null 2>&1; uci -q set irqbalance.@irqbalance[0].enabled='1'; }
uci commit irqbalance 2>/dev/null || true

uci commit firewall
uci commit ecm 2>/dev/null || true
uci commit passwall2 2>/dev/null || true
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-nss-optimize