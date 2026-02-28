#!/bin/bash

# setup-kvm-configs.sh
# Создание KVM-специфичных конфигураций для SENTINEL OS

set -e

cd ~/sentinel-kvm
mkdir -p configs/etc/{config,sentinel,nftables.d,modprobe.d,sysctl.d}

# 1. Сетевой конфиг для KVM (с поддержкой VirtIO)
cat > configs/etc/config/network << 'EOF'
# SENTINEL OS v2.0 KVM - Network Configuration
# Оптимизировано для VirtIO в KVM

config interface 'loopback'
    option device 'lo'
    option proto 'static'
    option ipaddr '127.0.0.1'
    option netmask '255.0.0.0'

# Основной интерфейс для KVM (VirtIO)
config device
    option name 'eth0'
    option type 'ethernet'

config interface 'lan'
    option device 'eth0'
    option proto 'static'
    option ipaddr '192.168.1.100'
    option netmask '255.255.255.0'
    option gateway '192.168.1.1'
    list dns '127.0.0.1'
    list dns '::1'

# Дополнительный интерфейс для WAN (если нужно)
config device
    option name 'eth1'
    option type 'ethernet'

config interface 'wan'
    option device 'eth1'
    option proto 'dhcp'

config interface 'wan6'
    option device 'eth1'
    option proto 'dhcpv6'

# Интерфейсы для VPN (VirtIO)
config device
    option name 'vhost0'
    option type 'tun'

config interface 'vpn'
    option device 'vhost0'
    option proto 'none'

# Оптимизация для VirtIO
config device 'virtio_optimization'
    option name 'eth0'
    option rx_ring_size '1024'
    option tx_ring_size '1024'
    option coalesce_usecs '100'
EOF

# 2. KVM-оптимизированный firewall (только nftables)
cat > configs/etc/config/firewall << 'EOF'
# SENTINEL OS v2.0 KVM - Firewall Configuration
# Чистый nftables, без смешивания с iptables

config defaults
    option syn_flood '1'
    option input 'DROP'
    option output 'ACCEPT'
    option forward 'DROP'
    option drop_invalid '1'

config zone
    option name 'lan'
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'ACCEPT'
    option network 'lan'

config zone
    option name 'wan'
    option input 'DROP'
    option output 'ACCEPT'
    option forward 'DROP'
    option masq '1'
    option mtu_fix '1'
    option network 'wan wan6'

config zone
    option name 'vpn'
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'ACCEPT'
    option masq '1'
    option network 'vpn'

config forwarding
    option src 'lan'
    option dest 'wan'

config forwarding
    option src 'lan'
    option dest 'vpn'

config forwarding
    option src 'vpn'
    option dest 'lan'

config forwarding
    option src 'vpn'
    option dest 'wan'

# Правила для VPN протоколов
config rule
    option name 'Allow-WireGuard'
    option src 'wan'
    option dest_port '51820'
    option proto 'udp'
    option target 'ACCEPT'

config rule
    option name 'Allow-OpenVPN'
    option src 'wan'
    option dest_port '1194'
    option proto 'udp'
    option target 'ACCEPT'

config rule
    option name 'Allow-Xray'
    option src 'wan'
    option dest_port '443'
    option proto 'tcp'
    option target 'ACCEPT'

# DNS правила - весь DNS через локальный резолвер
config rule
    option name 'Allow-DNS-Local'
    option src 'lan'
    option dest_ip '127.0.0.1'
    option dest_port '53'
    option proto 'tcp udp'
    option target 'ACCEPT'

config rule
    option name 'Block-DNS-External'
    option src 'lan'
    option dest 'wan'
    option dest_port '53'
    option proto 'tcp udp'
    option target 'REJECT'
EOF

# 3. KVM-оптимизированный sysctl
cat > configs/etc/sysctl.d/99-kvm-optimization.conf << 'EOF'
# SENTINEL OS KVM - Performance Optimizations

# Network optimizations for VirtIO
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 16777216
net.core.wmem_default = 16777216
net.core.optmem_max = 16777216
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 4096

