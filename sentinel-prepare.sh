#!/bin/bash

# install-dependencies-kvm.sh
# Установка зависимостей для сборки SENTINEL OS v2.0 под KVM
# Специализированная версия для Ubuntu Server с поддержкой виртуализации

set -e
exec 2>&1
LOG_FILE="/tmp/sentinel-kvm-build.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "🚀 [SENTINEL OS KVM] Начало установки зависимостей..."
echo "📅 Время: $(date)"
echo "================================================"

# Функция логирования с временем
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Функция проверки успешности
check_success() {
    if [ $? -eq 0 ]; then
        echo "✅ $1"
    else
        echo "❌ $1"
        exit 1
    fi
}

# 1. Базовые системные пакеты для сборки
log "📦 Установка базовых инструментов сборки..."
apt update
apt install -y \
    build-essential \
    clang \
    flex \
    bison \
    g++ \
    gawk \
    gcc-multilib \
    g++-multilib \
    gettext \
    git \
    libncurses5-dev \
    libssl-dev \
    python3-setuptools \
    rsync \
    swig \
    unzip \
    zlib1g-dev \
    file \
    wget \
    curl \
    jq \
    qemu-utils \
    genisoimage \
    libelf-dev \
    python3-pip \
    python3-venv \
    time \
    bc \
    gcc \
    binutils \
    patch \
    bzip2 \
    flex \
    bison \
    make \
    autoconf \
    gettext \
    texinfo \
    automake \
    libtool \
    pkg-config

check_success "Базовые инструменты установлены"

# 2. Инструменты для работы с KVM/qemu
log "📦 Установка инструментов виртуализации..."
apt install -y \
    qemu-kvm \
    libvirt-daemon-system \
    libvirt-clients \
    bridge-utils \
    virt-manager \
    virt-viewer \
    ovmf \
    cpu-checker \
    cloud-image-utils

check_success "Инструменты KVM установлены"

# 3. Python-пакеты для центрального оркестратора
log "📦 Установка Python-пакетов..."
pip3 install --upgrade pip
pip3 install --user \
    pyyaml \
    psutil \
    netifaces \
    python-iptables \
    nftables \
    jinja2 \
    requests \
    cryptography

check_success "Python-пакеты установлены"

# 4. Проверка поддержки виртуализации
log "🔍 Проверка поддержки виртуализации..."
kvm-ok || log "⚠️ Внимание: Аппаратная виртуализация может быть недоступна"

# 5. Создание структуры директорий
log "📁 Создание структуры директорий..."
mkdir -p ~/sentinel-kvm/{build,configs,scripts,release,images}
mkdir -p ~/sentinel-kvm/build/openwrt-imagebuilder

check_success "Структура директорий создана"

# 6. Создание виртуального моста для сети
log "🌉 Настройка сетевого моста для KVM..."
cat > /etc/netplan/01-netcfg.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: no
  bridges:
    br0:
      interfaces: [eth0]
      dhcp4: yes
      dhcp6: no
      parameters:
        stp: false
        forward-delay: 0
EOF

netplan apply || log "⚠️ Netplan не применен - настройте bridge вручную"

# 7. Создание скрипта проверки окружения
cat > ~/sentinel-kvm/scripts/check-kvm-env.sh << 'EOF'
#!/bin/bash

# check-kvm-env.sh
# Проверка готовности окружения к сборке и запуску SENTINEL OS под KVM

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🔍 Проверка окружения для SENTINEL OS KVM"
echo "=========================================="

# Проверка KVM
if [ -c /dev/kvm ]; then
    echo -e "${GREEN}✅ KVM доступен${NC}"
else
    echo -e "${RED}❌ KVM недоступен${NC}"
fi

# Проверка виртуализации CPU
if grep -q vmx /proc/cpuinfo || grep -q svm /proc/cpuinfo; then
    echo -e "${GREEN}✅ Аппаратная виртуализация поддержана${NC}"
else
    echo -e "${YELLOW}⚠️ Аппаратная виртуализация не найдена${NC}"
fi

# Проверка libvirt
if systemctl is-active libvirtd >/dev/null 2>&1; then
    echo -e "${GREEN}✅ libvirtd запущен${NC}"
else
    echo -e "${RED}❌ libvirtd не запущен${NC}"
fi

# Проверка сетевого моста
if ip link show br0 >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Сетевой мост br0 существует${NC}"
else
    echo -e "${YELLOW}⚠️ Сетевой мост br0 не найден${NC}"
fi

# Проверка свободного места
FREE_SPACE=$(df -BG ~ | awk 'NR==2 {print $4}' | sed 's/G//')
if [ $FREE_SPACE -gt 20 ]; then
    echo -e "${GREEN}✅ Свободно: ${FREE_SPACE}GB${NC}"
else
    echo -e "${RED}❌ Мало места: ${FREE_SPACE}GB (нужно >20GB)${NC}"
fi

echo "=========================================="
EOF

chmod +x ~/sentinel-kvm/scripts/check-kvm-env.sh

log "✅ Установка зависимостей завершена!"
log "📁 Рабочая директория: ~/sentinel-kvm"
log "🔍 Запустите: ~/sentinel-kvm/scripts/check-kvm-env.sh"

exit 0