#!/bin/bash

# setup-imagebuilder-kvm.sh
# Настройка OpenWrt ImageBuilder для KVM с поддержкой VirtIO

set -e
LOG_FILE="/tmp/sentinel-kvm-imagebuilder.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "🚀 Настройка ImageBuilder для KVM"
echo "================================================"

cd ~/sentinel-kvm/build/

# Определяем версию OpenWrt (рекомендуется последняя LTS)
VERSION="23.05.5"
ARCH="x86_64"
IMAGE_BUILDER="openwrt-imagebuilder-${VERSION}-${ARCH}.Linux-x86_64"
IMAGE_BUILDER_FILE="${IMAGE_BUILDER}.tar.xz"
DOWNLOAD_URL="https://downloads.openwrt.org/releases/${VERSION}/targets/x86/64/${IMAGE_BUILDER_FILE}"

# Загрузка
echo "📥 Загрузка ImageBuilder ${VERSION}..."
if [ ! -f "${IMAGE_BUILDER_FILE}" ]; then
    wget ${DOWNLOAD_URL}
else
    echo "Файл уже загружен"
fi

# Распаковка
echo "📦 Распаковка..."
if [ ! -d "${IMAGE_BUILDER}" ]; then
    tar -xJf ${IMAGE_BUILDER_FILE}
fi

ln -sfn ${IMAGE_BUILDER} openwrt-imagebuilder
cd openwrt-imagebuilder

# Настройка feeds.conf с кастомными репозиториями
cat > feeds.conf << 'EOF'
src-git packages https://git.openwrt.org/feed/packages.git^23.05.5
src-git luci https://git.openwrt.org/project/luci.git^23.05.5
src-git routing https://git.openwrt.org/feed/routing.git^23.05.5
src-git telephony https://git.openwrt.org/feed/telephony.git^23.05.5
src-git kenzok8 https://github.com/kenzok8/openwrt-packages.git
src-git small https://github.com/kenzok8/small.git
src-git amneziawg https://github.com/amnezia-vpn/amneziawg-openwrt.git
src-git passwall https://github.com/xiaorouji/openwrt-passwall.git
src-git helloworld https://github.com/fw876/helloworld.git
EOF

# Обновление фидов
./scripts/feeds update -a
./scripts/feeds install -a

# Создание конфигурации для KVM
cat > .config << 'EOF'
# Target Configuration
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_Generic=y
CONFIG_TARGET_ROOTFS_PARTSIZE=2048
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_TARGET_IMAGES_GZIP=y
CONFIG_QCOW2_IMAGES=y
CONFIG_VDI_IMAGES=y
CONFIG_VMDK_IMAGES=y

# VirtIO Drivers (критически важно для KVM)
CONFIG_PACKAGE_kmod-virtio=y
CONFIG_PACKAGE_kmod-virtio-net=y
CONFIG_PACKAGE_kmod-virtio-blk=y
CONFIG_PACKAGE_kmod-virtio-pci=y
CONFIG_PACKAGE_kmod-virtio-ring=y
CONFIG_PACKAGE_kmod-virtio-balloon=y
CONFIG_PACKAGE_kmod-virtio-console=y
CONFIG_PACKAGE_kmod-virtio-rng=y
CONFIG_PACKAGE_kmod-virtio-scsi=y

# Network Drivers
CONFIG_PACKAGE_kmod-e1000=y
CONFIG_PACKAGE_kmod-e1000e=y
CONFIG_PACKAGE_kmod-igb=y
CONFIG_PACKAGE_kmod-ixgbe=y

# Filesystem support
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_kmod-fs-ntfs=y
CONFIG_PACKAGE_kmod-fs-btrfs=y

# USB Support
CONFIG_PACKAGE_kmod-usb-core=y
CONFIG_PACKAGE_kmod-usb-ohci=y
CONFIG_PACKAGE_kmod-usb-uhci=y
CONFIG_PACKAGE_kmod-usb2=y
CONFIG_PACKAGE_kmod-usb3=y
CONFIG_PACKAGE_kmod-usb-storage=y

# Console and Serial
CONFIG_PACKAGE_kmod-8139cp=y
CONFIG_PACKAGE_kmod-8139too=y
CONFIG_PACKAGE_kmod-pcnet32=y
CONFIG_GRUB_CONSOLE=y
CONFIG_GRUB_SERIAL=y

# Swap support (важно для ресурсоемких приложений)
CONFIG_PACKAGE_kmod-zram=y
CONFIG_PACKAGE_zram-swap=y
CONFIG_PACKAGE_fdisk=y
CONFIG_PACKAGE_lsblk=y

# Performance monitoring
CONFIG_PACKAGE_kmod-vhost-net=y
CONFIG_PACKAGE_iperf3=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_atop=y
CONFIG_PACKAGE_iotop=y

# Python support (для оркестратора)
CONFIG_PACKAGE_python3=y
CONFIG_PACKAGE_python3-pip=y
CONFIG_PACKAGE_python3-cryptography=y

# nftables (современный firewall)
CONFIG_PACKAGE_nftables=y
CONFIG_PACKAGE_iptables-nft=y
CONFIG_PACKAGE_arptables-nft=y
CONFIG_PACKAGE_ebtables-nft=y

# System utilities
CONFIG_PACKAGE_coreutils=y
CONFIG_PACKAGE_coreutils-base64=y
CONFIG_PACKAGE_tmux=y
CONFIG_PACKAGE_screen=y
CONFIG_PACKAGE_socat=y
CONFIG_PACKAGE_tcpdump=y
CONFIG_PACKAGE_nmap=y

# Include all packages
CONFIG_ALL=y
CONFIG_ALL_KMODS=y
CONFIG_ALL_NON_KMODS=y

# Size optimization (отключаем для KVM - нам нужно больше места)
# CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_EXTRA_OPTIMIZATION=y
CONFIG_TARGET_OPTIMIZATION="-Os -pipe -mno-call"

# Debug symbols (можно отключить для production)
# CONFIG_DEBUG=y
CONFIG_STRIP_KERNEL_EXPORTS=y
CONFIG_USE_MKLIBS=y
CONFIG_USE_SSTRIP=y
EOF

# Сохранение конфигурации
cp .config .config.kvm.backup

echo "✅ ImageBuilder настроен для KVM"
echo "📁 Локация: $(pwd)"
echo "🚀 Для сборки: make defconfig && make -j$(nproc)"

exit 0