#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
SENTINEL OS KVM - nftables Router
==================================
Чистая реализация маршрутизации на nftables для KVM
Без использования iptables, полная интеграция с VirtIO
"""

import os
import sys
import json
import time
import logging
import subprocess
import ipaddress
import urllib.request
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple, Set
from datetime import datetime
import threading
import hashlib

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("sentinel-nftables-kvm")

class KVMNFTablesRouter:
    """
    Маршрутизатор на чистом nftables для KVM.
    Полная замена iptables с поддержкой VirtIO оптимизаций.
    """
    
    def __init__(self, kvm_resources: Dict[str, Any] = None):
        self.kvm_resources = kvm_resources or self._detect_kvm_resources()
        self.nftables_bin = self._find_nftables()
        self.rules_dir = Path("/etc/nftables.d")
        self.rules_dir.mkdir(parents=True, exist_ok=True)
        
        # GEOIP базы
        self.geoip_dir = Path("/etc/nftables/geoip")
        self.geoip_dir.mkdir(parents=True, exist_ok=True)
        
        # Наборы правил
        self.rulesets = {
            "base": self.rules_dir / "00-base.nft",
            "geoip": self.rules_dir / "10-geoip.nft",
            "vpn": self.rules_dir / "20-vpn.nft",
            "dns": self.rules_dir / "30-dns.nft",
            "protection": self.rules_dir / "40-protection.nft",
            "custom": self.rules_dir / "99-custom.nft"
        }
        
        # Проверка nftables
        self._check_nftables()
        
        logger.info(f"✅ KVM NFTables Router инициализирован")
        logger.info(f"📊 nftables: {self.nftables_bin}")
    
    def _detect_kvm_resources(self) -> Dict[str, Any]:
        """Определение ресурсов KVM для оптимизации"""
        import psutil
        return {
            "cpu_count": psutil.cpu_count(),
            "memory_mb": psutil.virtual_memory().total // (1024 * 1024),
            "virtio_net": self._check_virtio_net(),
            "virtio_queues": self._get_virtio_queues()
        }
    
    def _check_virtio_net(self) -> bool:
        """Проверка VirtIO сетевых устройств"""
        for dev in ["eth0", "eth1", "ens3", "ens4"]:
            path = f"/sys/class/net/{dev}/device/driver"
            if os.path.exists(path):
                driver = os.path.realpath(path).split('/')[-1]
                if "virtio" in driver:
                    return True
        return False
    
    def _get_virtio_queues(self) -> int:
        """Получение количества очередей VirtIO"""
        try:
            for dev in ["eth0", "eth1", "ens3", "ens4"]:
                queues_path = f"/sys/class/net/{dev}/queues"
                if os.path.exists(queues_path):
                    rx_queues = len(list(Path(queues_path).glob("rx-*")))
                    if rx_queues > 0:
                        return rx_queues
        except:
            pass
        return 4
    
    def _find_nftables(self) -> str:
        """Поиск пути к nftables"""
        for path in ["/usr/sbin/nft", "/sbin/nft", "/usr/bin/nft"]:
            if os.path.exists(path):
                return path
        raise RuntimeError("nftables не найден")
    
    def _check_nftables(self):
        """Проверка наличия и работоспособности nftables"""
        result = subprocess.run(
            f"{self.nftables_bin} list tables 2>/dev/null",
            shell=True, capture_output=True
        )
        if result.returncode != 0:
            logger.warning("⚠️ nftables не инициализирован, создаю базовые таблицы")
            self._init_nftables()
    
    def _init_nftables(self):
        """Инициализация базовых таблиц nftables"""
        rules = """
# SENTINEL OS KVM - Base nftables Configuration
flush ruleset

