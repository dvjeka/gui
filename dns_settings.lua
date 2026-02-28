-- SENTINEL OS KVM - DNS Settings CBI
-- /usr/lib/lua/luci/model/cbi/sentinel-kvm/dns_settings.lua

local dsp = require "luci.dispatcher"
local http = require "luci.http"
local uci = require "luci.model.uci".cursor()
local util = require "luci.util"
local json = require "luci.jsonc"

m = Map("sentinel-kvm-dns", "🔒 DNS Приватность (KVM Edition)",
    "Настройте DNS с KVM-оптимизациями и защитой от утечек. " ..
    "AdGuard Home на порту 53, Unbound на 5353, DNSCrypt на 5354."
)

-- ============================================================================
-- ОСНОВНОЙ РЕЖИМ DNS
-- ============================================================================

s_main = m:section(TypedSection, "main", "Основные настройки")
s_main.anonymous = true

-- Режим DNS
dns_mode = s_main:option(ListValue, "dns_mode", "Режим работы")
dns_mode:value("adguard", "AdGuard Home (порт 53) - с блокировкой рекламы")
dns_mode:value("unbound", "Unbound (порт 5353) - рекурсивный с DNSSEC")
dns_mode:value("dnscrypt", "DNSCrypt-proxy (порт 5354) - шифрованный")
dns_mode:value("stubby", "Stubby (порт 5353) - DNS-over-TLS")
dns_mode:value("chain", "Цепочка: AdGuard → DNSCrypt → Unbound")
dns_mode.default = "chain"
dns_mode.description = "Выберите режим работы DNS. Цепочка обеспечивает максимальную приватность."

-- Уровень безопасности
security_level = s_main:option(ListValue, "security_level", "Уровень безопасности")
security_level:value("basic", "Базовый (только шифрование)")
security_level:value("secure", "Безопасный (DNSSEC + шифрование)")
security_level:value("maximum", "Максимальный (DNSSEC + No Logging + блокировка)")
security_level.default = "maximum"

-- Блокировка рекламы
block_ads = s_main:option(Flag, "block_ads", "Блокировать рекламу и трекеры")
block_ads.default = "1"
block_ads.description = "Использовать списки блокировки AdGuard"

-- ============================================================================
-- UPSTREAM DNS СЕРВЕРЫ
-- ============================================================================

s_upstream = m:section(TypedSection, "upstream", "Upstream DNS серверы")
s_upstream.anonymous = true
s_upstream.addremove = true
s_upstream.template = "cbi/tblsection"

-- Сервер
server = s_upstream:option(Value, "server", "Адрес сервера")
server.datatype = "host"
server.placeholder = "1.1.1.1"

-- Порт
port = s_upstream:option(Value, "port", "Порт")
port.datatype = "port"
port.default = "853"
port.placeholder = "853"

-- Протокол
protocol = s_upstream:option(ListValue, "protocol", "Протокол")
protocol:value("tls", "DNS-over-TLS (DoT)")
protocol:value("https", "DNS-over-HTTPS (DoH)")
protocol:value("quic", "DNS-over-QUIC (DoQ)")
protocol:value("dnscrypt", "DNSCrypt")
protocol.default = "tls"

-- Приоритет
priority = s_upstream:option(Value, "priority", "Приоритет")
priority.datatype = "uinteger"
priority.default = "1"

-- ============================================================================
-- ПРЕДУСТАНОВЛЕННЫЕ НАБОРЫ
-- ============================================================================

s_presets = m:section(TypedSection, "presets", "🚀 Быстрые настройки")
s_presets.anonymous = true

-- Кнопки пресетов
preset_cloudflare = s_presets:option(Button, "cloudflare", "Cloudflare (1.1.1.1)")
preset_cloudflare.inputstyle = "apply"
function preset_cloudflare.write()
    uci:set("sentinel-kvm-dns", "upstream", "server", "1.1.1.1")
    uci:set("sentinel-kvm-dns", "upstream", "port", "853")
    uci:set("sentinel-kvm-dns", "upstream", "protocol", "tls")
    uci:commit("sentinel-kvm-dns")
    http.redirect(dsp.build_url("admin/sentinel-kvm/dns/settings"))
end

preset_quad9 = s_presets:option(Button, "quad9", "Quad9 (9.9.9.9)")
preset_quad9.inputstyle = "apply"
function preset_quad9.write()
    uci:set("sentinel-kvm-dns", "upstream", "server", "9.9.9.9")
    uci:set("sentinel-kvm-dns", "upstream", "port", "853")
    uci:set("sentinel-kvm-dns", "upstream", "protocol", "tls")
    uci:commit("sentinel-kvm-dns")
    http.redirect(dsp.build_url("admin/sentinel-kvm/dns/settings"))
