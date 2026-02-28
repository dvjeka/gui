-- SENTINEL OS KVM - Stealth Mode CBI
-- /usr/lib/lua/luci/model/cbi/sentinel-kvm/protection_stealth.lua

local dsp = require "luci.dispatcher"
local http = require "luci.http"
local uci = require "luci.model.uci".cursor()
local util = require "luci.util"
local json = require "luci.jsonc"

m = Map("sentinel-kvm-protection", "🕵️ Стелс-режим (KVM Edition)",
    "Скрытие открытых портов и защита от сканирования через nftables."
)

-- Основные настройки
s_main = m:section(TypedSection, "stealth", "Основные настройки")
s_main.anonymous = true

-- Включение
enabled = s_main:option(Flag, "enabled", "Включить стелс-режим")
enabled.default = "0"
enabled.description = "Скрыть открытые порты от внешнего сканирования"

-- Уровень
level = s_main:option(ListValue, "level", "Уровень защиты")
level:value("basic", "🔰 Базовый (скрыть порты)")
level:value("advanced", "🛡️ Продвинутый (+SYN cookies)")
level:value("paranoid", "👁️ Параноидальный (отклонить все, кроме established)")
level.default = "advanced"
level:depends("enabled", "1")

-- KVM-оптимизации
s_kvm = m:section(TypedSection, "kvm", "⚡ KVM оптимизации")
s_kvm.anonymous = true

-- Аппаратная защита
virtio_sec = s_kvm:option(Flag, "virtio_sec", "VirtIO security features")
virtio_sec.default = "1"
virtio_sec:depends("enabled", "1")
virtio_sec.description = "Использовать аппаратные возможности VirtIO для защиты"

-- Защита от DDoS
s_ddos = m:section(TypedSection, "ddos", "🌊 Защита от DDoS")
s_ddos.anonymous = true

-- SYN flood protection
syn_flood = s_ddos:option(Flag, "syn_flood", "Защита от SYN flood")
syn_flood.default = "1"
syn_flood:depends("enabled", "1")

-- Лимит соединений
conn_limit = s_ddos:option(Value, "conn_limit", "Лимит соединений с IP")
conn_limit.datatype = "range(10,1000)"
conn_limit.default = "100"
conn_limit:depends("enabled", "1")
conn_limit.description = "Максимум одновременных соединений с одного IP"

-- Лимит новых соединений
rate_limit = s_ddos:option(Value, "rate_limit", "Лимит новых соединений/сек")
rate_limit.datatype = "range(1,100)"
rate_limit.default = "10"
rate_limit:depends("enabled", "1")

-- Port knocking
s_knock = m:section(TypedSection, "knock", "🔑 Port knocking")
s_knock.anonymous = true

-- Включить port knocking
knock_enabled = s_knock:option(Flag, "enabled", "Включить port knocking")
knock_enabled.default = "0"
knock_enabled:depends("enabled", "1")
knock_enabled.description = "Открывать порты только после последовательности"

-- Последовательность
sequence = s_knock:option(Value, "sequence", "Последовательность портов")
sequence.placeholder = "1000,2000,3000"
sequence:depends("knock_enabled", "1")
sequence.description = "Порты через запятую в правильном порядке"

-- Таймаут
knock_timeout = s_knock:option(Value, "timeout", "Таймаут (секунд)")
knock_timeout.datatype = "range(5,60)"
knock_timeout.default = "10"
knock_timeout:depends("knock_enabled", "1")

-- Открываемые порты
open_ports = s_knock:option(Value, "open_ports", "Открываемые порты")
open_ports.placeholder = "22,80,443"
open_ports:depends("knock_enabled", "1")
open_ports.description = "Порты для открытия после knocking"

-- Исключения
s_exceptions = m:section(TypedSection, "exceptions", "✅ Исключения")
s_exceptions.anonymous = true

-- Доверенные IP
trusted_ips = s_exceptions:option(Value, "trusted_ips", "Доверенные IP")
trusted_ips.placeholder = "192.168.1.0/24, 10.0.0.1"
trusted_ips:depends("enabled", "1")
trusted_ips.description = "IP/сети, не подпадающие под защиту"

-- ICMP
allow_icmp = s_exceptions:option(Flag, "allow_icmp", "Разрешить ICMP (ping)")
allow_icmp.default = "0"
allow_icmp:depends("enabled", "1")

-- Статус
s_status = m:section(TypedSection, "status", "📊 Текущий статус")
s_status.anonymous = true
s_status.template = "sentinel-kvm/protection_stealth_status"

-- Применение
function m.on_commit(map)
    if enabled:formvalue("1") then
        local level_val = level:formvalue()
        os.execute("/usr/bin/sentinel-stealth-mode start " .. level_val)
        
        -- DDoS protection
        if syn_flood:formvalue("1") then
            os.execute("sysctl -w net.ipv4.tcp_syncookies=1")
        end
        
        -- Лимиты
        if conn_limit:formvalue() then
            os.execute("nft add rule inet sentinel input ct count " .. 
                      conn_limit:formvalue() .. " drop")
        end
        
        m.message = "✅ Стелс-режим активирован"
    else
        os.execute("/usr/bin/sentinel-stealth-mode stop")
        m.message = "⏹️ Стелс-режим отключен"
    end
end

return m