# TCP optimizations
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3

# Memory optimizations
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 30
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1
vm.min_free_kbytes = 65536

# Security
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_all = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1

# IPv6 (можно отключить для безопасности)
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.forwarding = 1
EOF

# 4. Модули для KVM
cat > configs/etc/modules.d/10-kvm-virtio << 'EOF'
# VirtIO modules for KVM
virtio
virtio_ring
virtio_pci
virtio_net
virtio_blk
virtio_console
virtio_rng
virtio_balloon
vhost
vhost_net
vhost_iotlb
EOF

# 5. Настройка zram-swap (для экономии памяти)
cat > configs/etc/config/zram-swap << 'EOF'
# SENTINEL OS KVM - ZRAM Swap Configuration
# Компрессия RAM вместо дискового swap

config zram-swap
    option enabled '1'
    option compression_algorithm 'zstd'
    option size_mb '1024'
    option priority '100'
EOF

# 6. Скрипт для проверки KVM окружения внутри виртуалки
cat > configs/usr/bin/sentinel-check-kvm << 'EOF'
#!/bin/sh

# sentinel-check-kvm
# Проверка окружения SENTINEL OS внутри KVM

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🔍 SENTINEL OS KVM Environment Check"
echo "======================================"

# Проверка KVM
if systemd-detect-virt | grep -q kvm; then
    echo -e "${GREEN}✅ Запущено под KVM${NC}"
else
    echo -e "${YELLOW}⚠️ Не KVM окружение: $(systemd-detect-virt)${NC}"
fi

# Проверка VirtIO устройств
echo ""
echo "📦 VirtIO устройства:"
ls -l /sys/bus/virtio/devices/ 2>/dev/null | wc -l | xargs echo "  Найдено: "

# Проверка сетевых драйверов
echo ""
echo "🌐 Сетевые интерфейсы:"
for iface in $(ls /sys/class/net/ | grep -v lo); do
    driver=$(readlink /sys/class/net/$iface/device/driver 2>/dev/null | xargs basename 2>/dev/null || echo "unknown")
    echo "  $iface: $driver"
done

# Проверка памяти
echo ""
echo "💾 Память:"
free -h | grep -v +

# Проверка KVM оптимизаций
echo ""
echo "⚡ KVM оптимизации:"
echo -n "  BBR: "
if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
    echo -e "${GREEN}включен${NC}"
else
    echo -e "${RED}отключен${NC}"
fi

echo -n "  TSO/GSO: "
if ethtool -k eth0 2>/dev/null | grep -q "tcp-segmentation-offload: on"; then
    echo -e "${GREEN}включено${NC}"
else
    echo -e "${YELLOW}отключено${NC}"
fi

echo ""
echo "======================================"
EOF

chmod +x configs/usr/bin/sentinel-check-kvm

# 7. systemd сервис для KVM оптимизаций
cat > configs/etc/init.d/kvm-optimize << 'EOF'
#!/bin/sh /etc/rc.common

# KVM Optimizations for SENTINEL OS

START=10
STOP=15

boot() {
    # Enable BBR if not enabled
    if ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        echo "Enabling BBR..."
        echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
        echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
        sysctl -p
    fi
    
    # Enable KSM for memory deduplication
    echo 1 > /sys/kernel/mm/ksm/run 2>/dev/null
    echo 100 > /sys/kernel/mm/ksm/pages_to_scan 2>/dev/null
    
    # Set CPU governor to performance
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "performance" > $cpu 2>/dev/null
    done
    
    # Optimize network queues for VirtIO
    for iface in eth0 eth1; do
        if [ -d /sys/class/net/$iface ]; then
            # Increase queue size
            ethtool -G $iface rx 4096 tx 4096 2>/dev/null
            # Enable all offloads
            ethtool -K $iface tx on rx on tso on gso on gro on lro on 2>/dev/null
        fi
    done
    
    echo "KVM optimizations applied"
}
EOF

chmod +x configs/etc/init.d/kvm-optimize

echo "✅ KVM-оптимизированные конфиги созданы"
exit 0