end

preset_adguard = s_presets:option(Button, "adguard", "AdGuard DNS (с блокировкой)")
preset_adguard.inputstyle = "apply"
function preset_adguard.write()
    uci:set("sentinel-kvm-dns", "upstream", "server", "94.140.14.14")
    uci:set("sentinel-kvm-dns", "upstream", "port", "853")
    uci:set("sentinel-kvm-dns", "upstream", "protocol", "tls")
    uci:commit("sentinel-kvm-dns")
    http.redirect(dsp.build_url("admin/sentinel-kvm/dns/settings"))
end

preset_mullvad = s_presets:option(Button, "mullvad", "Mullvad (макс. приватность)")
preset_mullvad.inputstyle = "apply"
function preset_mullvad.write()
    uci:set("sentinel-kvm-dns", "upstream", "server", "194.242.2.2")
    uci:set("sentinel-kvm-dns", "upstream", "port", "853")
    uci:set("sentinel-kvm-dns", "upstream", "protocol", "tls")
    uci:commit("sentinel-kvm-dns")
    http.redirect(dsp.build_url("admin/sentinel-kvm/dns/settings"))
end

-- ============================================================================
-- KVM-ОПТИМИЗАЦИИ ДЛЯ DNS
-- ============================================================================

s_kvm = m:section(TypedSection, "kvm", "⚡ KVM оптимизации DNS")
s_kvm.anonymous = true

-- VirtIO multi-queue для DNS
dns_multiqueue = s_kvm:option(Flag, "multiqueue", "VirtIO multi-queue для DNS")
dns_multiqueue.default = "1"
dns_multiqueue.description = "Увеличивает производительность DNS в KVM"

-- Количество очередей
dns_queues = s_kvm:option(Value, "queues", "Количество очередей")
dns_queues:depends("multiqueue", "1")
dns_queues.datatype = "range(1,16)"
dns_queues.default = "4"

-- CPU affinity для DNS
cpu_affinity = s_kvm:option(Flag, "cpu_affinity", "CPU affinity")
cpu_affinity.default = "1"
cpu_affinity.description = "Привязать DNS процессы к выделенным ядрам"

-- Выделенные ядра
dedicated_cpus = s_kvm:option(Value, "dedicated_cpus", "Номера ядер")
dedicated_cpus:depends("cpu_affinity", "1")
dedicated_cpus.placeholder = "0,1"
dedicated_cpus.description = "Например: 0,1 для первых двух ядер"

-- ============================================================================
-- ЗАЩИТА ОТ УТЕЧЕК
-- ============================================================================

s_protection = m:section(TypedSection, "protection", "🛡️ Защита от утечек")
s_protection.anonymous = true

-- Блокировка обычного DNS
block_plain = s_protection:option(Flag, "block_plain", "Блокировать обычный DNS (порт 53)")
block_plain.default = "1"
block_plain.description = "Заблокировать все незашифрованные DNS запросы через nftables"

-- Принудительный DNS через VPN
force_vpn = s_protection:option(Flag, "force_vpn", "Принудительный DNS через VPN")
force_vpn.default = "1"
force_vpn.description = "Весь DNS трафик направлять через активный VPN"

-- DNSSEC
dnssec = s_protection:option(Flag, "dnssec", "Включить DNSSEC")
dnssec.default = "1"
dnssec.description = "Проверка цифровых подписей DNS записей"

-- EDNS Client Subnet
edns = s_protection:option(Flag, "edns_client", "Отключить EDNS Client Subnet")
edns.default = "1"
edns.description = "Не передавать информацию о подсети клиента"

-- IPv6 блокировка
block_ipv6 = s_protection:option(Flag, "block_ipv6", "Блокировать IPv6 DNS")
block_ipv6.default = "1"
block_ipv6.description = "Блокировать все IPv6 DNS запросы"

-- ============================================================================
-- СПИСКИ БЛОКИРОВКИ
-- ============================================================================

s_blocklists = m:section(TypedSection, "blocklists", "📋 Списки блокировки")
s_blocklists.anonymous = true
s_blocklists.addremove = true
s_blocklists.template = "cbi/tblsection"

-- Название
list_name = s_blocklists:option(Value, "name", "Название")
list_name.placeholder = "AdGuard DNS filter"

-- URL
list_url = s_blocklists:option(Value, "url", "URL списка")
list_url.placeholder = "https://adguardteam.github.io/..."

