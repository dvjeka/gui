-- SENTINEL OS KVM - Protocols Management CBI
-- /usr/lib/lua/luci/model/cbi/sentinel-kvm/protocols_add.lua

local dsp = require "luci.dispatcher"
local http = require "luci.http"
local uci = require "luci.model.uci".cursor()
local util = require "luci.util"
local json = require "luci.jsonc"

m = Map("sentinel-kvm", "➕ Добавление протокола (KVM Edition)",
    "Добавьте новый протокол с автоматическими KVM-оптимизациями. " ..
    "Система определит тип и применит оптимальные настройки для VirtIO."
)

-- Категории протоколов
categories = {
    { id = "vpn", name = "VPN протоколы", icon = "🔒" },
    { id = "proxy", name = "Прокси", icon = "🔄" },
    { id = "dpi", name = "DPI обход", icon = "🛡️" },
    { id = "tunnel", name = "Туннели", icon = "🌐" }
}

-- Протоколы по категориям
protocols = {
    vpn = {
        { value = "wireguard", name = "WireGuard", desc = "Современный VPN с KVM multiqueue", 
          memory = "low", cpu = "low", kvm_optimized = true },
        { value = "amneziawg", name = "AmneziaWG", desc = "WireGuard с обфускацией", 
          memory = "low", cpu = "low", kvm_optimized = true },
        { value = "openvpn", name = "OpenVPN", desc = "Классический VPN", 
          memory = "medium", cpu = "medium", kvm_optimized = false },
        { value = "xray", name = "Xray", desc = "VLESS/VMess/Reality", 
          memory = "high", cpu = "high", kvm_optimized = true },
        { value = "wireguard-go", name = "WireGuard-Go", desc = "Userspace WireGuard", 
          memory = "medium", cpu = "medium", kvm_optimized = false }
    },
    proxy = {
        { value = "shadowsocks", name = "Shadowsocks", desc = "Легковесный прокси", 
          memory = "low", cpu = "low", kvm_optimized = true },
        { value = "trojan", name = "Trojan", desc = "HTTPS-маскировка", 
          memory = "medium", cpu = "low", kvm_optimized = true },
        { value = "sing-box", name = "Sing-box", desc = "Универсальный прокси", 
          memory = "medium", cpu = "medium", kvm_optimized = true },
        { value = "hysteria2", name = "Hysteria2", desc = "QUIC-based прокси", 
          memory = "medium", cpu = "medium", kvm_optimized = true }
    },
    dpi = {
        { value = "zapret", name = "Zapret", desc = "Обход DPI", 
          memory = "low", cpu = "low", kvm_optimized = true },
        { value = "byedpi", name = "ByeDPI", desc = "DPI обходчик", 
          memory = "low", cpu = "low", kvm_optimized = true },
        { value = "goodbyedpi", name = "GoodbyeDPI", desc = "Классический обходчик", 
          memory = "low", cpu = "low", kvm_optimized = false }
    },
    tunnel = {
        { value = "gre", name = "GRE", desc = "Generic Routing Encapsulation", 
          memory = "low", cpu = "low", kvm_optimized = true },
        { value = "ipip", name = "IPIP", desc = "IP-в-IP туннель", 
          memory = "low", cpu = "low", kvm_optimized = true },
        { value = "vxlan", name = "VXLAN", desc = "Виртуальные сети", 
          memory = "low", cpu = "low", kvm_optimized = true }
    }
}

-- Основная секция выбора
s_main = m:section(TypedSection, "add_protocol", "Выбор протокола")
s_main.anonymous = true

-- Категория
category = s_main:option(ListValue, "category", "Категория")
for _, cat in ipairs(categories) do
    category:value(cat.id, cat.icon .. " " .. cat.name)
end
category.default = "vpn"

-- Протокол (динамически заполняется JavaScript)
protocol_type = s_main:option(ListValue, "protocol_type", "Протокол")
protocol_type:depends("category", "vpn")
for _, proto in ipairs(protocols.vpn) do
    local opt_name = proto.name
    if proto.kvm_optimized then
        opt_name = opt_name .. " ⚡"
    end
    protocol_type:value(proto.value, opt_name)
end

-- Поле для ввода конфигурации
config_input = s_main:option(TextValue, "config_data", "Конфигурация / Ключ")
config_input.rows = 12
config_input.wrap = "off"
config_input.description = [[
Вставьте конфигурацию в любом формате. Поддерживаются:
• WireGuard: стандартный .conf или wg://
• Xray: vless://, vmess://, trojan:// ссылки
• OpenVPN: содержимое .ovpn файла
• Shadowsocks: ss:// ссылка
• AmneziaWG: amnezia:// ссылка
]]

-- Секция KVM-оптимизаций
s_kvm = m:section(TypedSection, "kvm_opts", "⚡ KVM оптимизации")
s_kvm.anonymous = true

-- Автоматические оптимизации
auto_opt = s_kvm:option(Flag, "auto_optimize", "Автооптимизация для KVM")
auto_opt.default = "1"
auto_opt.description = "Автоматически применить оптимальные настройки для VirtIO"

-- Multiqueue
multiqueue = s_kvm:option(Flag, "multiqueue", "Multiqueue (VirtIO)")
multiqueue.default = "1"
multiqueue:depends("auto_optimize", "0")
multiqueue.description = "Включить несколько очередей для сетевых устройств"

