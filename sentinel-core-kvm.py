#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
SENTINEL OS v2.0 KVM EDITION - CENTRAL ORCHESTRATOR
====================================================
Специализированная версия для работы в среде KVM на Ubuntu Server
Архитектура: чистая nftables, VirtIO оптимизации, no iptables legacy
"""

import os
import sys
import json
import yaml
import time
import signal
import logging
import subprocess
import ipaddress
import re
import psutil
import netifaces
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple, Union
from dataclasses import dataclass, field, asdict
from enum import Enum
from datetime import datetime
import threading
import fcntl
import struct
import socket

# ============================================================================
# KVM-СПЕЦИФИЧНЫЕ КОНСТАНТЫ
# ============================================================================

SENTINEL_VERSION = "2.0.0"
SENTINEL_CODENAME = "KVM ULTIMATE PRIVACY EDITION"

# Директории
BASE_DIR = Path("/etc/sentinel")
CONFIG_DIR = BASE_DIR / "configs"
PROTOCOLS_DIR = BASE_DIR / "protocols"
LOGS_DIR = BASE_DIR / "logs"
STATE_DIR = Path("/var/run/sentinel")
KVM_STATE_DIR = STATE_DIR / "kvm"

# Файлы
MAIN_CONFIG = BASE_DIR / "sentinel.yaml"
STATE_FILE = STATE_DIR / "state.json"
LOG_FILE = LOGS_DIR / "sentinel-core.log"
KVM_METRICS = KVM_STATE_DIR / "metrics.json"

# VirtIO интерфейсы
VIRTIO_NET_DEVS = ["eth0", "eth1", "eth2", "eth3"]
VIRTIO_BLK_DEVS = ["vda", "vdb", "vdc", "vdd"]

# Создаем необходимые директории
for dir_path in [BASE_DIR, CONFIG_DIR, PROTOCOLS_DIR, LOGS_DIR, STATE_DIR, KVM_STATE_DIR]:
    dir_path.mkdir(parents=True, exist_ok=True)

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("sentinel-core-kvm")

# ============================================================================
# ENUM И ДАТАКЛАССЫ
# ============================================================================

class ProtocolType(Enum):
    """Типы поддерживаемых протоколов"""
    WIREGUARD = "wireguard"
    AMNEZIAWG = "amneziawg"
    OPENVPN = "openvpn"
    XRAY = "xray"
    SHADOWSOCKS = "shadowsocks"
    TROJAN = "trojan"
    SINGBOX = "sing-box"
    HYSTERIA2 = "hysteria2"
    TOR = "tor"
    ZAPRET = "zapret"
    BYEDPI = "byedpi"
    GOODBYEDPI = "goodbyedpi"

class ProtocolStatus(Enum):
    STOPPED = "stopped"
    STARTING = "starting"
    RUNNING = "running"
    STOPPING = "stopping"
    ERROR = "error"

class KVMVirtIOType(Enum):
    """Типы VirtIO устройств"""
    NET = "net"
    BLK = "blk"
    CONSOLE = "console"
    RNG = "rng"
    BALLOON = "balloon"

@dataclass
class KVMVirtIODevice:
    """Информация о VirtIO устройстве"""
    type: KVMVirtIOType
    name: str
    driver: str
    enabled: bool = True
    queues: int = 1
    features: List[str] = field(default_factory=list)

@dataclass
class ProtocolConfig:
    """Конфигурация протокола"""
    name: str
    type: ProtocolType
    enabled: bool = False
    status: ProtocolStatus = ProtocolStatus.STOPPED
    config_file: Optional[Path] = None
    pid_file: Optional[Path] = None
    auto_start: bool = False
    priority: int = 10
    depends_on: List[str] = field(default_factory=list)
    settings: Dict[str, Any] = field(default_factory=dict)
    last_error: Optional[str] = None
    start_time: Optional[datetime] = None
    memory_limit_mb: Optional[int] = None
    cpu_quota: Optional[int] = None

@dataclass
class KVMResources:
    """Мониторинг ресурсов KVM"""
    memory_total: int = 0
    memory_available: int = 0
    memory_used: int = 0
    cpu_count: int = 0
    cpu_usage: float = 0.0
    virtio_net_count: int = 0
    virtio_blk_count: int = 0
    balloon_size: int = 0
    ksm_sharing: float = 0.0

# ============================================================================
# ОСНОВНОЙ КЛАСС ОРКЕСТРАТОРА
# ============================================================================

class SentinelKVMOrchestrator:
    """
    Центральный оркестратор SENTINEL OS для KVM.
    Оптимизирован для виртуализации с чистой nftables архитектурой.
    """
    
    def __init__(self):
        self.version = SENTINEL_VERSION
        self.codename = SENTINEL_CODENAME
        self.running = False
        self.protocols: Dict[str, ProtocolConfig] = {}
        self.kvm_resources = KVMResources()
        self.virtio_devices: List[KVMVirtIODevice] = []
        self.active_protocol: Optional[str] = None
        self.nftables_initialized = False
        
        # Регистрируем обработчики сигналов
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
        # Инициализация KVM-специфичных компонентов
        self._init_kvm_environment()
        self._load_configuration()
        
        logger.info(f"🚀 Sentinel KVM Orchestrator v{self.version} инициализирован")
        logger.info(f"📋 Режим: {self.codename}")
    
    # ========================================================================
    # KVM-СПЕЦИФИЧНЫЕ МЕТОДЫ
    # ========================================================================
    
    def _init_kvm_environment(self):
        """Инициализация KVM окружения"""
        logger.info("🔍 Инициализация KVM окружения...")
        
        # Определяем тип виртуализации
        virt_type = self._get_virt_type()
        if "kvm" not in virt_type.lower():
            logger.warning(f"⚠️ Запущено не под KVM: {virt_type}")
        
        # Сканируем VirtIO устройства
        self._scan_virtio_devices()
        
        # Инициализируем KSM для экономии памяти
        self._init_ksm()
        
        # Настраиваем сетевые оптимизации
        self._optimize_network()
        
        # Обновляем информацию о ресурсах
        self._update_kvm_resources()
        
        logger.info(f"✅ KVM окружение инициализировано: {self.kvm_resources}")
    
    def _get_virt_type(self) -> str:
        """Получение типа виртуализации"""
        try:
            result = subprocess.run(
                "systemd-detect-virt 2>/dev/null || echo 'unknown'",
                shell=True, capture_output=True, text=True
            )
            return result.stdout.strip()
        except:
            return "unknown"
    
    def _scan_virtio_devices(self):
        """Сканирование VirtIO устройств"""
        # VirtIO сетевые устройства
        for dev in VIRTIO_NET_DEVS:
            if Path(f"/sys/class/net/{dev}").exists():
                driver = self._get_device_driver(dev)
                queues = self._get_net_queues(dev)
                self.virtio_devices.append(KVMVirtIODevice(
                    type=KVMVirtIOType.NET,
                    name=dev,
                    driver=driver,
                    queues=queues
                ))
                logger.info(f"✅ VirtIO сеть: {dev} (драйвер: {driver}, очередей: {queues})")
        
        # VirtIO блочные устройства
        for dev in VIRTIO_BLK_DEVS:
            if Path(f"/sys/block/{dev}").exists():
                driver = self._get_block_driver(dev)
                self.virtio_devices.append(KVMVirtIODevice(
                    type=KVMVirtIOType.BLK,
                    name=dev,
                    driver=driver
                ))
                logger.info(f"✅ VirtIO блок: {dev} (драйвер: {driver})")
    
    def _get_device_driver(self, dev: str) -> str:
        """Получение драйвера устройства"""
        try:
            driver_path = Path(f"/sys/class/net/{dev}/device/driver")
            if driver_path.exists():
                return driver_path.resolve().name
        except:
            pass
        return "unknown"
    
    def _get_block_driver(self, dev: str) -> str:
        """Получение драйвера блочного устройства"""
        try:
            driver_path = Path(f"/sys/block/{dev}/device/driver")
            if driver_path.exists():
                return driver_path.resolve().name
        except:
            pass
        return "unknown"
    
    def _get_net_queues(self, dev: str) -> int:
        """Получение количества очередей сетевого устройства"""
        try:
            queues = Path(f"/sys/class/net/{dev}/queues").glob("rx-*")
            return len(list(queues))
        except:
            return 1
    
    def _init_ksm(self):
        """Инициализация Kernel Same-page Merging для экономии памяти"""
        try:
            # Включаем KSM
            with open("/sys/kernel/mm/ksm/run", "w") as f:
                f.write("1")
            
            # Настраиваем параметры
            with open("/sys/kernel/mm/ksm/pages_to_scan", "w") as f:
                f.write("100")
            
            with open("/sys/kernel/mm/ksm/sleep_millisecs", "w") as f:
                f.write("20")
            
            logger.info("✅ KSM активирован для экономии памяти")
        except Exception as e:
            logger.warning(f"⚠️ Не удалось активировать KSM: {e}")
    
    def _optimize_network(self):
        """Оптимизация сети для VirtIO"""
        for dev in self.virtio_devices:
            if dev.type == KVMVirtIOType.NET:
                try:
                    # Увеличиваем размер очередей
                    subprocess.run(
                        f"ethtool -G {dev.name} rx 4096 tx 4096 2>/dev/null",
                        shell=True
                    )
                    
                    # Включаем все offloads
                    subprocess.run(
                        f"ethtool -K {dev.name} tx on rx on tso on gso on gro on 2>/dev/null",
                        shell=True
                    )
                    
                    logger.info(f"✅ Сетевые оптимизации для {dev.name}")
                except:
                    pass
    
    def _update_kvm_resources(self):
        """Обновление информации о ресурсах KVM"""
        try:
            # Память
            mem = psutil.virtual_memory()
            self.kvm_resources.memory_total = mem.total // (1024 * 1024)
            self.kvm_resources.memory_available = mem.available // (1024 * 1024)
            self.kvm_resources.memory_used = mem.used // (1024 * 1024)
            
            # CPU
            self.kvm_resources.cpu_count = psutil.cpu_count()
            self.kvm_resources.cpu_usage = psutil.cpu_percent(interval=0.1)
            
            # VirtIO устройства
            self.kvm_resources.virtio_net_count = sum(
                1 for d in self.virtio_devices if d.type == KVMVirtIOType.NET
            )
            self.kvm_resources.virtio_blk_count = sum(
                1 for d in self.virtio_devices if d.type == KVMVirtIOType.BLK
            )
            
            # KSM статистика
            try:
                with open("/sys/kernel/mm/ksm/pages_sharing", "r") as f:
                    sharing = int(f.read().strip())
                with open("/sys/kernel/mm/ksm/pages_shared", "r") as f:
                    shared = int(f.read().strip())
                
                if shared > 0:
                    self.kvm_resources.ksm_sharing = sharing / shared
            except:
                pass
            
        except Exception as e:
            logger.error(f"❌ Ошибка обновления ресурсов KVM: {e}")
    
    # ========================================================================
    # NFTABLES МЕТОДЫ (ЧИСТАЯ АРХИТЕКТУРА)
    # ========================================================================
    
    def _init_nftables(self) -> bool:
        """Инициализация nftables (чистая, без iptables legacy)"""
        if self.nftables_initialized:
            return True
        
        try:
            # Проверяем наличие nft
            if not self._check_nftables():
                logger.error("❌ nftables не установлен")
                return False
            
            # Очищаем все legacy iptables правила
            self._flush_iptables_legacy()
            
            # Инициализируем базовые таблицы
            self._create_base_tables()
            
            self.nftables_initialized = True
            logger.info("✅ nftables инициализирован")
            return True
            
        except Exception as e:
            logger.error(f"❌ Ошибка инициализации nftables: {e}")
            return False
    
    def _check_nftables(self) -> bool:
        """Проверка наличия nftables"""
        result = subprocess.run(
            "command -v nft >/dev/null && nft list tables >/dev/null 2>&1",
            shell=True
        )
        return result.returncode == 0
    
    def _flush_iptables_legacy(self):
        """Очистка всех legacy iptables правил для избежания конфликтов"""
        logger.info("🧹 Очистка legacy iptables правил...")
        
        tables = ["filter", "nat", "mangle", "raw", "security"]
        for table in tables:
            subprocess.run(f"iptables -t {table} -F 2>/dev/null", shell=True)
            subprocess.run(f"iptables -t {table} -X 2>/dev/null", shell=True)
            subprocess.run(f"ip6tables -t {table} -F 2>/dev/null", shell=True)
            subprocess.run(f"ip6tables -t {table} -X 2>/dev/null", shell=True)
    
    def _create_base_tables(self):
        """Создание базовых таблиц nftables"""
        rules = """