table inet sentinel {
    # Базовые наборы
    set geoip_direct {
        type ipv4_addr
        flags interval
        timeout 1d
        gc-interval 1h
    }
    
    set ports_direct {
        type inet_service
        flags constant
        elements = { 6881-6889 }
    }
    
    set ips_direct {
        type ipv4_addr
        flags constant
        elements = { 192.168.1.11 }
    }
    
    # Цепочка предварительной маршрутизации
    chain prerouting {
        type filter hook prerouting priority -150; policy accept;
        
        # Прямой доступ для GEOIP
        ip saddr @geoip_direct meta mark set 0x00000001
        
        # Прямой доступ для торрентов
        tcp dport @ports_direct meta mark set 0x00000001
        udp dport @ports_direct meta mark set 0x00000001
        
        # Прямой доступ для IP сервера
        ip saddr @ips_direct meta mark set 0x00000001
        ip daddr @ips_direct meta mark set 0x00000001
    }
    
    # Цепочка форвардинга
    chain forward {
        type filter hook forward priority 0; policy drop;
        
        # Разрешаем маркированный трафик
        meta mark 0x00000001 accept
        
        # Разрешаем VPN трафик
        oifname { "wg0", "wg1", "tun0", "tap0" } accept
        iifname { "wg0", "wg1", "tun0", "tap0" } accept
        
        # Разрешаем установленные соединения
        ct state { established, related } accept
    }
    
    # Цепочка вывода
    chain output {
        type route hook output priority -150; policy accept;
        meta mark 0x00000001 return
    }
}

table inet sentinel_dns {
    # Защита от DNS утечек
    chain output {
        type filter hook output priority -160; policy accept;
        
        # Блокируем прямой DNS в WAN
        ip daddr != 127.0.0.1 udp dport 53 drop
        ip daddr != 127.0.0.1 tcp dport 53 drop
        ip6 daddr != ::1 udp dport 53 drop
        ip6 daddr != ::1 tcp dport 53 drop
        
        # Разрешаем локальный DNS
        ip daddr 127.0.0.1 udp dport 53 accept
        ip daddr 127.0.0.1 tcp dport 53 accept
        ip6 daddr ::1 udp dport 53 accept
        ip6 daddr ::1 tcp dport 53 accept
    }
}
"""
        
        self._apply_rules_string(rules)
        logger.info("✅ Базовые nftables таблицы созданы")
    
    def _apply_rules_string(self, rules: str) -> bool:
        """Применение правил из строки"""
        try:
            result = subprocess.run(
                f"{self.nftables_bin} -f -",
                input=rules, shell=True, capture_output=True, text=True
            )
            if result.returncode != 0:
                logger.error(f"❌ Ошибка применения правил: {result.stderr}")
                return False
            return True
        except Exception as e:
            logger.error(f"❌ Ошибка: {e}")
            return False
    
    def _apply_rules_file(self, filepath: Path) -> bool:
        """Применение правил из файла"""
        try:
            result = subprocess.run(
                f"{self.nftables_bin} -f {filepath}",
                shell=True, capture_output=True, text=True
            )
            if result.returncode != 0:
                logger.error(f"❌ Ошибка в {filepath}: {result.stderr}")
                return False
            return True
        except Exception as e:
            logger.error(f"❌ Ошибка: {e}")
            return False
    
    def update_geoip(self, countries: List[str] = None):
        """
        Обновление GEOIP баз для nftables.
        Использует ipdeny.com для загрузки IP ranges.
        """
        if countries is None:
            countries = ["ru", "su", "by", "kz"]
        
        logger.info(f"📥 Загрузка GEOIP баз для {countries}")
        
        for country in countries:
            try:
                # Загрузка списка IP
                url = f"https://www.ipdeny.com/ipblocks/data/countries/{country}.zone"
                response = urllib.request.urlopen(url, timeout=30)
                ips = response.read().decode('utf-8').strip().split('\n')
                
                # Сохранение в файл
                geo_file = self.geoip_dir / f"{country}.ipv4"
                with open(geo_file, 'w') as f:
                    f.write('\n'.join(ips))
                
                logger.info(f"✅ {country}: {len(ips)} сетей")
                
                # Создание nftables набора
                self._create_geoip_set(country, ips)
                
            except Exception as e:
                logger.error(f"❌ Ошибка загрузки {country}: {e}")
        
        logger.info("✅ GEOIP базы обновлены")
    
    def _create_geoip_set(self, country: str, ips: List[str]):
        """Создание nftables набора для страны"""
        # Группируем IP для эффективности
        networks = []
        for ip in ips[:1000]:  # Ограничение для производительности
            try:
                network = ipaddress.ip_network(ip.strip())
                networks.append(str(network))
            except:
                pass
        
        # Создаем временный файл с набором
        set_file = self.geoip_dir / f"{country}.nft"
        with open(set_file, 'w') as f:
            f.write(f"""
