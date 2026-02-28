#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
SENTINEL OS KVM - Парсер ключей и конфигураций
===============================================
Модуль парсинга с поддержкой KVM-оптимизаций и проверкой ресурсов
"""

import re
import json
import base64
import urllib.parse
import ipaddress
import socket
from typing import Dict, Any, List, Optional, Tuple
from datetime import datetime
import hashlib
import binascii

class KVMProtocolParser:
    """
    Парсер протоколов с KVM-специфичными оптимизациями.
    Поддерживает автоопределение и валидацию конфигураций.
    """
    
    def __init__(self, kvm_resources: Dict[str, Any] = None):
        self.kvm_resources = kvm_resources or {
            "cpu_count": 4,
            "memory_mb": 2048,
            "virtio_net": True,
            "virtio_queues": 4
        }
        self.supported_protocols = [
            "wireguard", "amneziawg", "openvpn", "xray",
            "shadowsocks", "trojan", "sing-box", "hysteria2",
            "tor", "zapret", "byedpi", "goodbyedpi"
        ]
    
    def parse(self, protocol: str, data: str) -> Dict[str, Any]:
        """
        Главный метод парсинга с автоопределением и KVM-оптимизациями.
        
        Args:
            protocol: Имя протокола или "auto"
            data: Строка с конфигурацией/ключом
            
        Returns:
            Dict с распарсенными данными и KVM-оптимизациями
        """
        result = {
            "timestamp": datetime.now().isoformat(),
            "protocol": protocol,
            "parsed": False,
            "kvm_optimizations": self._get_kvm_optimizations(),
            "warnings": [],
            "errors": []
        }
        
        # Автоопределение протокола
        if protocol == "auto" or not protocol:
            protocol = self._detect_protocol(data)
            result["protocol"] = protocol
            result["auto_detected"] = True
        
        # Проверка поддержки
        if protocol not in self.supported_protocols:
            result["warnings"].append(f"Протокол {protocol} может не поддерживаться")
        
        # Выбор парсера
        try:
            if protocol == "wireguard":
                parsed = self._parse_wireguard(data)
            elif protocol == "amneziawg":
                parsed = self._parse_amneziawg(data)
            elif protocol == "openvpn":
                parsed = self._parse_openvpn(data)
            elif protocol == "xray":
                parsed = self._parse_xray(data)
            elif protocol == "shadowsocks":
                parsed = self._parse_shadowsocks(data)
            elif protocol == "trojan":
                parsed = self._parse_trojan(data)
            elif protocol == "sing-box":
                parsed = self._parse_singbox(data)
            elif protocol == "hysteria2":
                parsed = self._parse_hysteria2(data)
            elif protocol == "tor":
                parsed = self._parse_tor(data)
            elif protocol in ["zapret", "byedpi", "goodbyedpi"]:
                parsed = self._parse_dpi_bypass(protocol, data)
            else:
                parsed = self._parse_generic(data)
            
            result.update(parsed)
            result["parsed"] = True
            
            # Добавляем KVM-специфичные оптимизации
            result["kvm_specific"] = self._get_protocol_kvm_optimizations(protocol, parsed)
            
            # Валидация
            self._validate_config(protocol, result)
            
        except Exception as e:
            result["errors"].append(str(e))
            result["parsed"] = False
        
        return result
    
    def _detect_protocol(self, data: str) -> str:
        """Автоопределение протокола по содержимому"""
        data = data.strip()
        
        # URL схемы
        if data.startswith("ss://"):
            return "shadowsocks"
        elif data.startswith("trojan://"):
            return "trojan"
        elif data.startswith("vless://") or data.startswith("vmess://"):
            return "xray"
        elif data.startswith("wg://") or data.startswith("wireguard://"):
            return "wireguard"
        elif data.startswith("amnezia://"):
            return "amneziawg"
        elif data.startswith("hysteria://") or data.startswith("hy2://"):
            return "hysteria2"
        
        # WireGuard конфиг
        if "[Interface]" in data and "[Peer]" in data:
            if "Jc" in data or "Jmin" in data:
                return "amneziawg"
            return "wireguard"
        
        # OpenVPN
        if "client" in data.lower() and "dev tun" in data.lower():
            return "openvpn"
        
        # JSON конфиги
        if data.strip().startswith("{"):
            try:
                json_data = json.loads(data)
                if "outbounds" in json_data:
                    return "sing-box"
                elif "inbounds" in json_data:
                    return "xray"
            except:
                pass
        
        # Tor
        if "SOCKSPort" in data or "torrc" in data.lower():
            return "tor"
        
        return "unknown"
    
    def _parse_wireguard(self, data: str) -> Dict[str, Any]:
        """Парсинг WireGuard с KVM-оптимизациями"""
        result = {
            "type": "wireguard",
            "interface": {},
            "peers": [],
            "kvm_optimizations": {
                "multiqueue": True,
                "rx_queues": min(self.kvm_resources.get("cpu_count", 4), 8),
                "tx_queues": min(self.kvm_resources.get("cpu_count", 4), 8),
                "vhost_net": True
            }
        }
        
        # URL формат
        if data.startswith("wg://") or data.startswith("wireguard://"):
            return self._parse_wireguard_url(data)
        
        # INI формат
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
        
        # Проверка на AmneziaWG параметры
        for param in ["jc", "jmin", "jmax", "s1", "s2", "h1", "h2", "h3", "h4"]:
            if param in result["interface"]:
                result["type"] = "amneziawg"
                break
        
        return result
    
    def _parse_wireguard_url(self, url: str) -> Dict[str, Any]:
        """Парсинг WireGuard URL"""
        result = {
            "type": "wireguard",
            "interface": {},
            "peers": [],
            "kvm_optimizations": {
                "multiqueue": True,
                "rx_queues": self.kvm_resources.get("cpu_count", 4)
            }
        }
        
        # Удаляем префикс
        url = re.sub(r'^(wg://|wireguard://)', '', url)
        
        # Парсим параметры
        if '#' in url:
            url, name = url.split('#', 1)
            result["name"] = name
        
        if '?' in url:
            url, query = url.split('?', 1)
            params = urllib.parse.parse_qs(query)
            for key, values in params.items():
                result["interface"][key.lower()] = values[0]
        
        # Основная часть
        if '@' in url:
            keys, endpoint = url.split('@', 1)
            if '+' in keys:
                private_key, public_key = keys.split('+', 1)
                result["interface"]["privatekey"] = private_key
                result["peers"].append({
                    "publickey": public_key,
                    "endpoint": endpoint
                })
            else:
                result["interface"]["privatekey"] = keys
                result["peers"].append({"endpoint": endpoint})
        
        return result
    
    def _parse_amneziawg(self, data: str) -> Dict[str, Any]:
        """Парсинг AmneziaWG с дополнительными параметрами"""
        result = self._parse_wireguard(data)
        result["type"] = "amneziawg"
        
        # AmneziaWG специфичные параметры
        awg_params = {
            "jc": "4",      # Junk packet count
            "jmin": "30",    # Minimum junk packet size
            "jmax": "50",    # Maximum junk packet size
            "s1": "120",     # Init packet junk size
            "s2": "150"      # Response packet junk size
        }
        
        for param, default in awg_params.items():
            if param not in result["interface"]:
                result["interface"][param] = default
        
        return result
    
    def _parse_openvpn(self, data: str) -> Dict[str, Any]:
        """Парсинг OpenVPN с поддержкой inline тегов"""
        result = {
            "type": "openvpn",
            "mode": "client",
            "remote": [],
            "auth": {},
            "tls": {},
            "inline_keys": {},
            "kvm_optimizations": {
                "tun_queue": self.kvm_resources.get("virtio_queues", 4),
                "tcp_fastopen": True
            }
        }
        
        lines = data.split('\n')
        current_inline = None
        inline_content = []
        
        for line in lines:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            # Inline теги
            if line.startswith('<') and line.endswith('>'):
                current_inline = line[1:-1]
                inline_content = []
                continue
            elif line.startswith('</') and line.endswith('>'):
                if current_inline:
                    result["inline_keys"][current_inline.lower()] = '\n'.join(inline_content)
                    current_inline = None
                continue
            elif current_inline:
                inline_content.append(line)
                continue
            
            # Парсинг директив
            parts = line.split()
            if not parts:
                continue
            
            directive = parts[0].lower()
            
            if directive == "remote":
                if len(parts) >= 2:
                    server = parts[1]
                    port = int(parts[2]) if len(parts) >= 3 else 1194
                    proto = parts[3] if len(parts) >= 4 else "udp"
                    result["remote"].append({
                        "server": server,
                        "port": port,
                        "proto": proto
                    })
            
            elif directive == "proto":
                result["proto"] = parts[1] if len(parts) > 1 else "udp"
            
            elif directive == "dev":
                result["dev"] = parts[1] if len(parts) > 1 else "tun"
            
            elif directive == "cipher":
                result["cipher"] = parts[1] if len(parts) > 1 else "AES-256-GCM"
            
            elif directive == "auth":
                result["auth"] = parts[1] if len(parts) > 1 else "SHA512"
            
            elif directive == "auth-user-pass":
                result["auth"]["user_pass"] = True
                if len(parts) > 1:
                    result["auth"]["auth_file"] = parts[1]
        
        return result
    
    def _parse_xray(self, data: str) -> Dict[str, Any]:
        """Парсинг Xray конфигураций (VLESS, VMess, Trojan, Reality)"""
        result = {
            "type": "xray",
            "protocol": None,
            "settings": {},
            "stream_settings": {},
            "kvm_optimizations": {
                "tcp_fastopen": True,
                "bbr_congestion": True,
                "multicore": True,
                "sniffing": True
            }
        }
        
        # JSON конфиг
        if data.strip().startswith('{'):
            try:
                json_config = json.loads(data)
                return self._parse_xray_json(json_config)
            except:
                pass
        
        # URL форматы
        if data.startswith("vless://"):
            return self._parse_vless_url(data)
        elif data.startswith("vmess://"):
            return self._parse_vmess_url(data)
        elif data.startswith("trojan://"):
            return self._parse_trojan_url(data)
        
        return result
    
    def _parse_vless_url(self, url: str) -> Dict[str, Any]:
        """Парсинг VLESS URL"""
        parsed = urllib.parse.urlparse(url)
        
        result = {
            "type": "xray",
            "protocol": "vless",
            "uuid": parsed.username or "",
            "server": parsed.hostname or "",
            "port": parsed.port or 443,
            "flow": "",
            "encryption": "none",
            "stream_settings": {
                "network": "tcp",
                "security": "none"
            },
            "kvm_optimizations": {
                "tcp_fastopen": True,
                "multicore": True
            }
        }
        
        # Парсим параметры
        if parsed.query:
            params = urllib.parse.parse_qs(parsed.query)
            
            if "type" in params:
                result["stream_settings"]["network"] = params["type"][0]
            if "security" in params:
                result["stream_settings"]["security"] = params["security"][0]
            if "flow" in params:
                result["flow"] = params["flow"][0]
            if "pbk" in params:  # Reality public key
                result["stream_settings"]["reality_settings"] = {
                    "public_key": params["pbk"][0],
                    "short_id": params.get("sid", [""])[0],
                    "server_name": params.get("sni", [result["server"]])[0]
                }
                result["stream_settings"]["security"] = "reality"
        
        if parsed.fragment:
            result["name"] = parsed.fragment
        
        return result
    
    def _parse_vmess_url(self, url: str) -> Dict[str, Any]:
        """Парсинг VMess URL (base64)"""
        b64_part = url[8:]  # Убираем 'vmess://'
        
        try:
            # Добавляем padding если нужно
            b64_part += "=" * ((4 - len(b64_part) % 4) % 4)
            json_str = base64.b64decode(b64_part).decode('utf-8')
            vmess = json.loads(json_str)
            
            result = {
                "type": "xray",
                "protocol": "vmess",
                "uuid": vmess.get("id", ""),
                "server": vmess.get("add", ""),
                "port": int(vmess.get("port", 443)),
                "aid": int(vmess.get("aid", 0)),
                "stream_settings": {
                    "network": vmess.get("net", "tcp"),
                    "security": vmess.get("tls", "none")
                },
                "kvm_optimizations": {
                    "tcp_fastopen": True,
                    "multicore": True
                }
            }
            
            if "path" in vmess:
                if result["stream_settings"]["network"] == "ws":
                    result["stream_settings"]["ws_settings"] = {
                        "path": vmess["path"],
                        "host": vmess.get("host", "")
                    }
            
            return result
            
        except Exception as e:
            return {
                "type": "xray",
                "protocol": "vmess",
                "error": str(e),
                "kvm_optimizations": {}
            }
    
    def _parse_trojan_url(self, url: str) -> Dict[str, Any]:
        """Парсинг Trojan URL"""
        parsed = urllib.parse.urlparse(url)
        
        result = {
            "type": "trojan",
            "protocol": "trojan",
            "password": parsed.username or "",
            "server": parsed.hostname or "",
            "port": parsed.port or 443,
            "stream_settings": {
                "security": "tls",
                "network": "tcp"
            },
            "kvm_optimizations": {
                "tcp_fastopen": True,
                "multicore": True
            }
        }
        
        if parsed.query:
            params = urllib.parse.parse_qs(parsed.query)
            if "sni" in params:
                result["stream_settings"]["tls_settings"] = {
                    "server_name": params["sni"][0]
                }
            if "type" in params:
                result["stream_settings"]["network"] = params["type"][0]
        
        if parsed.fragment:
            result["name"] = parsed.fragment
        
        return result
    
    def _parse_xray_json(self, config: Dict) -> Dict[str, Any]:
        """Парсинг Xray JSON конфигурации"""
        result = {
            "type": "xray",
            "protocol": "xray",
            "inbounds": config.get("inbounds", []),
            "outbounds": config.get("outbounds", []),
            "kvm_optimizations": {
                "tcp_fastopen": True,
                "multicore": True,
                "sniffing": True
            }
        }
        
        if result["outbounds"]:
            outbound = result["outbounds"][0]
            result["protocol"] = outbound.get("protocol", "xray")
            result["settings"] = outbound.get("settings", {})
            
            if "streamSettings" in outbound:
                result["stream_settings"] = outbound["streamSettings"]
        
        return result
    
    def _parse_shadowsocks(self, data: str) -> Dict[str, Any]:
        """Парсинг Shadowsocks (ss://)"""
        result = {
            "type": "shadowsocks",
            "method": None,
            "password": None,
            "server": None,
            "port": None,
            "plugin": None,
            "kvm_optimizations": {
                "tcp_fastopen": True,
                "reuse_port": True
            }
        }
        
        if data.startswith("ss://"):
            data = data[5:]
        
        if '#' in data:
            data, name = data.split('#', 1)
            result["name"] = urllib.parse.unquote(name)
        
        if '?' in data:
            data, query = data.split('?', 1)
            params = urllib.parse.parse_qs(query)
            if "plugin" in params:
                result["plugin"] = params["plugin"][0]
        
        try:
            # Формат: method:password@server:port
            if '@' in data:
                auth_part, server_part = data.split('@', 1)
                
                # Декодируем auth часть если в base64
                try:
                    decoded = base64.b64decode(auth_part).decode('utf-8')
                    if ':' in decoded:
                        result["method"], result["password"] = decoded.split(':', 1)
                except:
                    if ':' in auth_part:
                        result["method"], result["password"] = auth_part.split(':', 1)
                
                # Парсим server:port
                if ':' in server_part:
                    result["server"], port_str = server_part.split(':', 1)
                    result["port"] = int(port_str)
        
        except Exception as e:
            result["error"] = str(e)
        
        return result
    
    def _parse_trojan(self, data: str) -> Dict[str, Any]:
        """Парсинг Trojan"""
        if data.startswith("trojan://"):
            return self._parse_trojan_url(data)
        else:
            try:
                json_config = json.loads(data)
                return {
                    "type": "trojan",
                    "protocol": "trojan",
                    "config": json_config,
                    "kvm_optimizations": {
                        "tcp_fastopen": True,
                        "multicore": True
                    }
                }
            except:
                return {
                    "type": "trojan",
                    "error": "Invalid format",
                    "kvm_optimizations": {}
                }
    
    def _parse_singbox(self, data: str) -> Dict[str, Any]:
        """Парсинг Sing-box конфигурации"""
        result = {
            "type": "sing-box",
            "protocol": "sing-box",
            "kvm_optimizations": {
                "tcp_fastopen": True,
                "multicore": True,
                "bbr": True,
                "wireguard_multiqueue": True
            }
        }
        
        try:
            json_config = json.loads(data)
            result["config"] = json_config
            
            # Извлекаем основную информацию
            if "outbounds" in json_config:
                result["outbounds"] = []
                for outbound in json_config["outbounds"]:
                    outbound_info = {
                        "type": outbound.get("type"),
                        "tag": outbound.get("tag")
                    }
                    if "server" in outbound:
                        outbound_info["server"] = outbound["server"]
                    if "server_port" in outbound:
                        outbound_info["port"] = outbound["server_port"]
                    result["outbounds"].append(outbound_info)
            
            if "inbounds" in json_config:
                result["inbounds"] = len(json_config["inbounds"])
        
        except Exception as e:
            result["error"] = str(e)
        
        return result
    
    def _parse_hysteria2(self, data: str) -> Dict[str, Any]:
        """Парсинг Hysteria2"""
        result = {
            "type": "hysteria2",
            "protocol": "hysteria2",
            "kvm_optimizations": {
                "quic": True,
                "bbr": True,
                "fast_open": True
            }
        }
        
        # URL формат
        if data.startswith("hysteria://") or data.startswith("hy2://"):
            data = re.sub(r'^(hysteria://|hy2://)', '', data)
            
            if '?' in data:
                address, query = data.split('?', 1)
                params = urllib.parse.parse_qs(query)
                
                if ':' in address:
                    result["server"], port_str = address.split(':', 1)
                    result["port"] = int(port_str)
                else:
                    result["server"] = address
                    result["port"] = 443
                
                if "auth" in params:
                    result["auth"] = params["auth"][0]
                if "up" in params:
                    result["up_mbps"] = int(params["up"][0])
                if "down" in params:
                    result["down_mbps"] = int(params["down"][0])
        
        # JSON формат
        else:
            try:
                json_config = json.loads(data)
                result["config"] = json_config
            except:
                pass
        
        return result
    
    def _parse_tor(self, data: str) -> Dict[str, Any]:
        """Парсинг Tor конфигурации"""
        result = {
            "type": "tor",
            "protocol": "tor",
            "settings": {},
            "kvm_optimizations": {
                "num_cpus": min(self.kvm_resources.get("cpu_count", 4), 2),
                "max_mem": 512
            }
        }
        
        for line in data.split('\n'):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            if ' ' in line:
                key, value = line.split(' ', 1)
                result["settings"][key.lower()] = value.strip()
        
        # Устанавливаем оптимизации для KVM
        if "SOCKSPort" not in result["settings"]:
            result["settings"]["SOCKSPort"] = "9050"
        if "ControlPort" not in result["settings"]:
            result["settings"]["ControlPort"] = "9051"
        
        return result
    
    def _parse_dpi_bypass(self, protocol: str, data: str) -> Dict[str, Any]:
        """Парсинг конфигураций DPI-обходчиков"""
        result = {
            "type": protocol,
            "protocol": protocol,
            "settings": {},
            "kvm_optimizations": {
                "nftables": True,
                "queue": self.kvm_resources.get("virtio_queues", 4)
            }
        }
        
        # Парсим параметры командной строки
        args = data.split()
        i = 0
        while i < len(args):
            arg = args[i]
            if arg.startswith('--'):
                key = arg[2:]
                if i + 1 < len(args) and not args[i + 1].startswith('--'):
                    result["settings"][key] = args[i + 1]
                    i += 2
                else:
                    result["settings"][key] = True
                    i += 1
            else:
                i += 1
        
        return result
    
    def _parse_generic(self, data: str) -> Dict[str, Any]:
        """Универсальный парсер для неизвестных форматов"""
        result = {
            "type": "unknown",
            "raw_data": data[:500] + "..." if len(data) > 500 else data,
            "detected": []
        }
        
        # Ищем IP адреса
        ip_pattern = r'\b(?:\d{1,3}\.){3}\d{1,3}\b'
        ips = re.findall(ip_pattern, data)
        if ips:
            result["detected"].append(f"IPs: {ips[:5]}")
        
        # Ищем порты
        port_pattern = r'\bport[=:\s]+(\d+)\b'
        ports = re.findall(port_pattern, data.lower())
        if ports:
            result["detected"].append(f"Ports: {ports[:5]}")
        
        # Ищем ключи (base64)
        b64_pattern = r'[A-Za-z0-9+/]{40,}={0,2}'
        keys = re.findall(b64_pattern, data)
        if keys:
            result["detected"].append("Contains cryptographic keys")
        
        return result
    
    def _get_kvm_optimizations(self) -> Dict[str, Any]:
        """Получение общих KVM-оптимизаций"""
        return {
            "virtio_enabled": self.kvm_resources.get("virtio_net", True),
            "cpu_count": self.kvm_resources.get("cpu_count", 4),
            "memory_mb": self.kvm_resources.get("memory_mb", 2048),
            "virtio_queues": self.kvm_resources.get("virtio_queues", 4)
        }
    
    def _get_protocol_kvm_optimizations(self, protocol: str, parsed: Dict) -> Dict[str, Any]:
        """Получение специфичных для протокола KVM-оптимизаций"""
        optimizations = {}
        
        if protocol in ["wireguard", "amneziawg"]:
            optimizations = {
                "multiqueue": True,
                "rx_queues": min(self.kvm_resources.get("cpu_count", 4), 8),
                "tx_queues": min(self.kvm_resources.get("cpu_count", 4), 8),
                "vhost_net": True
            }
        
        elif protocol in ["xray", "sing-box"]:
            optimizations = {
                "tcp_fastopen": True,
                "bbr_congestion": True,
                "multicore": True,
                "sniffing": True
            }
        
        elif protocol == "openvpn":
            optimizations = {
                "tun_queue": self.kvm_resources.get("virtio_queues", 4),
                "tcp_fastopen": True
            }
        
        elif protocol == "tor":
            optimizations = {
                "num_cpus": min(self.kvm_resources.get("cpu_count", 4), 2),
                "max_mem": 512
            }
        
        return optimizations
    
    def _validate_config(self, protocol: str, config: Dict) -> bool:
        """Валидация конфигурации"""
        valid = True
        
        if protocol in ["wireguard", "amneziawg"]:
            if "interface" not in config or not config.get("interface"):
                config["warnings"].append("Отсутствует секция Interface")
                valid = False
            if "peers" not in config or not config.get("peers"):
                config["warnings"].append("Отсутствуют пиры")
                valid = False
        
        elif protocol == "openvpn":
            if "remote" not in config or not config.get("remote"):
                config["warnings"].append("Отсутствует remote сервер")
                valid = False
        
        elif protocol in ["xray", "vless", "vmess", "trojan"]:
            if "server" not in config or not config.get("server"):
                config["warnings"].append("Отсутствует сервер")
                valid = False
            if "port" not in config:
                config["warnings"].append("Отсутствует порт")
                valid = False
        
        return valid


# ============================================================================
# ТЕСТОВЫЙ МОДУЛЬ
# ============================================================================

def test_parser():
    """Тестирование парсера"""
    parser = KVMProtocolParser({
        "cpu_count": 8,
        "memory_mb": 4096,
        "virtio_net": True,
        "virtio_queues": 4
    })
    
    test_cases = [
        ("wireguard", """
[Interface]
PrivateKey = eJX1z1Z3Q4Z5a6b7c8d9e0f1g2h3i4j5k6l7m8n9o0p1=
Address = 10.0.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = fE9s8d7g6h5j4k3l2p1o0i9u8y7t6r5e4w3q2z1x2v3=
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.example.com:51820
"""),
        ("xray", "vless://uuid@example.com:443?type=tcp&security=reality&pbk=publickey&fp=chrome#MyConfig"),
        ("shadowsocks", "ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwYXNzd29yZA@example.com:8443#MySS"),
        ("trojan", "trojan://password@example.com:443?sni=example.com#MyTrojan"),
        ("openvpn", """
client
dev tun
proto udp
remote example.com 1194
resolv-retry infinite
nobind
remote-cert-tls server
cipher AES-256-GCM
verb 3
<ca>
-----BEGIN CERTIFICATE-----
MIIF...
-----END CERTIFICATE-----
</ca>
""")
    ]
    
    for protocol, data in test_cases:
        print(f"\n🔍 Тестирование {protocol}:")
        print("-" * 50)
        result = parser.parse(protocol, data)
        print(json.dumps(result, indent=2, ensure_ascii=False)[:1000])


if __name__ == "__main__":
    test_parser()