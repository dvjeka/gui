-- SENTINEL OS KVM - TTL Fuzzing CBI
-- /usr/lib/lua/luci/model/cbi/sentinel-kvm/protection_ttl.lua

local dsp = require "luci.dispatcher"
local http = require "luci.http"
local uci = require "luci.model.uci".cursor()
local util = require "luci.util"
local json = require "luci.jsonc"

m = Map("sentinel-kvm-protection", "🛡️ TTL фаззинг (KVM Edition)",
    "Настройка обхода DPI через изменение TTL. Работает через nftables без iptables."
)

-- Основные настройки
s_main = m:section(TypedSection, "ttl", "Основные настройки")
s_main.anonymous = true

-- Включение
enabled = s_main:option(Flag, "enabled", "Включить TTL фаззинг")
enabled.default = "0"
enabled.description = "Активировать обход DPI через модификацию TTL"

-- Режим работы
mode = s_main:option(ListValue, "mode", "Режим работы")
mode:value("random", "🎲 Случайный (TTL 64-128)")
mode:value("windows", "🪟 Windows (TTL 128)")
mode:value("linux", "🐧 Linux (TTL 64)")
mode:value("bsd", "🔷 BSD (TTL 255)")
mode:value("macos", "🍎 macOS (TTL 64)")
mode:value("custom", "⚙️ Свой TTL")
mode.default = "random"
mode:depends("enabled", "1")

-- Свой TTL
custom_ttl = s_main:option(Value, "custom_ttl", "Свой TTL")
custom_ttl.datatype = "range(1,255)"
custom_ttl.placeholder = "64"
custom_ttl:depends("mode", "custom")
custom_ttl:depends("enabled", "1")

-- KVM-оптимизации
s_kvm = m:section(TypedSection, "kvm", "⚡ KVM оптимизации")
s_kvm.anonymous = true

-- Аппаратная поддержка
hw_offload = s_kvm:option(Flag, "hw_offload", "Аппаратная offload (VirtIO)")
hw_offload.default = "1"
hw_offload:depends("enabled", "1")
hw_offload.description = "Использовать аппаратную поддержку TTL в VirtIO"

-- Многоочередность
multiqueue = s_kvm:option(Flag, "multiqueue", "Multi-queue для TTL")
multiqueue.default = "1"
multiqueue:depends("enabled", "1")
multiqueue.description = "Распределять обработку TTL по нескольким очередям"

-- Дополнительные настройки
s_adv = m:section(TypedSection, "advanced", "🔧 Дополнительные настройки")
s_adv.anonymous = true

-- Случайная вариация
random_range = s_adv:option(Value, "random_range", "Диапазон случайности")
random_range.datatype = "range(1,20)"
random_range.default = "5"
random_range:depends("mode", "random")
random_range.description = "Отклонение от базового TTL"

-- Применять только к TCP
tcp_only = s_adv:option(Flag, "tcp_only", "Только для TCP")
tcp_only.default = "0"
tcp_only:depends("enabled", "1")
tcp_only.description = "Применять фаззинг только к TCP пакетам"

-- Исключения
exceptions = s_adv:option(Value, "exceptions", "Исключения (IP/сети)")
exceptions.placeholder = "192.168.1.0/24, 10.0.0.1"
exceptions:depends("enabled", "1")
exceptions.description = "IP адреса, для которых не применять фаззинг"

-- Статус
s_status = m:section(TypedSection, "status", "📊 Текущий статус")
s_status.anonymous = true
s_status.template = "sentinel-kvm/protection_ttl_status"

-- Применение
function m.on_commit(map)
    if enabled:formvalue("1") then
        local mode_val = mode:formvalue()
        local ttl_val = custom_ttl:formvalue()
        
        if mode_val == "custom" and ttl_val then
            os.execute("/usr/bin/sentinel-ttl-fuzz start " .. ttl_val)
        else
            os.execute("/usr/bin/sentinel-ttl-fuzz start " .. mode_val)
        end
        
        -- KVM оптимизации
        if hw_offload:formvalue("1") then
            os.execute("ethtool -K eth0 tx on rx on 2>/dev/null")
        end
        
        m.message = "✅ TTL фаззинг активирован"
    else
        os.execute("/usr/bin/sentinel-ttl-fuzz stop")
        m.message = "⏹️ TTL фаззинг отключен"
    end
end

return m