# GEOIP set for {country}
add element inet sentinel geoip_direct {{ {', '.join(networks)} }}
""")
        
        # Добавляем в существующий набор
        self._apply_rules_file(set_file)
    
    def add_vpn_interface(self, iface: str, table: str = "inet", chain: str = "forward"):
        """Добавление VPN интерфейса в правила форвардинга"""
        rules = f"""
add rule {table} sentinel {chain} oifname {{ "{iface}" }} accept
add rule {table} sentinel {chain} iifname {{ "{iface}" }} accept
"""
        self._apply_rules_string(rules)
        logger.info(f"✅ VPN интерфейс {iface} добавлен в маршрутизацию")
    
    def remove_vpn_interface(self, iface: str, table: str = "inet", chain: str = "forward"):
        """Удаление VPN интерфейса из правил"""
        # В nftables нет прямого удаления, нужно перезагрузить всю таблицу
        self.reload_all_rules()
        logger.info(f"🔄 Правила перезагружены, интерфейс {iface} удален")
    
    def add_direct_ip(self, ip: str):
        """Добавление IP для прямого доступа"""
        rules = f"add element inet sentinel ips_direct {{ {ip} }}"
        self._apply_rules_string(rules)
        logger.info(f"✅ IP {ip} добавлен для прямого доступа")
    
    def add_direct_port(self, port: int, proto: str = "tcp"):
        """Добавление порта для прямого доступа"""
        rules = f"add element inet sentinel ports_direct {{ {port} }}"
        self._apply_rules_string(rules)
        logger.info(f"✅ Порт {port}/{proto} добавлен для прямого доступа")
    
    def enable_dns_leak_protection(self):
        """Включение защиты от DNS утечек"""
        rules = """
# DNS Leak Protection
add table inet sentinel_dns
add chain inet sentinel_dns output { type filter hook output priority -160; policy accept; }
add rule inet sentinel_dns output ip daddr != 127.0.0.1 udp dport 53 drop
add rule inet sentinel_dns output ip daddr != 127.0.0.1 tcp dport 53 drop
add rule inet sentinel_dns output ip6 daddr != ::1 udp dport 53 drop
add rule inet sentinel_dns output ip6 daddr != ::1 tcp dport 53 drop
"""
        self._apply_rules_string(rules)
        logger.info("✅ Защита от DNS утечек включена")
    
    def enable_ipv6_leak_protection(self):
        """Включение защиты от IPv6 утечек"""
        rules = """
# IPv6 Leak Protection
add table inet sentinel_ipv6
add chain inet sentinel_ipv6 output { type filter hook output priority -150; policy accept; }
add rule inet sentinel_ipv6 output ip6 daddr { ::/0 } reject with icmpv6 addr-unreachable
"""
        self._apply_rules_string(rules)
        logger.info("✅ Защита от IPv6 утечек включена")
    
    def enable_port_stealth(self):
        """Включение стелс-режима (скрытие открытых портов)"""
        rules = """
# Port Stealth Mode
add table inet sentinel_stealth
add chain inet sentinel_stealth input { type filter hook input priority -150; policy drop; }

# Разрешаем только established соединения
add rule inet sentinel_stealth input ct state { established, related } accept

# Разрешаем локальный трафик
add rule inet sentinel_stealth input iif "lo" accept