# SENTINEL OS KVM - Base nftables Configuration
flush ruleset

table inet sentinel {
    set geoip_ru {
        type ipv4_addr
        flags interval
    }
    
    set geoip_su {
        type ipv4_addr
        flags interval
    }
    
    set ports_direct {
        type inet_service
        elements = { 6881-6889 }
    }
    
    set ips_direct {
        type ipv4_addr
        elements = { 192.168.1.11 }
    }
    
    chain prerouting {
        type filter hook prerouting priority -150; policy accept;
        
        # Прямой доступ для GEOIP
        ip saddr @geoip_ru meta mark set 0x00000001
        ip saddr @geoip_su meta mark set 0x00000001
        
        # Прямой доступ для торрентов
        tcp dport @ports_direct meta mark set 0x00000001
        udp dport @ports_direct meta mark set 0x00000001
        
        # Прямой доступ для IP сервера
        ip saddr @ips_direct meta mark set 0x00000001
        ip daddr @ips_direct meta mark set 0x00000001
    }
    
    chain output {
        type route hook output priority -150; policy accept;
        meta mark 0x00000001 return
    }
}

table inet sentinel_dns {
    chain output {
        type filter hook output priority -160; policy accept;
        
        # Блокировка обычного DNS
        udp dport 53 reject with icmp port-unreachable
        tcp dport 53 reject with tcp reset
        
        # Разрешаем только локальный DNS
        ip daddr 127.0.0.1 udp dport 53 accept
        ip daddr 127.0.0.1 tcp dport 53 accept
    }
}
"""
        
        # Применяем правила
        rules_file = CONFIG_DIR / "nftables-base.nft"
        with open(rules_file, 'w') as f:
            f.write(rules)
        
        subprocess.run(f"nft -f {rules_file}", shell=True, check=True)
        logger.info("✅ Базовые nftables таблицы созданы")
    
    # ========================================================================
    # МЕТОДЫ УПРАВЛЕНИЯ РЕСУРСАМИ
    # ========================================================================
    
    def check_resources(self, protocol: str) -> bool:
        """Проверка доступности ресурсов для протокола"""
        self._update_kvm_resources()
        
        # Проверка памяти
        if protocol in ["adguardhome", "xray", "hysteria2"]:
            if self.kvm_resources.memory_available < 512:
                logger.error(f"❌ Недостаточно памяти для {protocol}: {self.kvm_resources.memory_available}MB")
                return False
        
        # Проверка CPU для многопоточных протоколов
        if protocol in ["xray", "sing-box"]:
            if self.kvm_resources.cpu_usage > 80:
                logger.warning(f"⚠️ Высокая загрузка CPU для {protocol}: {self.kvm_resources.cpu_usage}%")
        
        return True
    
    def set_memory_limit(self, protocol: str, limit_mb: int):
        """Установка лимита памяти для протокола (cgroups)"""
        if protocol not in self.protocols:
            return
        
        try:
            pid = self._get_protocol_pid(protocol)
            if pid:
                # Используем cgroups для ограничения памяти
                cgroup_path = f"/sys/fs/cgroup/memory/sentinel/{protocol}"
                os.makedirs(cgroup_path, exist_ok=True)
                
                with open(f"{cgroup_path}/memory.limit_in_bytes", "w") as f:
                    f.write(str(limit_mb * 1024 * 1024))
                
                with open(f"{cgroup_path}/tasks", "w") as f:
                    f.write(str(pid))
                
                logger.info(f"✅ Лимит памяти {limit_mb}MB установлен для {protocol}")
        except Exception as e:
            logger.error(f"❌ Ошибка установки лимита памяти: {e}")
    
    # ========================================================================
    # ПАРСИНГ КЛЮЧЕЙ (ОПТИМИЗИРОВАННЫЙ)
    # ========================================================================
    
    def parse_key(self, protocol: str, key_data: str) -> Dict[str, Any]:
        """Парсинг ключа с KVM-специфичными проверками"""
        logger.info(f"🔑 Парсинг ключа для протокола: {protocol}")
        
        result = {
            "protocol": protocol,
            "parsed": False,
            "timestamp": datetime.now().isoformat(),
            "kvm_optimized": True
        }
        
        # Проверка ресурсов перед парсингом
        if not self.check_resources(protocol):
            result["errors"] = ["Недостаточно ресурсов KVM"]
            return result
        
        # Определяем протокол автоматически
        if protocol == "auto":
            protocol = self._detect_protocol(key_data)
            result["protocol"] = protocol
        
        # Вызываем соответствующий парсер
        try:
            if protocol == "wireguard":
                parsed = self._parse_wireguard(key_data)
            elif protocol == "amneziawg":
                parsed = self._parse_amneziawg(key_data)
            elif protocol == "xray":
                parsed = self._parse_xray(key_data)
            elif protocol == "shadowsocks":
                parsed = self._parse_shadowsocks(key_data)
            elif protocol == "trojan":
                parsed = self._parse_trojan(key_data)
            else:
                parsed = self._parse_generic(key_data)
            
            result.update(parsed)
            result["parsed"] = True
            
            # Добавляем KVM-специфичные оптимизации
            result["kvm_optimizations"] = self._get_kvm_optimizations(protocol)
            
        except Exception as e:
            logger.error(f"❌ Ошибка парсинга: {e}")
            result["errors"] = [str(e)]
        
        return result
    
    def _parse_wireguard(self, data: str) -> Dict[str, Any]:
        """Парсинг WireGuard с KVM-оптимизациями"""
        result = {
            "type": "wireguard",
            "interface": {},
            "peers": [],
            "kvm_optimizations": {
                "virtio_net_queues": self._get_optimal_queues(),
                "multiqueue": True
            }
        }
        
        # Парсим конфиг
        current_section = None
        current_peer = {}
        
        for line in data.split('\n'):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            if line.startswith('[') and line.endswith(']'):
                current_section = line[1:-1]
                if current_section == "Peer":
                    if current_peer:
                        result["peers"].append(current_peer)
                    current_peer = {}
                continue
            
            if '=' in line:
                key, value = line.split('=', 1)
                key = key.strip().lower()
                value = value.strip()
                
                if current_section == "Interface":
                    result["interface"][key] = value
                elif current_section == "Peer":
                    current_peer[key] = value
        
        if current_peer:
            result["peers"].append(current_peer)
        
        return result
    
    def _get_optimal_queues(self) -> int:
        """Получение оптимального количества очередей для VirtIO"""
        cpu_count = psutil.cpu_count()
        return min(cpu_count, 8)  # Максимум 8 очередей для VirtIO
    
    def _get_kvm_optimizations(self, protocol: str) -> Dict[str, Any]:
        """Получение KVM-специфичных оптимизаций для протокола"""
        optimizations = {
            "virtio_enabled": len(self.virtio_devices) > 0,
            "cpu_count": self.kvm_resources.cpu_count,
            "memory_mb": self.kvm_resources.memory_total
        }
        
        # Специфичные для протокола оптимизации
        if protocol in ["wireguard", "amneziawg"]:
            optimizations["multiqueue"] = True
            optimizations["rx_queues"] = self._get_optimal_queues()
        
        elif protocol in ["xray", "sing-box"]:
            optimizations["tcp_fastopen"] = True
            optimizations["bbr_congestion"] = True
        
        return optimizations
    
    # ========================================================================
    # УПРАВЛЕНИЕ СЛУЖБАМИ (С ПРОВЕРКОЙ РЕСУРСОВ)
    # ========================================================================
    
    def start_protocol(self, protocol: str) -> bool:
        """Запуск протокола с проверкой ресурсов KVM"""
        logger.info(f"▶️ Запуск протокола: {protocol}")
        
        if protocol not in self.protocols:
            logger.error(f"❌ Протокол {protocol} не найден")
            return False
        
        # Проверка ресурсов
        if not self.check_resources(protocol):
            self.protocols[protocol].status = ProtocolStatus.ERROR
            self.protocols[protocol].last_error = "Insufficient KVM resources"
            return False
        
        # Проверка nftables
        if not self.nftables_initialized:
            self._init_nftables()
        
        proto_config = self.protocols[protocol]
        proto_config.status = ProtocolStatus.STARTING
        
        try:
            # Запуск через systemd или init.d
            if Path(f"/etc/init.d/{protocol}").exists():
                result = subprocess.run(
                    f"/etc/init.d/{protocol} start",
                    shell=True, capture_output=True, text=True
                )
                
                if result.returncode == 0:
                    proto_config.status = ProtocolStatus.RUNNING
                    proto_config.start_time = datetime.now()
                    
                    # Установка лимитов для ресурсоемких протоколов
                    if protocol in ["adguardhome", "xray", "hysteria2"]:
                        self.set_memory_limit(protocol, 512)
                    
                    logger.info(f"✅ Протокол {protocol} запущен")
                    return True
                else:
                    proto_config.status = ProtocolStatus.ERROR
                    proto_config.last_error = result.stderr
                    logger.error(f"❌ Ошибка запуска: {result.stderr}")
                    return False
            
        except Exception as e:
            proto_config.status = ProtocolStatus.ERROR
            proto_config.last_error = str(e)
            logger.error(f"❌ Ошибка: {e}")
            return False
    
    def stop_protocol(self, protocol: str) -> bool:
        """Остановка протокола"""
        logger.info(f"⏹️ Остановка протокола: {protocol}")
        
        if protocol not in self.protocols:
            logger.error(f"❌ Протокол {protocol} не найден")
            return False
        
        proto_config = self.protocols[protocol]
        proto_config.status = ProtocolStatus.STOPPING
        
        try:
            if Path(f"/etc/init.d/{protocol}").exists():
                result = subprocess.run(
                    f"/etc/init.d/{protocol} stop",
                    shell=True, capture_output=True, text=True
                )
                
                if result.returncode == 0:
                    proto_config.status = ProtocolStatus.STOPPED
                    proto_config.start_time = None
                    
                    # Очистка cgroups
                    cgroup_path = f"/sys/fs/cgroup/memory/sentinel/{protocol}"
                    if Path(cgroup_path).exists():
                        subprocess.run(f"rmdir {cgroup_path}", shell=True)
                    
                    logger.info(f"✅ Протокол {protocol} остановлен")
                    return True
                    
        except Exception as e:
            logger.error(f"❌ Ошибка: {e}")
        
        return False
    
    def status(self) -> Dict[str, Any]:
        """Получение статуса системы с KVM-метриками"""
        self._update_kvm_resources()
        
        result = {
            "version": self.version,
            "codename": self.codename,
            "uptime": self._get_uptime(),
            "kvm": {
                "virt_type": self._get_virt_type(),
                "resources": asdict(self.kvm_resources),
                "virtio_devices": [asdict(d) for d in self.virtio_devices],
                "nftables_initialized": self.nftables_initialized
            },
            "protocols": {},
            "system": self._get_system_info()
        }
        
        for name, proto in self.protocols.items():
            pid = self._get_protocol_pid(name)
            result["protocols"][name] = {
                "type": proto.type.value,
                "status": proto.status.value,
                "pid": pid,
                "memory": self._get_process_memory(pid) if pid else None,
                "cpu": self._get_process_cpu(pid) if pid else None,
                "start_time": proto.start_time.isoformat() if proto.start_time else None
            }
        
        return result
    
    # ========================================================================
    # NFTABLES ПРАВИЛА (ЧИСТАЯ РЕАЛИЗАЦИЯ)
    # ========================================================================
    
    def apply_rules(self) -> bool:
        """Применение правил маршрутизации через чистый nftables"""
        if not self.nftables_initialized:
            self._init_nftables()
        
        try:
            rules_file = CONFIG_DIR / "nftables-rules.nft"
            
            with open(rules_file, 'w') as f:
                f.write(self._generate_rules())
            
            result = subprocess.run(
                f"nft -f {rules_file}",
                shell=True, capture_output=True, text=True
            )
            
            if result.returncode == 0:
                logger.info("✅ Правила nftables применены")
                return True
            else:
                logger.error(f"❌ Ошибка: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"❌ Ошибка: {e}")
            return False
    
    def _generate_rules(self) -> str:
        """Генерация правил nftables"""
        rules = f"""# SENTINEL OS KVM - nftables Rules
