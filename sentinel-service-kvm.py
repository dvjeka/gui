#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
SENTINEL OS KVM - Service Manager
=================================
Управление службами с KVM-оптимизациями, cgroups и мониторингом
"""

import os
import sys
import json
import time
import signal
import logging
import subprocess
import psutil
import threading
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple
from datetime import datetime
import socket
import fcntl
import struct

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("sentinel-service-kvm")

class KVMServiceManager:
    """
    Менеджер служб с поддержкой KVM-оптимизаций.
    Управляет запуском, остановкой и мониторингом всех протоколов.
    """
    
    def __init__(self, kvm_resources: Dict[str, Any] = None):
        self.kvm_resources = kvm_resources or self._detect_kvm_resources()
        self.services: Dict[str, Dict[str, Any]] = {}
        self.cgroups_base = "/sys/fs/cgroup"
        self.sentinel_cgroup = f"{self.cgroups_base}/sentinel"
        self.running = False
        self.monitor_thread = None
        
        # Инициализация cgroups
        self._init_cgroups()
        
        logger.info(f"✅ KVM Service Manager инициализирован")
        logger.info(f"📊 Ресурсы: CPU={self.kvm_resources['cpu_count']}, "
                   f"RAM={self.kvm_resources['memory_mb']}MB")
    
    def _detect_kvm_resources(self) -> Dict[str, Any]:
        """Автоопределение ресурсов KVM"""
        resources = {
            "cpu_count": psutil.cpu_count(),
            "cpu_freq": psutil.cpu_freq().current if psutil.cpu_freq() else 0,
            "memory_mb": psutil.virtual_memory().total // (1024 * 1024),
            "memory_available_mb": psutil.virtual_memory().available // (1024 * 1024),
            "virtio_net": self._check_virtio_net(),
            "virtio_queues": self._get_virtio_queues(),
            "kvm_guest": self._is_kvm_guest()
        }
        return resources
    
    def _is_kvm_guest(self) -> bool:
        """Проверка, запущена ли система под KVM"""
        try:
            result = subprocess.run(
                "systemd-detect-virt 2>/dev/null || echo 'unknown'",
                shell=True, capture_output=True, text=True
            )
            return "kvm" in result.stdout.lower()
        except:
            return False
    
    def _check_virtio_net(self) -> bool:
        """Проверка наличия VirtIO сетевых устройств"""
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
        return min(self.kvm_resources.get("cpu_count", 4), 8)
    
    def _init_cgroups(self):
        """Инициализация cgroups для управления ресурсами"""
        try:
            # Создаем cgroup для Sentinel
            if not os.path.exists(self.sentinel_cgroup):
                os.makedirs(f"{self.sentinel_cgroup}/memory", exist_ok=True)
                os.makedirs(f"{self.sentinel_cgroup}/cpu", exist_ok=True)
                os.makedirs(f"{self.sentinel_cgroup}/blkio", exist_ok=True)
                
                # Включаем контроль памяти
                with open(f"{self.sentinel_cgroup}/memory/memory.use_hierarchy", "w") as f:
                    f.write("1")
                
                logger.info("✅ cgroups инициализированы")
        except Exception as e:
            logger.warning(f"⚠️ Не удалось инициализировать cgroups: {e}")
    
    def register_service(self, name: str, service_type: str, config: Dict[str, Any]):
        """Регистрация службы в менеджере"""
        self.services[name] = {
            "name": name,
            "type": service_type,
            "config": config,
            "status": "stopped",
            "pid": None,
            "start_time": None,
            "memory_usage": 0,
            "cpu_usage": 0,
            "restart_count": 0,
            "last_error": None,
            "cgroup": f"{self.sentinel_cgroup}/{name.replace('.', '_')}"
        }
        logger.info(f"📝 Зарегистрирована служба: {name} ({service_type})")
    
    def start_service(self, name: str) -> bool:
        """Запуск службы с KVM-оптимизациями"""
        if name not in self.services:
            logger.error(f"❌ Служба {name} не найдена")
            return False
        
        service = self.services[name]
        
        # Проверка ресурсов
        if not self._check_resources(name):
            service["last_error"] = "Insufficient resources"
            return False
        
        logger.info(f"▶️ Запуск службы: {name}")
        service["status"] = "starting"
        
        try:
            # Создаем cgroup для службы
            self._create_service_cgroup(name)
            
            # Запуск в зависимости от типа
            if service["type"] == "wireguard":
                success = self._start_wireguard(name, service)
            elif service["type"] == "openvpn":
                success = self._start_openvpn(name, service)
            elif service["type"] == "xray":
                success = self._start_xray(name, service)
            elif service["type"] == "shadowsocks":
                success = self._start_shadowsocks(name, service)
            elif service["type"] == "tor":
                success = self._start_tor(name, service)
            elif service["type"] in ["zapret", "byedpi", "goodbyedpi"]:
                success = self._start_dpi_bypass(name, service)
            else:
                success = self._start_generic(name, service)
            
            if success:
                service["status"] = "running"
                service["start_time"] = datetime.now()
                service["restart_count"] = 0
                
                # Применяем лимиты ресурсов
                self._apply_resource_limits(name)
                
                logger.info(f"✅ Служба {name} запущена")
                return True
            else:
                service["status"] = "error"
                service["last_error"] = "Start failed"
                return False
                
        except Exception as e:
            service["status"] = "error"
            service["last_error"] = str(e)
            logger.error(f"❌ Ошибка запуска {name}: {e}")
            return False
    
    def stop_service(self, name: str) -> bool:
        """Остановка службы"""
        if name not in self.services:
            logger.error(f"❌ Служба {name} не найдена")
            return False
        
        service = self.services[name]
        logger.info(f"⏹️ Остановка службы: {name}")
        service["status"] = "stopping"
        
        try:
            # Отправляем SIGTERM
            if service["pid"]:
                os.kill(service["pid"], signal.SIGTERM)
                
                # Ждем завершения
                for _ in range(10):
                    if not self._process_exists(service["pid"]):
                        break
                    time.sleep(0.5)
                else:
                    # Принудительное завершение
                    os.kill(service["pid"], signal.SIGKILL)
            
            # Удаляем cgroup
            self._remove_service_cgroup(name)
            
            service["status"] = "stopped"
            service["pid"] = None
            service["start_time"] = None
            
            logger.info(f"✅ Служба {name} остановлена")
            return True
            
        except Exception as e:
            service["status"] = "error"
            service["last_error"] = str(e)
            logger.error(f"❌ Ошибка остановки {name}: {e}")
            return False
    
    def _start_wireguard(self, name: str, service: Dict) -> bool:
        """Запуск WireGuard с KVM-оптимизациями"""
        config = service["config"]
        config_file = Path(f"/etc/wireguard/{name}.conf")
        
        # Создаем конфиг
        with open(config_file, 'w') as f:
            f.write("[Interface]\n")
            for key, value in config.get("interface", {}).items():
                f.write(f"{key} = {value}\n")
            
            f.write("\n[Peer]\n")
            for peer in config.get("peers", []):
                for key, value in peer.items():
                    f.write(f"{key} = {value}\n")
        
        # Включаем multiqueue для VirtIO
        if self.kvm_resources.get("virtio_net"):
            queues = self.kvm_resources.get("virtio_queues", 4)
            subprocess.run(f"ethtool -L {config.get('interface', {}).get('device', 'wg0')} "
                         f"combined {queues} 2>/dev/null", shell=True)
        
        # Запускаем wg-quick
        result = subprocess.run(
            f"wg-quick up {config_file}",
            shell=True, capture_output=True, text=True
        )
        
        if result.returncode == 0:
            # Получаем PID
            service["pid"] = self._get_wireguard_pid(name)
            return True
        
        service["last_error"] = result.stderr
        return False
    
    def _start_openvpn(self, name: str, service: Dict) -> bool:
        """Запуск OpenVPN с оптимизациями"""
        config = service["config"]
        config_file = Path(f"/etc/openvpn/{name}.conf")
        
        # Создаем конфиг
        with open(config_file, 'w') as f:
            for remote in config.get("remote", []):
                f.write(f"remote {remote['server']} {remote['port']} "
                       f"{remote.get('proto', 'udp')}\n")
            
            if "proto" in config:
                f.write(f"proto {config['proto']}\n")
            
            if "dev" in config:
                f.write(f"dev {config['dev']}\n")
            
            if "cipher" in config:
                f.write(f"cipher {config['cipher']}\n")
            
            # Inline keys
            for key_name, key_data in config.get("inline_keys", {}).items():
                f.write(f"<{key_name}>\n{key_data}\n</{key_name}>\n")
        
        # Запускаем OpenVPN
        result = subprocess.run(
            f"openvpn --config {config_file} --daemon",
            shell=True, capture_output=True, text=True
        )
        
        if result.returncode == 0:
            time.sleep(2)
            service["pid"] = self._find_pid("openvpn")
            return True
        
        service["last_error"] = result.stderr
        return False
    
    def _start_xray(self, name: str, service: Dict) -> bool:
        """Запуск Xray с KVM-оптимизациями"""
        config = service["config"]
        config_file = Path(f"/etc/xray/{name}.json")
        
        # Создаем конфиг
        if "full_config" in config:
            xray_config = config["full_config"]
        else:
            xray_config = {
                "log": {"loglevel": "warning"},
                "inbounds": [{
                    "port": 1080,
                    "protocol": "socks",
                    "settings": {"udp": True}
                }],
                "outbounds": [{
                    "protocol": config.get("protocol", "vless"),
                    "settings": config.get("settings", {}),
                    "streamSettings": config.get("stream_settings", {})
                }]
            }
            
            # Добавляем KVM-оптимизации
            xray_config["api"] = {
                "services": ["HandlerService", "LoggerService", "StatsService"],
                "tag": "api"
            }
            xray_config["stats"] = {}
            xray_config["policy"] = {
                "levels": {
                    "0": {
                        "statsUserUplink": True,
                        "statsUserDownlink": True
                    }
                },
                "system": {"statsInboundUplink": True, "statsInboundDownlink": True}
            }
        
        with open(config_file, 'w') as f:
            json.dump(xray_config, f, indent=2)
        
        # Запускаем Xray
        result = subprocess.run(
            f"xray -config {config_file} > /dev/null 2>&1 &",
            shell=True
        )
        
        time.sleep(2)
        service["pid"] = self._find_pid("xray")
        return service["pid"] is not None
    
    def _start_shadowsocks(self, name: str, service: Dict) -> bool:
        """Запуск Shadowsocks"""
        config = service["config"]
        config_file = Path(f"/etc/shadowsocks/{name}.json")
        
        ss_config = {
            "server": config.get("server"),
            "server_port": config.get("port", 8388),
            "password": config.get("password"),
            "method": config.get("method", "chacha20-ietf-poly1305"),
            "local_address": "127.0.0.1",
            "local_port": 1080,
            "timeout": 300,
            "fast_open": True
        }
        
        with open(config_file, 'w') as f:
            json.dump(ss_config, f, indent=2)
        
        # Запускаем ss-redir
        result = subprocess.run(
            f"ss-redir -c {config_file} -f /var/run/shadowsocks-{name}.pid",
            shell=True
        )
        
        if result.returncode == 0:
            service["pid"] = self._read_pid_file(f"/var/run/shadowsocks-{name}.pid")
            return True
        
        return False
    
    def _start_tor(self, name: str, service: Dict) -> bool:
        """Запуск Tor с ограничением ресурсов"""
        config = service["config"]
        torrc = Path("/etc/tor/torrc")
        
        with open(torrc, 'w') as f:
            f.write("# Tor Configuration\n")
            for key, value in config.get("settings", {}).items():
                f.write(f"{key} {value}\n")
            
            # Добавляем ограничения для KVM
            f.write(f"NumCPUs {min(self.kvm_resources['cpu_count'], 2)}\n")
            f.write("MaxMemInQueues 256 MB\n")
            f.write("ConstrainedSockSize 64 KB\n")
        
        # Запускаем Tor
        result = subprocess.run(
            "tor -f /etc/tor/torrc > /dev/null 2>&1 &",
            shell=True
        )
        
        time.sleep(3)
        service["pid"] = self._find_pid("tor")
        return service["pid"] is not None
    
    def _start_dpi_bypass(self, name: str, service: Dict) -> bool:
        """Запуск DPI-обходчиков"""
        settings = service["config"].get("settings", {})
        
        if service["type"] == "zapret":
            cmd = "/etc/init.d/zapret start"
        elif service["type"] == "byedpi":
            args = " ".join([f"--{k} {v}" for k, v in settings.items() if v is not True])
            flags = " ".join([f"--{k}" for k, v in settings.items() if v is True])
            cmd = f"byedpi {args} {flags} > /dev/null 2>&1 &"
        elif service["type"] == "goodbyedpi":
            cmd = "goodbyedpi --blacklist /etc/goodbyedpi/blacklist.txt > /dev/null 2>&1 &"
        else:
            return False
        
        result = subprocess.run(cmd, shell=True)
        time.sleep(2)
        service["pid"] = self._find_pid(service["type"])
        
        return result.returncode == 0
    
    def _start_generic(self, name: str, service: Dict) -> bool:
        """Универсальный запуск через init.d"""
        if Path(f"/etc/init.d/{service['type']}").exists():
            result = subprocess.run(
                f"/etc/init.d/{service['type']} start",
                shell=True, capture_output=True
            )
            time.sleep(2)
            service["pid"] = self._find_pid(service["type"])
            return result.returncode == 0
        return False
    
    def _check_resources(self, name: str) -> bool:
        """Проверка доступности ресурсов"""
        service = self.services[name]
        
        # Проверка памяти
        if service["type"] in ["xray", "adguardhome", "hysteria2"]:
            if self.kvm_resources["memory_available_mb"] < 512:
                logger.error(f"❌ Недостаточно памяти для {name}")
                return False
        
        # Проверка CPU для многопоточных служб
        if service["type"] in ["xray", "sing-box"]:
            cpu_percent = psutil.cpu_percent()
            if cpu_percent > 80:
                logger.warning(f"⚠️ Высокая загрузка CPU ({cpu_percent}%) для {name}")
        
        return True
    
    def _create_service_cgroup(self, name: str):
        """Создание cgroup для службы"""
        try:
            cgroup_path = f"{self.sentinel_cgroup}/{name.replace('.', '_')}"
            os.makedirs(cgroup_path, exist_ok=True)
            self.services[name]["cgroup"] = cgroup_path
        except Exception as e:
            logger.warning(f"⚠️ Не удалось создать cgroup: {e}")
    
    def _remove_service_cgroup(self, name: str):
        """Удаление cgroup службы"""
        try:
            cgroup_path = self.services[name].get("cgroup")
            if cgroup_path and os.path.exists(cgroup_path):
                os.rmdir(cgroup_path)
        except Exception as e:
            logger.warning(f"⚠️ Не удалось удалить cgroup: {e}")
    
    def _apply_resource_limits(self, name: str):
        """Применение лимитов ресурсов через cgroups"""
        service = self.services[name]
        cgroup_path = service.get("cgroup")
        
        if not cgroup_path or not service["pid"]:
            return
        
        try:
            # Лимит памяти для ресурсоемких служб
            if service["type"] in ["xray", "adguardhome", "hysteria2"]:
                limit_mb = 512
                with open(f"{cgroup_path}/memory.max", "w") as f:
                    f.write(f"{limit_mb * 1024 * 1024}")
                
                logger.info(f"✅ Лимит памяти {limit_mb}MB для {name}")
            
            # Привязка CPU для Tor
            if service["type"] == "tor":
                with open(f"{cgroup_path}/cpu.max", "w") as f:
                    f.write("50000 100000")  # 50% CPU
            
            # Добавляем PID в cgroup
            with open(f"{cgroup_path}/cgroup.procs", "w") as f:
                f.write(str(service["pid"]))
                
        except Exception as e:
            logger.warning(f"⚠️ Не удалось применить лимиты: {e}")
    
    def get_status(self) -> Dict[str, Any]:
        """Получение статуса всех служб"""
        status = {
            "kvm": self.kvm_resources,
            "services": {},
            "system": {
                "cpu_percent": psutil.cpu_percent(),
                "memory_percent": psutil.virtual_memory().percent,
                "uptime": time.time() - psutil.boot_time()
            }
        }
        
        for name, service in self.services.items():
            if service["pid"]:
                try:
                    process = psutil.Process(service["pid"])
                    service["memory_usage"] = process.memory_info().rss / 1024 / 1024
                    service["cpu_usage"] = process.cpu_percent()
                except:
                    pass
            
            status["services"][name] = {
                "type": service["type"],
                "status": service["status"],
                "pid": service["pid"],
                "memory_mb": service["memory_usage"],
                "cpu_percent": service["cpu_usage"],
                "uptime": (datetime.now() - service["start_time"]).seconds 
                         if service["start_time"] else 0,
                "restart_count": service["restart_count"]
            }
        
        return status
    
    def start_monitoring(self):
        """Запуск мониторинга служб"""
        self.running = True
        self.monitor_thread = threading.Thread(target=self._monitor_loop)
        self.monitor_thread.daemon = True
        self.monitor_thread.start()
        logger.info("✅ Мониторинг запущен")
    
    def _monitor_loop(self):
        """Цикл мониторинга"""
        while self.running:
            for name, service in self.services.items():
                if service["status"] == "running" and service["pid"]:
                    if not self._process_exists(service["pid"]):
                        logger.warning(f"⚠️ Процесс {name} (PID {service['pid']}) умер")
                        service["restart_count"] += 1
                        
                        # Автоматический перезапуск
                        if service["restart_count"] < 3:
                            logger.info(f"🔄 Перезапуск {name}...")
                            self.start_service(name)
                        else:
                            service["status"] = "error"
                            service["last_error"] = "Max restarts exceeded"
            
            time.sleep(10)
    
    def _process_exists(self, pid: int) -> bool:
        """Проверка существования процесса"""
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False
    
    def _find_pid(self, name: str) -> Optional[int]:
        """Поиск PID процесса"""
        try:
            result = subprocess.run(
                f"pgrep -f '{name}'",
                shell=True, capture_output=True, text=True
            )
            if result.stdout:
                return int(result.stdout.strip().split('\n')[0])
        except:
            pass
        return None
    
    def _get_wireguard_pid(self, name: str) -> Optional[int]:
        """Получение PID WireGuard процесса"""
        return self._find_pid("wg-quick")
    
    def _read_pid_file(self, pid_file: str) -> Optional[int]:
        """Чтение PID из файла"""
        try:
            with open(pid_file, 'r') as f:
                return int(f.read().strip())
        except:
            return None


# ============================================================================
# ТЕСТОВЫЙ МОДУЛЬ
# ============================================================================

def test_service_manager():
    """Тестирование менеджера служб"""
    manager = KVMServiceManager()
    
    # Регистрация тестовых служб
    manager.register_service("test-wg", "wireguard", {
        "interface": {
            "privatekey": "testkey",
            "address": "10.0.0.2/24"
        },
        "peers": [{
            "publickey": "peerkey",
            "endpoint": "example.com:51820",
            "allowedips": "0.0.0.0/0"
        }]
    })
    
    manager.register_service("test-xray", "xray", {
        "protocol": "vless",
        "server": "example.com",
        "port": 443,
        "uuid": "test-uuid"
    })
    
    # Получение статуса
    print(json.dumps(manager.get_status(), indent=2, default=str))


if __name__ == "__main__":
    test_service_manager()