# Разрешаем ICMP
add rule inet sentinel_stealth input ip protocol icmp accept
add rule inet sentinel_stealth input ip6 protocol icmpv6 accept
"""
        self._apply_rules_string(rules)
        logger.info("✅ Стелс-режим включен")
    
    def enable_ttl_fuzzing(self, mode: str = "random"):
        """Включение TTL фаззинга для обхода DPI"""
        if mode == "random":
            ttl_rules = "ip ttl set 64-128"
        elif mode == "windows":
            ttl_rules = "ip ttl set 128"
        elif mode == "linux":
            ttl_rules = "ip ttl set 64"
        else:
            ttl_rules = "ip ttl set 65"
        
        rules = f"""
# TTL Fuzzing
add table inet sentinel_ttl
add chain inet sentinel_ttl postrouting {{ type filter hook postrouting priority -150; policy accept; }}
add rule inet sentinel_ttl postrouting {ttl_rules}
"""
        self._apply_rules_string(rules)
        logger.info(f"✅ TTL фаззинг включен (режим: {mode})")
    
    def enable_mtu_randomization(self):
        """Включение MTU рандомизации"""
        # MTU рандомизация требует изменения на интерфейсах
        for dev in ["eth0", "eth1", "ens3", "ens4"]:
            if os.path.exists(f"/sys/class/net/{dev}"):
                import random
                new_mtu = random.randint(1300, 1500)
                subprocess.run(f"ip link set dev {dev} mtu {new_mtu}", shell=True)
                logger.info(f"✅ MTU для {dev}: {new_mtu}")
    
    def enable_fragment_obfuscation(self):
        """Включение обфускации IP фрагментов"""
        rules = """
# IP Fragment Obfuscation
add table inet sentinel_frag
add chain inet sentinel_frag output { type filter hook output priority -150; policy accept; }

# Обфускация идентификаторов фрагментов
add rule inet sentinel_frag output ip frag-off & 0x1fff != 0 ip id set 0

# Принудительная фрагментация для больших UDP пакетов
add rule inet sentinel_frag output udp length > 500 ip frag-off set 0x2000
"""
        self._apply_rules_string(rules)
        logger.info("✅ Обфускация фрагментов включена")
    
    def create_vpn_bypass_rule(self, dest_ip: str, dest_port: int = None):
        """Создание правила обхода VPN для конкретного назначения"""
        if dest_port:
            rule = f"add rule inet sentinel output ip daddr {dest_ip} tcp dport {dest_port} meta mark set 0x00000001"
        else:
            rule = f"add rule inet sentinel output ip daddr {dest_ip} meta mark set 0x00000001"
        
        self._apply_rules_string(rule)
        logger.info(f"✅ Правило обхода VPN создано для {dest_ip}")
    
    def create_port_forward(self, public_port: int, private_ip: str, private_port: int, proto: str = "tcp"):
        """Создание проброса портов"""
        rules = f"""
# Port Forward {public_port} -> {private_ip}:{private_port}
add table inet sentinel_nat
add chain inet sentinel_nat prerouting {{ type nat hook prerouting priority -100; policy accept; }}
add chain inet sentinel_nat postrouting {{ type nat hook postrouting priority 100; policy accept; }}