-- Количество очередей
queues = s_kvm:option(Value, "queues", "Количество очередей")
queues:depends("multiqueue", "1")
queues:depends("auto_optimize", "0")
queues.datatype = "range(1,16)"
queues.default = "4"

-- TCP Fast Open
tfo = s_kvm:option(Flag, "tcp_fastopen", "TCP Fast Open")
tfo.default = "1"
tfo:depends("auto_optimize", "0")
tfo.description = "Ускоряет установку TCP соединений"

-- BBR
bbr = s_kvm:option(Flag, "bbr", "BBR Congestion Control")
bbr.default = "1"
bbr:depends("auto_optimize", "0")
bbr.description = "Алгоритм контроля перегрузки Google"

-- Секция ограничений ресурсов
s_limits = m:section(TypedSection, "limits", "📊 Лимиты ресурсов (cgroups)")
s_limits.anonymous = true

-- Лимит памяти
mem_limit = s_limits:option(ListValue, "memory_limit", "Лимит памяти")
mem_limit:value("0", "Без лимита")
mem_limit:value("256", "256 MB")
mem_limit:value("512", "512 MB")
mem_limit:value("1024", "1 GB")
mem_limit:value("2048", "2 GB")
mem_limit.default = "0"

-- CPU квота
cpu_quota = s_limits:option(ListValue, "cpu_quota", "CPU квота")
cpu_quota:value("0", "Без ограничений")
cpu_quota:value("25", "25% (1 ядро)")
cpu_quota:value("50", "50% (2 ядра)")
cpu_quota:value("100", "100% (4 ядра)")
cpu_quota:value("200", "200% (8 ядер)")
cpu_quota.default = "0"

-- IO приоритет
io_prio = s_limits:option(ListValue, "io_priority", "I/O приоритет")
io_prio:value("0", "Низкий")
io_prio:value("4", "Средний")
io_prio:value("7", "Высокий")
io_prio.default = "4"

-- Секция дополнительных настроек
s_adv = m:section(TypedSection, "advanced", "⚙️ Дополнительно")
s_adv.anonymous = true

-- Имя конфигурации
name = s_adv:option(Value, "name", "Имя конфигурации")
name.placeholder = "Например: Мой VPN"

-- Автозапуск
auto_start = s_adv:option(Flag, "auto_start", "Автозапуск при загрузке")
auto_start.default = "0"

-- Мониторинг
monitoring = s_adv:option(Flag, "monitoring", "Включить мониторинг")
monitoring.default = "1"
monitoring.description = "Сбор метрик CPU/памяти"

-- Предпросмотр парсинга
s_preview = m:section(TypedSection, "preview", "Предпросмотр")
s_preview.anonymous = true
s_preview.template = "sentinel-kvm/protocols_preview"

-- JavaScript для динамического поведения
m:append(Template("sentinel-kvm/protocols_add_js"))

-- Обработка сохранения
function m.on_commit(map)
    local protocol = map:formvalue("cbid.sentinel-kvm.add_protocol.protocol_type")
    local config = map:formvalue("cbid.sentinel-kvm.add_protocol.config_data")
    local name = map:formvalue("cbid.sentinel-kvm.advanced.name")
    local auto_opt = map:formvalue("cbid.sentinel-kvm.kvm_opts.auto_optimize")
    local mem_limit = map:formvalue("cbid.sentinel-kvm.limits.memory_limit")
    
    if not config or config == "" then
        m.message = "❌ Конфигурация не может быть пустой"
        return false
    end
    
    -- Сохраняем во временный файл
    local tmp_file = "/tmp/sentinel_proto_input.txt"
    local out_file = "/tmp/sentinel_proto_output.json"
    
    local fp = io.open(tmp_file, "w")
    fp:write(config)
    fp:close()
    
    -- Вызываем парсер
    local cmd = string.format(
        "cat %s | /usr/bin/sentinel-core-kvm parse --protocol auto --json > %s 2>&1",
        tmp_file, out_file
    )
    os.execute(cmd)
    
    -- Читаем результат
    local fp = io.open(out_file, "r")
    if fp then
        local result = fp:read("*all")
        fp:close()
        
        local ok, parsed = pcall(json.parse, result)
        if ok and parsed and parsed.parsed then
            -- Добавляем KVM-оптимизации
            parsed.kvm = {
                auto_optimized = (auto_opt == "1"),
                memory_limit = tonumber(mem_limit) or 0,
                virtio_optimized = true
            }
            
            -- Сохраняем конфигурацию
            local save_cmd = string.format(
                "/usr/bin/sentinel-core-kvm save --protocol %s --name '%s' --config '%s'",
                protocol,
                (name ~= "" and name or protocol),
                json.stringify(parsed):gsub("'", "'\\''")
            )
            os.execute(save_cmd)
            
            m.message = "✅ Протокол успешно добавлен с KVM-оптимизациями"
            return true
        else
            m.message = "❌ Ошибка парсинга: " .. (parsed and parsed.error or "Неизвестная ошибка")
            return false
        end
    end
    
    m.message = "❌ Ошибка обработки"
    return false
end

return m