# Generated: {datetime.now().isoformat()}

flush ruleset

table inet sentinel {{
    # Маркировка трафика
    chain mangle {{
        type filter hook prerouting priority -150; policy accept;
        
        # GEOIP (загружается динамически)
        ip saddr {{ 95.0.0.0/8, 94.0.0.0/8 }} meta mark set 0x01
    }}
    
    # Форвардинг
    chain forward {{
        type filter hook forward priority 0; policy drop;
        
        # Разрешаем маркированный трафик
        meta mark 0x01 accept
        
        # Разрешаем VPN трафик
        oifname "wg0" accept
        oifname "tun0" accept
        oifname "tap0" accept
        
        # Established connections
        ct state established,related accept
    }}
}}

table inet sentinel_dns {{
    # Защита от DNS утечек
    chain output {{
        type filter hook output priority -160; policy accept;
        
        # Блокируем прямой DNS в WAN
        ip daddr != 127.0.0.1 udp dport 53 drop
        ip daddr != 127.0.0.1 tcp dport 53 drop
    }}
}}
"""
        return rules
    
    # ========================================================================
    # ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
    # ========================================================================
    
    def _load_configuration(self):
        """Загрузка конфигурации"""
        if MAIN_CONFIG.exists():
            try:
                with open(MAIN_CONFIG, 'r') as f:
                    config = yaml.safe_load(f)
                    
                if 'protocols' in config:
                    for name, proto_config in config['protocols'].items():
                        self.protocols[name] = ProtocolConfig(
                            name=name,
                            type=ProtocolType(proto_config.get('type', 'wireguard')),
                            enabled=proto_config.get('enabled', False),
                            auto_start=proto_config.get('auto_start', False)
                        )
                
                logger.info("✅ Конфигурация загружена")
            except Exception as e:
                logger.error(f"❌ Ошибка загрузки: {e}")
    
    def _get_protocol_pid(self, protocol: str) -> Optional[int]:
        """Получение PID процесса"""
        try:
            result = subprocess.run(
                f"pgrep -f '{protocol}'",
                shell=True, capture_output=True, text=True
            )
            if result.stdout:
                return int(result.stdout.strip().split('\n')[0])
        except:
            pass
        return None
    
    def _get_process_memory(self, pid: int) -> Optional[float]:
        """Получение использования памяти процессом"""
        try:
            process = psutil.Process(pid)
            return process.memory_info().rss / 1024 / 1024
        except:
            return None
    
    def _get_process_cpu(self, pid: int) -> Optional[float]:
        """Получение использования CPU процессом"""
        try:
            process = psutil.Process(pid)
            return process.cpu_percent(interval=0.1)
        except:
            return None
    
    def _get_uptime(self) -> str:
        """Получение времени работы"""
        try:
            with open('/proc/uptime', 'r') as f:
                seconds = float(f.readline().split()[0])
                hours = int(seconds // 3600)
                minutes = int((seconds % 3600) // 60)
                return f"{hours}ч {minutes}м"
        except:
            return "N/A"
    
    def _get_system_info(self) -> Dict[str, Any]:
        """Получение системной информации"""
        return {
            "hostname": socket.gethostname(),
            "load": psutil.getloadavg(),
            "connections": len(psutil.net_connections())
        }
    
    def _signal_handler(self, sig, frame):
        """Обработчик сигналов"""
        logger.info("🛑 Получен сигнал завершения")
        self.running = False
        
        for protocol in self.protocols:
            if self.protocols[protocol].status == ProtocolStatus.RUNNING:
                self.stop_protocol(protocol)
        
        sys.exit(0)

# ============================================================================
# CLI ИНТЕРФЕЙС
# ============================================================================

def main():
    """Точка входа"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description=f"SENTINEL OS KVM v{SENTINEL_VERSION}"
    )
    
    parser.add_argument(
        'command',
        choices=['status', 'start', 'stop', 'restart', 'apply-rules', 'kvm-info'],
        help='Команда для выполнения'
    )
    
    parser.add_argument('--protocol', '-p', help='Протокол')
    parser.add_argument('--json', action='store_true', help='JSON вывод')
    
    args = parser.parse_args()
    
    orchestrator = SentinelKVMOrchestrator()
    
    if args.command == 'status':
        result = orchestrator.status()
        if args.json:
            print(json.dumps(result, indent=2, default=str))
        else:
            print(json.dumps(result, indent=2, default=str))
    
    elif args.command == 'kvm-info':
        result = orchestrator.status()
        print("\n🔍 KVM Information:")
        print(json.dumps(result['kvm'], indent=2, default=str))
    
    elif args.command == 'apply-rules':
        success = orchestrator.apply_rules()
        print(f"{'✅' if success else '❌'} Правила применены")
    
    elif args.command in ['start', 'stop', 'restart']:
        if not args.protocol:
            print("❌ Укажите протокол: --protocol")
            sys.exit(1)
        
        if args.command == 'start':
            success = orchestrator.start_protocol(args.protocol)
        elif args.command == 'stop':
            success = orchestrator.stop_protocol(args.protocol)
        else:
            orchestrator.stop_protocol(args.protocol)
            time.sleep(1)
            success = orchestrator.start_protocol(args.protocol)
        
        print(f"{'✅' if success else '❌'} {args.command} {args.protocol}")

if __name__ == "__main__":
    main()