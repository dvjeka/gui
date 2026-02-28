#!/bin/bash

# final-build-kvm.sh
# Финальная сборка SENTINEL OS KVM EDITION
# Оптимизировано для запуска под KVM с VirtIO

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Директории
WORK_DIR="$HOME/sentinel-kvm"
BUILD_DIR="$WORK_DIR/build/openwrt-imagebuilder"
FILES_DIR="$BUILD_DIR/files"
CONFIG_DIR="$WORK_DIR/configs"
RELEASE_DIR="$WORK_DIR/release"
OUTPUT_DIR="$BUILD_DIR/bin/targets/x86/64"

# Версия
VERSION="2.0.0"
CODENAME="KVM ULTIMATE PRIVACY EDITION"

# Функции вывода
print_step() { echo -e "${BLUE}🔷 [$1/15] $2${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️ $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ️ $1${NC}"; }
print_kvm() { echo -e "${PURPLE}⚡ $1${NC}"; }

# Заголовок
clear
echo -e "${PURPLE}"
echo "================================================"
echo "🚀 SENTINEL OS KVM v$VERSION - FINAL BUILD"
echo "================================================"
echo -e "${NC}"

# Проверка окружения
check_environment() {
    print_step "1" "Проверка KVM окружения"
    
    # Проверка KVM
    if [ -c /dev/kvm ]; then
        print_success "KVM доступен"
    else
        print_warning "KVM недоступен - сборка продолжится, но без аппаратной виртуализации"
    fi
    
    # Проверка ImageBuilder
    if [ ! -d "$BUILD_DIR" ]; then
        print_error "ImageBuilder не найден в $BUILD_DIR"
        exit 1
    fi
    
    # Проверка необходимых утилит
    local missing=()
    for cmd in make tar gzip python3 nft qemu-img; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Отсутствуют: ${missing[*]}"
        exit 1
    fi
    
    print_success "Окружение проверено"
}

