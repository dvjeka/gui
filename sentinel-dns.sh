#!/bin/bash

# setup-dns-kvm.sh
# Настройка DNS для SENTINEL OS под KVM
# Чистая архитектура без конфликтов портов

set -e

cd ~/sentinel-kvm
mkdir -p configs/etc/{unbound,stubby,dnscrypt-proxy,adguardhome}

# 1. Unbound (рекурсивный DNS)
cat > configs/etc/unbound/unbound.conf << 'EOF'
# SENTINEL OS KVM - Unbound Configuration
# Рекурсивный DNS резолвер с DNSSEC

server:
    username: "unbound"
    directory: "/etc/unbound"
    chroot: "/etc/unbound"
    pidfile: "/var/run/unbound.pid"
    
    # Интерфейсы
    interface: 127.0.0.1
    interface: ::1
    interface: 192.168.1.100
    access-control: 127.0.0.0/8 allow
    access-control: ::1 allow
    access-control: 192.168.1.0/24 allow
    
    # Приватность
    do-not-query-localhost: no
    hide-identity: yes
    hide-version: yes
    identity: "SENTINEL-DNS"
    
    # Безопасность
    harden-glue: yes
    harden-dnssec-stripped: yes
    harden-referral-path: yes
    use-caps-for-id: yes
    
    # DNSSEC
    auto-trust-anchor-file: "/etc/unbound/root.key"
    val-clean-additional: yes
    val-permissive-mode: no
    
    # Кэширование
    cache-min-ttl: 300
    cache-max-ttl: 86400
    prefetch: yes
    prefetch-key: yes
    serve-expired: yes
    serve-expired-ttl: 86400
    
    # Производительность для KVM
    num-threads: 4
    msg-cache-size: 100m
    rrset-cache-size: 200m
    outgoing-range: 8192
    num-queries-per-thread: 512
    
    # DNS-over-TLS форвардинг к Stubby
    forward-zone:
        name: "."
        forward-addr: 127.0.0.1@5353
        forward-addr: ::1@5353
        forward-tls-upstream: yes

# Локальные зоны
stub-zone:
    name: "lan"
    stub-addr: 192.168.1.100
EOF

# 2. Stubby (DNS-over-TLS)
cat > configs/etc/stubby/stubby.yml << 'EOF'
# SENTINEL OS KVM - Stubby Configuration

resolution_type: GETDNS_RESOLUTION_STUB
dns_transport_list:
  - GETDNS_TRANSPORT_TLS
  - GETDNS_TRANSPORT_TCP

tls_authentication: GETDNS_AUTHENTICATION_REQUIRED
tls_query_padding_blocksize: 256
edns_client_subnet_private: 1
idle_timeout: 10000
listen_addresses:
  - 127.0.0.1@5353
  - ::1@5353

round_robin_upstreams: 1

# Приватные DNS серверы (DoT)
upstream_recursive_servers:
  # Cloudflare
  - address_data: 1.1.1.1
    tls_auth_name: "cloudflare-dns.com"
  - address_data: 1.0.0.1
    tls_auth_name: "cloudflare-dns.com"
  
  # Quad9
  - address_data: 9.9.9.9
    tls_auth_name: "dns.quad9.net"
  
  # AdGuard (с блокировкой рекламы)
  - address_data: 94.140.14.14
    tls_auth_name: "dns.adguard.com"
  
  # Mullvad (максимальная приватность)
  - address_data: 194.242.2.2
    tls_auth_name: "dns.mullvad.net"
EOF

# 3. DNSCrypt-proxy (альтернативный DoH)
cat > configs/etc/dnscrypt-proxy/dnscrypt-proxy.toml << 'EOF'
# SENTINEL OS KVM - DNSCrypt-Proxy Configuration

listen_addresses = ['127.0.0.1:5354', '[::1]:5354']

user_name = 'nobody'
cache = true
cache_size = 4096
cache_min_ttl = 300
cache_max_ttl = 86400

log_level = 2
log_file = '/var/log/dnscrypt-proxy.log'
use_syslog = true

ipv4_servers = true
ipv6_servers = true
dnscrypt_servers = true
doh_servers = true
require_dnssec = true
require_nolog = true
require_nofilter = true

server_names = [
    'cloudflare',
    'quad9-dnscrypt-ip4-filter-pri',
    'adguard-dns-family',
]

bootstrap_resolvers = ['9.9.9.9:53', '1.1.1.1:53']
fallback_resolvers = ['9.9.9.9:53', '8.8.8.8:53']
ignore_system_dns = true

[blocked_names]
  files = ['blacklist.txt']
  log_file = '/var/log/blocked-names.log'
EOF

# 4. AdGuard Home (блокировка рекламы) - на порту 53
cat > configs/etc/adguardhome/AdGuardHome.yaml << 'EOF'
# SENTINEL OS KVM - AdGuard Home Configuration

http:
  address: 192.168.1.100:3000
  session_ttl: 720h

users:
  - name: admin
    password: $2y$10$SENTINEL_CHANGE_THIS

dns:
  bind_hosts:
    - 0.0.0.0
    - ::
  port: 53
  protection_enabled: true
  filtering_enabled: true
  safebrowsing_enabled: false
  parental_enabled: false
  
  upstream_dns:
    - tls://1.1.1.1
    - https://cloudflare-dns.com/dns-query
    - 127.0.0.1:5354  # DNSCrypt-proxy
  
  bootstrap_dns:
    - 9.9.9.9
    - 1.1.1.1
  
  fallback_dns:
    - 8.8.8.8
  
  all_servers: true
  fastest_addr: true
  
  cache_size: 8388608  # 8MB
  cache_ttl_min: 60
  cache_ttl_max: 86400
  cache_optimistic: true

filtering:
  filtering_enabled: true
  filters_update_interval: 24
  filters:
    - enabled: true
      url: https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
      name: AdGuard DNS filter
      id: 1
    - enabled: true
      url: https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
      name: StevenBlack's Unified hosts
      id: 2
    - enabled: true
      url: https://someonewhocares.org/hosts/zero/hosts
      name: SomeoneWhoCares
      id: 3

log:
  file: "/var/log/adguard-home.log"
  max_backups: 3
  max_size: 100
  max_age: 30
EOF

# 5. Отключение dnsmasq (чтобы освободить порт 53)
cat > configs/etc/config/dhcp << 'EOF'
# SENTINEL OS KVM - DHCP Configuration
# dnsmasq отключен, весь DNS через AdGuard/Unbound

config dnsmasq
    option domainneeded '1'
    option boguspriv '1'
    option filterwin2k '0'
    option localise_queries '1'
    option rebind_protection '1'
    option rebind_localhost '1'
    option local '/lan/'
    option domain 'lan'
    option expandhosts '1'
    option authoritative '1'
    option readethers '1'
    option leasefile '/tmp/dhcp.leases'
    option resolvfile '/tmp/resolv.conf.dnsmasq'
    option nonwildcard '1'
    option localservice '1'
    option ednspacket_max '1232'
    option noresolv '1'           # Не использовать внешние DNS
    option port '0'                #