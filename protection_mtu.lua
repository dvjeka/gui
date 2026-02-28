-- SENTINEL OS KVM - MTU Randomization CBI
-- /usr/lib/lua/luci/model/cbi/sentinel-kvm/protection_mtu.lua

local dsp = require "luci.dispatcher"
local http = require "luci.http"
local uci = require "luci.model.uci".cursor()
local util = require "luci.util"
local json = require "luci.jsonc"

m = Map("sentinel-kvm-protection", "📦 MTU рандомизация (KVM Edition)",
    "Случайная MTU для обхода DPI и фрагментации. Оптимизировано для VirtIO."
)

-- Основные настройки
s_main = m:section(TypedSection, "mtu", "Основные настройки")
s_main.anonymous = true

-- Включение
enabled = s_main:option(Flag, "enabled", "Включить MTU рандомизацию")
enabled.default = "0"
enabled.description = "Случайно изменять MTU на интерфейсах"

-- Режим
mode = s_main:option(ListValue, "mode", "Режим работы")
mode:value("random", "🎲 Полностью случайный (500-1500)")
mode:value("vpn", "🔒 VPN оптимизированный (1300-1450)")
mode:value("pppoe", "📡 PPPoE (1400-1490)")
mode:value("jumbo", "🐘 Jumbo frames (1500-9000)")
mode:value("frag", "🧩 Принудительная фрагментация (500-1000)")
mode.default = "random"
mode:depends("enabled", "1")

-- Интервал изменения
interval = s_main:option(Value, "interval", "Интервал изменения (секунд)")
interval.datatype = "range(60,86400)"
interval.default = "3600"
interval:depends("enabled", "1")
interval.description = "Как часто менять MTU (1 час по умолчанию)"

-- KVM-оптимизации
s_kvm = m:section(TypedSection, "kvm", "⚡ VirtIO оптимизации")
s_kvm.anonymous = true

-- Интерфейсы
interfaces = s_kvm:option(MultiValue, "interfaces", "Интерфейсы для оптимизации")
interfaces:value("eth0", "eth0 (VirtIO)")
interfaces:value("eth1", "eth1 (VirtIO)")
interfaces:value("ens3", "ens3")
interfaces:value("ens4", "ens4")
interfaces.default = "eth0"
interfaces:depends("enabled", "1")

-- Аппаратная поддержка
virtio_tso = s_kvm:option(Flag, "virtio_tso", "VirtIO TSO/GSO")
virtio_tso.default = "1"
virtio_tso:depends("enabled", "1")
virtio_tso.description = "Аппаратная сегментация больших пакетов"

-- MSS clamping
s_adv = m:section(TypedSection, "advanced", "⚙️ MSS clamping")
s_adv.anonymous = true

-- Включить MSS clamping
mss_enabled = s_adv:option(Flag, "mss_enabled", "Включить MSS clamping")
mss_enabled.default = "1"
mss_enabled:depends("enabled", "1")
mss_enabled.description = "Автоматическая подстройка MSS под MTU"

-- PMTU discovery
pmtu = s_adv:option(ListValue, "pmtu", "PMTU discovery")
pmtu:value("on", "Включен (рекомендуется)")
pmtu:value("off", "Отключен (для обхода DPI)")
pmtu:value("blackhole", "Режим blackhole detection")
pmtu.default = "on"
pmtu:depends("enabled", "1")

-- Статус
s_status = m:section(TypedSection, "status", "📊 Текущий статус")
s_status.anonymous = true
s_status.template = "sentinel-kvm/protection_mtu_status"

-- Применение
function m.on_commit(map)
    if enabled:formvalue("1") then
        local mode_val = mode:formvalue()
        local interval_val = interval:formvalue()
        
        os.execute("/usr/bin/sentinel-mtu-random start " .. mode_val .. " --interval " .. interval_val)
        
        -- MSS clamping
        if mss_enabled:formvalue("1") then
            os.execute("/usr/bin/sentinel-mtu-random mss-clamp on")
        end
        
        m.message = "✅ MTU рандомизация активирована"
    else
        os.execute("/usr/bin/sentinel-mtu-random stop")
        m.message = "⏹️ MTU рандомизация отключена"
    end
end

return m