# Очистка
clean_build() {
    print_step "2" "Очистка предыдущей сборки"
    
    cd "$BUILD_DIR"
    
    if [ "$1" = "--full-clean" ]; then
        print_info "Полная очистка..."
        make clean
        rm -rf ./build_dir/*
        rm -rf ./staging_dir/*
    fi
    
    rm -rf "$FILES_DIR"
    mkdir -p "$FILES_DIR"
    
    print_success "Очистка завершена"
}

# Копирование конфигов
copy_configs() {
    print_step "3" "Копирование конфигурационных файлов"
    
    if [ ! -d "$CONFIG_DIR" ]; then
        print_error "Директория configs не найдена"
        exit 1
    fi
    
    # Копируем все конфиги
    cp -rv "$CONFIG_DIR"/* "$FILES_DIR"/ 2>/dev/null || true
    
    # Создаем структуру
    mkdir -p "$FILES_DIR"/{etc,usr,root,www}
    mkdir -p "$FILES_DIR"/etc/{sentinel,nftables.d,modprobe.d,sysctl.d}
    mkdir -p "$FILES_DIR"/usr/{bin,lib/lua/luci}
    
    print_success "Конфиги скопированы"
}

# Генерация списка пакетов для KVM
generate_package_list() {
    print_step "4" "Генерация списка пакетов для KVM"
    
    PACKAGES=""
    
    # Базовые пакеты
    PACKAGES="$PACKAGES base-files libc libgcc busybox dropbear mtd uci opkg"
    
    # VirtIO драйверы (критически важно для KVM)
    PACKAGES="$PACKAGES kmod-virtio kmod-virtio-net kmod-virtio-blk"
    PACKAGES="$PACKAGES kmod-virtio-pci kmod-virtio-ring kmod-virtio-balloon"
    PACKAGES="$PACKAGES kmod-virtio-console kmod-virtio-rng kmod-virtio-scsi"
    
    # Сетевые драйверы
    PACKAGES="$PACKAGES kmod-e1000 kmod-e1000e kmod-igb kmod-ixgbe"
    
    # Файловые системы
    PACKAGES="$PACKAGES kmod-fs-ext4 kmod-fs-vfat kmod-fs-ntfs kmod-fs-btrfs"
    
    # USB поддержка
    PACKAGES="$PACKAGES kmod-usb-core kmod-usb-ohci kmod-usb-uhci"
    PACKAGES="$PACKAGES kmod-usb2 kmod-usb3 kmod-usb-storage"
    
    # Сеть и firewall (чистый nftables)
    PACKAGES="$PACKAGES nftables firewall4 kmod-nft-offload"
    PACKAGES="$PACKAGES kmod-nft-socket kmod-nft-tproxy kmod-nft-nat"
    
    # VPN протоколы
    PACKAGES="$PACKAGES wireguard-tools kmod-wireguard"
    PACKAGES="$PACKAGES amneziawg-tools kmod-amneziawg"
    PACKAGES="$PACKAGES openvpn-openssl xray-core sing-box"
    
    # Прокси
    PACKAGES="$PACKAGES shadowsocks-libev-ss-redir trojan"
    PACKAGES="$PACKAGES hysteria2"
    
    # DNS и приватность
    PACKAGES="$PACKAGES unbound stubby dnscrypt-proxy adguardhome"
    PACKAGES="$PACKAGES smartdns https-dns-proxy"
    
    # DPI обход
    PACKAGES="$PACKAGES zapret byedpi goodbyedpi"
    
    # Дополнительные утилиты
    PACKAGES="$PACKAGES bash curl ca-certificates ip-full"
    PACKAGES="$PACKAGES python3 python3-pip python3-cryptography"
    PACKAGES="$PACKAGES iptables-nft tcpdump socat nmap"
    PACKAGES="$PACKAGES htop atop iotop iperf3"
    PACKAGES="$PACKAGES coreutils tmux screen"
    
    # Swap и память
    PACKAGES="$PACKAGES kmod-zram zram-swap fdisk lsblk"
    
    # Веб-интерфейс
    PACKAGES="$PACKAGES luci luci-base luci-compat luci-theme-material"
    
    print_success "Сгенерировано $(echo $PACKAGES | wc -w) пакетов"
}

# Создание файла версии
create_version_file() {
    print_step "5" "Создание файла версии"
    
    local version_file="$FILES_DIR/etc/sentinel-version"
    
    cat > "$version_file" << EOF
SENTINEL OS KVM v$VERSION
Codename: $CODENAME
Build Date: $(date)
Architecture: x86_64 (KVM optimized)
VirtIO Support: Yes

FEATURES:
- Full protocol support with KVM optimizations
- VirtIO multi-queue networking
- Hardware offload support
- Pure nftables firewall
- DNS privacy chain
- Advanced DPI bypass
- Leak protection suite

You'r System — you'r rules.
EOF
    
    print_success "Файл версии создан"
}

# Создание пост-установочного скрипта
create_postinst() {
    print_step "6" "Создание пост-установочного скрипта"
    
    local postinst="$FILES_DIR/etc/uci-defaults/99-sentinel-kvm-setup"
    mkdir -p "$FILES_DIR/etc/uci-defaults"
    
    cat > "$postinst" << 'EOF'
#!/bin/sh

# SENTINEL OS KVM - Post-installation setup

LOG_FILE="/tmp/sentinel-kvm-postinst.log"

log() {
    echo "[$(date)] $1" >> $LOG_FILE
    echo "$1"
}

log "🚀 Настройка SENTINEL OS KVM..."

# Создание директорий
mkdir -p /etc/sentinel/{configs,protocols,logs}
mkdir -p /var/run/sentinel
mkdir -p /etc/nftables.d
mkdir -p /etc/dnsmasq.d

# Отключение dnsmasq (освобождаем порт 53 для AdGuard)
uci set dhcp.@dnsmasq[0].port=0
uci commit dhcp

# Включение служб
/etc/init.d/sentinel-core-kvm enable
/etc/init.d/sentinel-core-kvm start

# Настройка sysctl для KVM
cat > /etc/sysctl.d/99-kvm.conf << SYSCTL
# KVM optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
SYSCTL

sysctl -p /etc/sysctl.d/99-kvm.conf

# Включение KSM (экономия памяти)
echo 1 > /sys/kernel/mm/ksm/run
echo 100 > /sys/kernel/mm/ksm/pages_to_scan

# Настройка VirtIO multi-queue
for dev in eth0 eth1; do
    if [ -d /sys/class/net/$dev ]; then
        queues=$(nproc)
        ethtool -L $dev combined $queues 2>/dev/null
        ethtool -K $dev tx on rx on tso on gso on gro on 2>/dev/null
    fi
done

# Настройка nftables
nft flush ruleset
nft -f /etc/nftables.d/00-base.nft

log "✅ Настройка завершена"
exit 0
EOF
    
    chmod +x "$postinst"
    print_success "Пост-установочный скрипт создан"
}

# Создание manifest файла
create_manifest() {
    print_step "7" "Создание manifest файла"
    
    local manifest="$FILES_DIR/etc/sentinel/manifest.json"
    
    cat > "$manifest" << EOF
{
    "version": "$VERSION",
    "codename": "$CODENAME",
    "build_date": "$(date -Iseconds)",
    "kvm": {
        "virtio_supported": true,
        "multi_queue": true,
        "vhost_net": true,
        "ksm_enabled": true
    },
    "components": {
        "core": "sentinel-core-kvm",
        "dns": ["adguardhome", "unbound", "dnscrypt"],
        "firewall": "nftables",
        "protocols": ["wireguard", "openvpn", "xray", "shadowsocks"]
    }
}
EOF
    
    print_success "Manifest файл создан"
}

# Создание systemd сервиса для KVM оптимизаций
create_kvm_service() {
    print_step "8" "Создание KVM service"
    
    local service="$FILES_DIR/etc/systemd/system/sentinel-kvm-optimize.service"
    mkdir -p "$FILES_DIR/etc/systemd/system"
    
    cat > "$service" << 'EOF'
[Unit]
Description=SENTINEL OS KVM Optimizations
Before=network.target
After=systemd-modules-load.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/sentinel-kvm-optimize
ExecReload=/usr/bin/sentinel-kvm-optimize

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "KVM service создан"
}

# Сборка образа
build_image() {
    print_step "9" "Сборка образа"
    
    cd "$BUILD_DIR"
    
    # Обновление фидов
    print_info "Обновление фидов..."
    ./scripts/feeds update -a
    ./scripts/feeds install -a
    
    # Конфигурация для KVM
    print_info "Настройка конфигурации..."
    
    cat >> .config << EOF
# Target
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_Generic=y

# RootFS
CONFIG_TARGET_ROOTFS_PARTSIZE=2048
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_TARGET_IMAGES_GZIP=y

# KVM formats
CONFIG_QCOW2_IMAGES=y
CONFIG_VDI_IMAGES=y
CONFIG_VMDK_IMAGES=y

# Console
CONFIG_GRUB_CONSOLE=y
CONFIG_GRUB_SERIAL=y
EOF
    
    make defconfig
    
    # Запуск сборки
    print_info "Запуск make (это займет много времени)..."
    make -j$(nproc) || make -j1 V=s
    
    if [ $? -eq 0 ]; then
        print_success "Сборка успешно завершена!"
    else
        print_error "Ошибка сборки!"
        exit 1
    fi
}

# Копирование образов
copy_images() {
    print_step "10" "Копирование образов"
    
    mkdir -p "$RELEASE_DIR/sentinel-os-kvm-$VERSION"
    
    if [ -d "$OUTPUT_DIR" ]; then
        cp -v "$OUTPUT_DIR"/*.gz "$RELEASE_DIR/sentinel-os-kvm-$VERSION"/ 2>/dev/null || true
        cp -v "$OUTPUT_DIR"/*.qcow2 "$RELEASE_DIR/sentinel-os-kvm-$VERSION"/ 2>/dev/null || true
        cp -v "$OUTPUT_DIR"/*.vmdk "$RELEASE_DIR/sentinel-os-kvm-$VERSION"/ 2>/dev/null || true
        cp -v "$OUTPUT_DIR"/*.vdi "$RELEASE_DIR/sentinel-os-kvm-$VERSION"/ 2>/dev/null || true
        
        # Контрольные суммы
        cd "$RELEASE_DIR/sentinel-os-kvm-$VERSION"
        sha256sum * > sha256sums.txt
        md5sum * > md5sums.txt
        
        print_success "Образы скопированы в $RELEASE_DIR/sentinel-os-kvm-$VERSION"
    else
        print_error "Образы не найдены!"
    fi
}

# Создание инструкции для KVM
create_kvm_guide() {
    print_step "11" "Создание инструкции для KVM"
    
    local guide="$RELEASE_DIR/INSTALL-KVM.txt"
    
    cat > "$guide" << EOF
SENTINEL OS KVM v$VERSION - INSTALLATION GUIDE FOR KVM
========================================================

You'r System — you'r rules

ВАРИАНТ 1: УСТАНОВКА ЧЕРЕЗ VIRT-MANAGER
---------------------------------------
1. Откройте virt-manager
2. Создайте новую VM
3. Выберите "Import existing disk image"
4. Укажите путь к sentinel-os-kvm-$VERSION.qcow2
5. Выберите OS type: Linux, Version: Linux 5.x
6. Настройте ресурсы:
   - RAM: минимум 2048 MB (рекомендуется 4096 MB)
   - CPU: минимум 2 ядра
   - Сеть: virtio
   - Диск: virtio
7. Завершите создание и запустите VM

ВАРИАНТ 2: УСТАНОВКА ЧЕРЕЗ COMMAND LINE
---------------------------------------
1. Скопируйте образ:
   sudo cp sentinel-os-kvm-$VERSION.qcow2 /var/lib/libvirt/images/

2. Создайте VM:
   virt-install \\
     --name sentinel-os \\
     --ram 4096 \\
     --vcpus 4 \\
     --disk path=/var/lib/libvirt/images/sentinel-os-kvm-$VERSION.qcow2,format=qcow2,bus=virtio \\
     --network network=default,model=virtio \\
     --graphics vnc,listen=0.0.0.0 \\
     --noautoconsole \\
     --import

3. Подключитесь:
   virsh console sentinel-os

ПЕРВЫЙ ЗАПУСК
-------------
1. Логин: root
2. Пароль: (пустой, смените при первом входе)
3. IP адрес по умолчанию: 192.168.1.100
4. Веб-интерфейс: http://192.168.1.100

ПРОВЕРКА KVM ОПТИМИЗАЦИЙ
------------------------
sentinel-check-kvm

ОСНОВНЫЕ КОМАНДЫ
----------------
sentinel-core-kvm status           - статус системы
sentinel-core-kvm start --protocol - запуск протокола
sentinel-dns-switch chain          - переключение DNS
sentinel-dns-leak-test              - тест DNS
sentinel-ip-leak-test               - тест IP
sentinel-stealth-mode start         - стелс-режим

========================================================
SENTINEL OS KVM v$VERSION - $CODENAME
EOF
    
    print_success "Инструкция создана"
}

# Финальная проверка
final_check() {
    print_step "12" "Финальная проверка"
    
    local release_dir="$RELEASE_DIR/sentinel-os-kvm-$VERSION"
    
    if [ -d "$release_dir" ] && [ "$(ls -A $release_dir)" ]; then
        print_success "✅ СБОРКА УСПЕШНО ЗАВЕРШЕНА!"
        print_info "Образы: $release_dir"
        print_info "Размер: $(du -sh $release_dir | cut -f1)"
        
        echo ""
        echo -e "${PURPLE}================================================"
        echo "🚀 SENTINEL OS KVM v$VERSION ГОТОВА К УСТАНОВКЕ!"
        echo "================================================${NC}"
        echo ""
        echo "📁 Образы: $release_dir"
        echo "📄 Инструкция: $RELEASE_DIR/INSTALL-KVM.txt"
        echo ""
        echo "🌐 Веб-интерфейс: http://192.168.1.100"
        echo "🔑 Логин: root, пароль: (сменить при входе)"
        echo "⚡ KVM оптимизации: включены"
        echo ""
    else
        print_error "❌ Образы не найдены!"
        exit 1
    fi
}

# Создание скрипта проверки KVM
create_kvm_check() {
    print_step "13" "Создание скрипта проверки KVM"
    
    local check_script="$FILES_DIR/usr/bin/sentinel-check-kvm"
    
    cat > "$check_script" << 'EOF'
#!/bin/bash

# sentinel-check-kvm
# Проверка KVM окружения

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${PURPLE}========================================${NC}"
echo -e "${PURPLE}🔍 SENTINEL OS KVM - CHECK${NC}"
echo -e "${PURPLE}========================================${NC}"

# Тип виртуализации
virt_type=$(systemd-detect-virt 2>/dev/null || echo "unknown")
if [ "$virt_type" = "kvm" ]; then
    echo -e "${GREEN}✅ Виртуализация: KVM${NC}"
else
    echo -e "${YELLOW}⚠️ Виртуализация: $virt_type${NC}"
fi

# VirtIO устройства
virtio_net=$(ls -d /sys/bus/virtio/devices/virtio* 2>/dev/null | wc -l)
echo -e "${GREEN}✅ VirtIO устройств: $virtio_net${NC}"

# Multi-queue
for dev in eth0 eth1; do
    if [ -d /sys/class/net/$dev ]; then
        queues=$(ls -d /sys/class/net/$dev/queues/rx-* 2>/dev/null | wc -l)
        echo -e "${GREEN}✅ $dev: $queues очередей${NC}"
    fi
done

# KSM
if [ -f /sys/kernel/mm/ksm/run ]; then
    ksm=$(cat /sys/kernel/mm/ksm/run)
    if [ "$ksm" = "1" ]; then
        echo -e "${GREEN}✅ KSM: активен${NC}"
    else
        echo -e "${YELLOW}⚠️ KSM: отключен${NC}"
    fi
fi

# nftables
if nft list tables &>/dev/null; then
    rules=$(nft list ruleset 2>/dev/null | grep -c "chain" || echo 0)
    echo -e "${GREEN}✅ nftables: $rules цепочек${NC}"
fi

# Память
mem_total=$(free -m | grep Mem | awk '{print $2}')
mem_avail=$(free -m | grep Mem | awk '{print $7}')
echo -e "${GREEN}✅ Память: $mem_avail MB свободно из $mem_total MB${NC}"

echo -e "${PURPLE}========================================${NC}"
EOF
    
    chmod +x "$check_script"
    print_success "Скрипт проверки KVM создан"
}

# Создание скрипта оптимизации KVM
create_kvm_optimize() {
    print_step "14" "Создание скрипта оптимизации KVM"
    
    local optimize_script="$FILES_DIR/usr/bin/sentinel-kvm-optimize"
    
    cat > "$optimize_script" << 'EOF'
#!/bin/bash

# sentinel-kvm-optimize
# Применение KVM оптимизаций

LOG_FILE="/var/log/sentinel-kvm-optimize.log"

log() {
    echo "[$(date)] $1" | tee -a $LOG_FILE
}

log "🚀 Применение KVM оптимизаций..."

# Настройка сетевых очередей
for dev in eth0 eth1; do
    if [ -d /sys/class/net/$dev ]; then
        queues=$(nproc)
        log "Настройка $dev: $queues очередей"
        ethtool -L $dev combined $queues 2>/dev/null
        ethtool -K $dev tx on rx on tso on gso on gro on 2>/dev/null
    fi
done

# Включение KSM
echo 1 > /sys/kernel/mm/ksm/run
echo 100 > /sys/kernel/mm/ksm/pages_to_scan
log "KSM активирован"

# Настройка планировщика
for disk in /sys/block/vd*; do
    if [ -d $disk ]; then
        echo none > $disk/queue/scheduler 2>/dev/null
        log "Планировщик для $(basename $disk): none"
    fi
done

# Настройка BBR
if ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    sysctl -p
    log "BBR активирован"
fi

log "✅ KVM оптимизации применены"
EOF
    
    chmod +x "$optimize_script"
    print_success "Скрипт оптимизации KVM создан"
}

# Завершение сборки
finish_build() {
    print_step "15" "Завершение сборки"
    
    print_success "✅ ВСЕ ЭТАПЫ ВЫПОЛНЕНЫ"
    
    echo ""
    echo -e "${PURPLE}================================================"
    echo "🎉 SENTINEL OS KVM v$VERSION ГОТОВА!"
    echo "================================================"
    echo ""
    echo "📦 Образы: $RELEASE_DIR/sentinel-os-kvm-$VERSION/"
    echo "📄 Инструкция: $RELEASE_DIR/INSTALL-KVM.txt"
    echo ""
    echo "⚡ KVM оптимизации:"
    echo "  - VirtIO multi-queue"
    echo "  - Hardware offload"
    echo "  - KSM memory sharing"
    echo "  - BBR congestion control"
    echo ""
    echo "🚀 Для установки:"
    echo "  sudo virt-install --name sentinel-os --ram 4096 --vcpus 4 \\"
    echo "    --disk path=$RELEASE_DIR/sentinel-os-kvm-$VERSION/sentinel-os-kvm-$VERSION.qcow2 \\"
    echo "    --network network=default,model=virtio --import"
    echo ""
    echo -e "${PURPLE}================================================"
    echo "You'r System — you'r rules"
    echo -e "================================================${NC}"
    echo ""
}

# Очистка временных файлов
cleanup() {
    print_info "Очистка временных файлов..."
    rm -rf /tmp/sentinel-*
    print_success "Очистка завершена"
}

# Основная функция
main() {
    check_environment
    clean_build "$1"
    copy_configs
    create_version_file
    create_postinst
    create_manifest
    create_kvm_service
    create_kvm_check
    create_kvm_optimize
    generate_package_list
    build_image
    copy_images
    create_kvm_guide
    final_check
    finish_build
    cleanup
}

# Запуск
main "$@"