-- Включен
list_enabled = s_blocklists:option(Flag, "enabled", "Вкл")
list_enabled.default = "1"

-- Категория
list_category = s_blocklists:option(ListValue, "category", "Категория")
list_category:value("ads", "Реклама")
list_category:value("tracking", "Трекеры")
list_category:value("malware", "Вредоносные")
list_category:value("phishing", "Фишинг")
list_category:value("all", "Все")
list_category.default = "ads"

-- Кнопка добавления стандартных списков
s_blocklists:option(Button, "add_defaults", "📥 Добавить стандартные списки").inputstyle = "apply"
function s_blocklists.add_defaults_write()
    local defaults = {
        { name = "AdGuard DNS filter", 
          url = "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt",
          category = "all" },
        { name = "StevenBlack Unified", 
          url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
          category = "all" },
        { name = "NoCoin", 
          url = "https://raw.githubusercontent.com/hoshsadiq/adblock-nocoin-list/master/nocoin.txt",
          category = "malware" },
        { name = "EasyList", 
          url = "https://easylist.to/easylist/easylist.txt",
          category = "ads" },
        { name = "EasyPrivacy", 
          url = "https://easylist.to/easylist/easyprivacy.txt",
          category = "tracking" }
    }
    
    for i, item in ipairs(defaults) do
        uci:set("sentinel-kvm-dns", "blocklist_" .. i, "blocklists")
        uci:set("sentinel-kvm-dns", "blocklist_" .. i, "name", item.name)
        uci:set("sentinel-kvm-dns", "blocklist_" .. i, "url", item.url)
        uci:set("sentinel-kvm-dns", "blocklist_" .. i, "category", item.category)
        uci:set("sentinel-kvm-dns", "blocklist_" .. i, "enabled", "1")
    end
    
    uci:commit("sentinel-kvm-dns")
    http.redirect(dsp.build_url("admin/sentinel-kvm/dns/settings"))
end

-- ============================================================================
-- НАСТРОЙКИ КЭШИРОВАНИЯ
-- ============================================================================

s_cache = m:section(TypedSection, "cache", "💾 Кэширование")
s_cache.anonymous = true

-- Размер кэша
cache_size = s_cache:option(Value, "size", "Размер кэша (MB)")
cache_size.datatype = "uinteger"
cache_size.default = "100"

-- Время жизни
cache_ttl = s_cache:option(Value, "ttl", "Время жизни кэша (секунд)")
cache_ttl.datatype = "uinteger"
cache_ttl.default = "3600"

-- Предзагрузка
prefetch = s_cache:option(Flag, "prefetch", "Предзагрузка популярных доменов")
prefetch.default = "1"
prefetch.description = "Ускоряет часто запрашиваемые домены"

-- ============================================================================
-- НАСТРОЙКИ ЛОГИРОВАНИЯ
-- ============================================================================

s_logging = m:section(TypedSection, "logging", "📝 Логирование")
s_logging.anonymous = true

-- Включить логирование
log_enable = s_logging:option(Flag, "enable", "Включить логирование")
log_enable.default = "0"

-- Уровень
log_level = s_logging:option(ListValue, "level", "Уровень детализации")
log_level:value("error", "Только ошибки")
log_level:value("info", "Информация")
log_level:value("debug", "Отладка")
log_level.default = "info"
log_level:depends("enable", "1")

-- Файл лога
log_file = s_logging:option(Value, "file", "Файл лога")
log_file.default = "/var/log/dns.log"
log_file:depends("enable", "1")

-- Ротация
log_rotate = s_logging:option(Value, "rotate", "Ротация (MB)")
log_rotate.datatype = "uinteger"
log_rotate.default = "10"
log_rotate:depends("enable", "1")

-- ============================================================================
-- СТАТУС DNS
-- ============================================================================

s_status = m:section(TypedSection, "status", "📊 Текущий статус")
s_status.anonymous = true
s_status.template = "sentinel-kvm/dns_status"

-- ============================================================================
-- БЫСТРЫЕ ДЕЙСТВИЯ
-- ============================================================================

s_actions = m:section(TypedSection, "actions", "⚡ Быстрые действия")
s_actions.anonymous = true
s_actions.template = "sentinel-kvm/dns_actions"

-- Обработка сохранения
function m.on_commit(map)
    local mode = uci:get("sentinel-kvm-dns", "main", "dns_mode") or "chain"
    os.execute("/usr/bin/sentinel-dns-switch " .. mode .. " >/dev/null 2>&1")
    os.execute("/etc/init.d/sentinel-core-kvm restart >/dev/null 2>&1")
end

return m