add rule inet sentinel_nat prerouting {proto} dport {public_port} dnat to {private_ip}:{private_port}
add rule inet sentinel_nat postrouting ip daddr {private_ip} masquerade
"""
        self._apply_rules_string(rules)
        logger.info(f"✅ Проброс портов создан: {public_port} -> {private_ip}:{private_port}")
    
    def get_ruleset(self) -> Dict[str, Any]:
        """Получение текущего набора правил"""
        result = subprocess.run(
            f"{self.nftables_bin} list ruleset",
            shell=True, capture_output=True, text=True
        )
        
        if result.returncode == 0:
            return {
                "ruleset": result.stdout,
                "tables": self._parse_tables(result.stdout)
            }
        return {"error": result.stderr}
    
    def _parse_tables(self, ruleset: str) -> List[str]:
        """Парсинг списка таблиц из ruleset"""
        tables = []
        for line in ruleset.split('\n'):
            if line.startswith("table"):
                parts = line.split()
                if len(parts) >= 3:
                    tables.append(f"{parts[1]} {parts[2]}")
        return tables
    
    def reload_all_rules(self):
        """Перезагрузка всех правил"""
        self._init_nftables()
        
        # Загружаем все файлы правил
        for ruleset in sorted(self.rulesets.values()):
            if ruleset.exists():
                self._apply_rules_file(ruleset)
        
        logger.info("✅ Все правила перезагружены")
    
    def save_ruleset(self, name: str = "current"):
        """Сохранение текущего набора правил"""
        result = subprocess.run(
            f"{self.nftables_bin} list ruleset",
            shell=True, capture_output=True, text=True
        )
        
        if result.returncode == 0:
            save_file = self.rules_dir / f"saved-{name}.nft"
            with open(save_file, 'w') as f:
                f.write(result.stdout)
            logger.info(f"✅ Правила сохранены в {save_file}")
            return str(save_file)
        
        return None
    
    def restore_ruleset(self, name: str = "current"):
        """Восстановление сохраненного набора правил"""
        save_file = self.rules_dir / f"saved-{name}.nft"
        if save_file.exists():
            self._apply_rules_file(save_file)
            logger.info(f"✅ Правила восстановлены из {save_file}")
            return True
        return False
    
    def clear_all_rules(self):
        """Очистка всех правил"""
        subprocess.run(f"{self.nftables_bin} flush ruleset", shell=True)
        logger.info("✅ Все правила очищены")
    
    def get_statistics(self) -> Dict[str, Any]:
        """Получение статистики по правилам"""
        stats = {}
        
        # Счетчики для каждой цепочки
        result = subprocess.run(
            f"{self.nftables_bin} list counters",
            shell=True, capture_output=True, text=True
        )
        
        if result.returncode == 0:
            # Парсим счетчики
            for line in result.stdout.split('\n'):
                if "counter" in line and "packets" in line:
                    parts = line.split()
                    for i, part in enumerate(parts):
                        if part == "packets":
                            packets = int(parts[i+1])
                        if part == "bytes":
                            bytes_count = int(parts[i+1])
                    
                    # Извлекаем имя цепочки
                    if "chain" in line:
                        chain_match = re.search(r'chain\s+(\w+)', line)
                        if chain_match:
                            chain = chain_match.group(1)
                            stats[chain] = {
                                "packets": packets,
                                "bytes": bytes_count,
                                "bytes_mb": bytes_count / (1024 * 1024)
                            }
        
        return stats
    
    def create_systemd_service(self):
        """Создание systemd сервиса для загрузки правил при старте"""
        service_content = """[Unit]
Description=SENTINEL OS KVM nftables Rules
Before=network.target
After=systemd-modules-load.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/nftables.d/00-base.nft
ExecReload=/usr/sbin/nft -f /etc/nftables.d/00-base.nft
ExecStop=/usr/sbin/nft flush ruleset

[Install]
WantedBy=multi-user.target
"""
        service_file = Path("/etc/systemd/system/sentinel-nftables.service")
        with open(service_file, 'w') as f:
            f.write(service_content)
        
        subprocess.run("systemctl daemon-reload", shell=True)
        logger.info(f"✅ systemd сервис создан: {service_file}")


# ============================================================================
# ТЕСТОВЫЙ МОДУЛЬ
# ============================================================================

def test_nftables_router():
    """Тестирование маршрутизатора"""
    router = KVMNFTablesRouter()
    
    # Инициализация
    router._init_nftables()
    
    # Обновление GEOIP
    router.update_geoip(["ru", "su"])
    
    # Добавление VPN интерфейса
    router.add_vpn_interface("wg0")
    
    # Включение защиты
    router.enable_dns_leak_protection()
    router.enable_port_stealth()
    
    # Получение статистики
    stats = router.get_statistics()
    print(json.dumps(stats, indent=2))
    
    # Сохранение правил
    router.save_ruleset("test")


if __name__ == "__main__":
    test_nftables_router()