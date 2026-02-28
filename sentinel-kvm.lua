-- SENTINEL OS KVM - LuCI Controller
-- Главный контроллер веб-интерфейса с KVM-оптимизациями

module("luci.controller.sentinel-kvm", package.seeall)

function index()
    -- Главное меню SENTINEL OS KVM
    entry({"admin", "sentinel-kvm"}, firstchild(), "SENTINEL OS KVM", 80).index = true
    
    -- Дашборд с KVM-метриками
    entry({"admin", "sentinel-kvm", "dashboard"}, template("sentinel-kvm/dashboard"), 
          "KVM Dashboard", 10)
    entry({"admin", "sentinel-kvm", "dashboard", "ajax"}, call("ajax_dashboard"), nil).leaf = true
    
    -- Управление протоколами
    entry({"admin", "sentinel-kvm", "protocols"}, firstchild(), "Протоколы", 20)
    entry({"admin", "sentinel-kvm", "protocols", "list"}, 
          template("sentinel-kvm/protocols/list"), "Список протоколов", 10)
    entry({"admin", "sentinel-kvm", "protocols", "add"}, 
          cbi("sentinel-kvm/protocols_add"), "Добавить протокол", 20)
    entry({"admin", "sentinel-kvm", "protocols", "status"}, 
          call("protocols_status"), nil).leaf = true
    entry({"admin", "sentinel-kvm", "protocols", "control"}, 
          post("protocols_control"), nil).leaf = true
    
    -- DNS Приватность
    entry({"admin", "sentinel-kvm", "dns"}, firstchild(), "DNS Приватность", 30)
    entry({"admin", "sentinel-kvm", "dns", "status"}, 
          call("dns_status"), "Статус DNS", 10)
    entry({"admin", "sentinel-kvm", "dns", "settings"}, 
          cbi("sentinel-kvm/dns_settings"), "Настройки DNS", 20)
    entry({"admin", "sentinel-kvm", "dns", "test"}, 
          call("dns_test"), "Тест утечек", 30)
    
    -- Маршрутизация nftables
    entry({"admin", "sentinel-kvm", "routing"}, firstchild(), "Маршрутизация", 40)
    entry({"admin", "sentinel-kvm", "routing", "rules"}, 
          template("sentinel-kvm/routing/rules"), "Правила nftables", 10)
    entry({"admin", "sentinel-kvm", "routing", "geoip"}, 
          cbi("sentinel-kvm/routing_geoip"), "GEOIP фильтры", 20)
    entry({"admin", "sentinel-kvm", "routing", "ports"}, 
          cbi("sentinel-kvm/routing_ports"), "Проброс портов", 30)
    entry({"admin", "sentinel-kvm", "routing", "apply"}, 
          post("routing_apply"), "Применить правила", 40)
    
    -- KVM оптимизации
    entry({"admin", "sentinel-kvm", "kvm"}, firstchild(), "KVM оптимизации", 50)
    entry({"admin", "sentinel-kvm", "kvm", "resources"}, 
          template("sentinel-kvm/kvm/resources"), "Ресурсы", 10)
    entry({"admin", "sentinel-kvm", "kvm", "virtio"}, 
          cbi("sentinel-kvm/kvm_virtio"), "VirtIO настройки", 20)
    entry({"admin", "sentinel-kvm", "kvm", "performance"}, 
          cbi("sentinel-kvm/kvm_performance"), "Производительность", 30)
    entry({"admin", "sentinel-kvm", "kvm", "metrics"}, 
          call("kvm_metrics"), "Метрики", 40)
    
    -- Дополнительная защита
    entry({"admin", "sentinel-kvm", "protection"}, firstchild(), "Защита", 60)
    entry({"admin", "sentinel-kvm", "protection", "ttl"}, 
          cbi("sentinel-kvm/protection_ttl"), "TTL фаззинг", 10)
    entry({"admin", "sentinel-kvm", "protection", "mtu"}, 
          cbi("sentinel-kvm/protection_mtu"), "MTU рандомизация", 20)
    entry({"admin", "sentinel-kvm", "protection", "stealth"}, 
          cbi("sentinel-kvm/protection_stealth"), "Стелс-режим", 30)
    
    -- Тестирование утечек
    entry({"admin", "sentinel-kvm", "leaktest"}, firstchild(), "Тест утечек", 70)
    entry({"admin", "sentinel-kvm", "leaktest", "dns"}, 
          call("leaktest_dns"), "DNS leak test", 10)
    entry({"admin", "sentinel-kvm", "leaktest", "ip"}, 
          call("leaktest_ip"), "IP leak test", 20)
    entry({"admin", "sentinel-kvm", "leaktest", "webrtc"}, 
          template("sentinel-kvm/leaktest/webrtc"), "WebRTC leak test", 30)
    
    -- Логи и статистика
    entry({"admin", "sentinel-kvm", "logs"}, template("sentinel-kvm/logs"), "Логи", 80)
    entry({"admin", "sentinel-kvm", "logs", "ajax"}, call("ajax_logs"), nil).leaf = true
    
    -- Настройки системы
    entry({"admin", "sentinel-kvm", "settings"}, cbi("sentinel-kvm/settings"), "Настройки", 90)
    entry({"admin", "sentinel-kvm", "settings", "backup"}, 
          call("settings_backup"), "Резервное копирование", 10)
    entry({"admin", "sentinel-kvm", "settings", "restore"}, 
          post("settings_restore"), "Восстановление", 20)
end

-- ============================================================================
-- AJAX обработчики для дашборда
-- ============================================================================

function ajax_dashboard()
    local http = require "luci.http"
    local json = require "luci.jsonc"
    
    http.prepare_content("application/json")
    
    -- Сбор KVM-метрик
    local metrics = {
        timestamp = os.time(),
        kvm = get_kvm_metrics(),
        resources = get_system_resources(),
        protocols = get_protocols_status(),
        nftables = get_nftables_stats()
    }
    
    http.write(json.stringify(metrics))
end

function get_kvm_metrics()
    local metrics = {
        virt_type = luci.sys.exec("systemd-detect-virt 2>/dev/null || echo 'unknown'"):gsub("\n", ""),
        cpu_count = tonumber(luci.sys.exec("nproc")),
        memory_total = tonumber(luci.sys.exec("free -m | grep Mem | awk '{print $2}'")) or 0,
        memory_used = tonumber(luci.sys.exec("free -m | grep Mem | awk '{print $3}'")) or 0,
        virtio_net = {}
    }
    
    -- Проверка VirtIO устройств
    local virtio_check = luci.sys.exec("ls -l /sys/bus/virtio/devices/ 2>/dev/null | wc -l")
    metrics.virtio_devices = tonumber(virtio_check) or 0
    
    -- Сетевые интерфейсы и их драйверы
    local interfaces = luci.sys.exec("ls /sys/class/net/ | grep -v lo")
    for iface in interfaces:gmatch("[^\n]+") do
        local driver = luci.sys.exec(string.format(
            "readlink /sys/class/net/%s/device/driver 2>/dev/null | xargs basename", iface))
        driver = driver:gsub("\n", "")
        
        local queues = luci.sys.exec(string.format(
            "ls -1 /sys/class/net/%s/queues/ 2>/dev/null | grep rx- | wc -l", iface))
        queues = tonumber(queues) or 1
        
        table.insert(metrics.virtio_net, {
            name = iface,
            driver = driver,
            queues = queues
        })
    end
    
    return metrics
end

function get_system_resources()
    return {
        cpu = {
            user = tonumber(luci.sys.exec("top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1")) or 0,
            system = tonumber(luci.sys.exec("top -bn1 | grep 'Cpu(s)' | awk '{print $4}' | cut -d'%' -f1")) or 0,
            idle = tonumber(luci.sys.exec("top -bn1 | grep 'Cpu(s)' | awk '{print $8}' | cut -d'%' -f1")) or 0
        },
        memory = {
            total = tonumber(luci.sys.exec("free -m | grep Mem | awk '{print $2}'")) or 0,
            used = tonumber(luci.sys.exec("free -m | grep Mem | awk '{print $3}'")) or 0,
            free = tonumber(luci.sys.exec("free -m | grep Mem | awk '{print $4}'")) or 0,
            cached = tonumber(luci.sys.exec("free -m | grep Mem | awk '{print $6}'")) or 0
        },
        swap = {
            total = tonumber(luci.sys.exec("free -m | grep Swap | awk '{print $2}'")) or 0,
            used = tonumber(luci.sys.exec("free -m | grep Swap | awk '{print $3}'")) or 0
        },
        loadavg = luci.sys.exec("cat /proc/loadavg | awk '{print $1\" \"$2\" \"$3}'"):gsub("\n", ""),
        uptime = luci.sys.exec("cat /proc/uptime | awk '{print int($1/3600)\"ч \" int(($1%3600)/60)\"м\"}'"):gsub("\n", "")
    }
end

function get_protocols_status()
    local status = {}
    local sentinel_status = luci.sys.exec("/usr/bin/sentinel-core-kvm status --json 2>/dev/null")
    
    if sentinel_status and #sentinel_status > 0 then
        local json = require "luci.jsonc"
        local parsed = json.parse(sentinel_status)
        if parsed and parsed.protocols then
            return parsed.protocols
        end
    end
    
    return status
end

function get_nftables_stats()
    local stats = {
        tables = {},
        rules = 0,
        chains = 0
    }
    
    -- Получение списка таблиц
    local tables = luci.sys.exec("nft list tables 2>/dev/null")
    for table in tables:gmatch("[^\n]+") do
        table = table:gsub("table ", "")
        table = table:gsub(" ", "_")
        table = table:gsub("\n", "")
        if #table > 0 then
            table.insert(stats.tables, table)
        end
    end
    
    -- Подсчет правил
    stats.rules = tonumber(luci.sys.exec("nft list ruleset 2>/dev/null | grep -c ' rule '")) or 0
    stats.chains = tonumber(luci.sys.exec("nft list ruleset 2>/dev/null | grep -c ' chain '")) or 0
    
    return stats
end

-- ============================================================================
-- Управление протоколами
-- ============================================================================

function protocols_status()
    local http = require "luci.http"
    local json = require "luci.jsonc"
    
    http.prepare_content("application/json")
    
    local status = luci.sys.exec("/usr/bin/sentinel-core-kvm status --json 2>/dev/null")
    if status and #status > 0 then
        http.write(status)
    else
        http.write(json.stringify({error = "Не удалось получить статус"}))
    end
end

function protocols_control()
    local http = require "luci.http"
    local json = require "luci.jsonc"
    
    local action = http.formvalue("action")
    local protocol = http.formvalue("protocol")
    
    if not action or not protocol then
        http.status(400, "Bad Request")
        return
    end
    
    local result = luci.sys.exec(string.format(
        "/usr/bin/sentinel-core-kvm %s --protocol %s 2>&1", action, protocol))
    
    http.prepare_content("application/json")
    http.write(json.stringify({
        success = (result:find("✅") ~= nil),
        message = result
    }))
end

-- ============================================================================
-- DNS статус и тесты
-- ============================================================================

function dns_status()
    local http = require "luci.http"
    local json = require "luci.jsonc"
    
    http.prepare_content("application/json")
    
    local status = {
        mode = luci.sys.exec("/usr/bin/sentinel-dns-switch status 2>/dev/null | grep 'Режим' | awk '{print $2}'"):gsub("\n", ""),
        services = {}
    }
    
    -- Проверка DNS сервисов
    local services = {"unbound", "stubby", "dnscrypt-proxy", "adguardhome"}
    for _, service in ipairs(services) do
        local running = luci.sys.call(string.format("/etc/init.d/%s running >/dev/null 2>&1", service))
        status.services[service] = (running == 0) and "running" or "stopped"
    end
    
    http.write(json.stringify(status))
end

function dns_test()
    local http = require "luci.http"
    local json = require "luci.jsonc"
    
    http.prepare_content("application/json")
    
    local test_type = http.formvalue("type") or "basic"
    local result = luci.sys.exec(string.format("/usr/bin/sentinel-dns-leak-test --%s 2>/dev/null", test_type))
    
    http.write(json.stringify({
        result = result
    }))
end

-- ============================================================================
-- Маршрутизация nftables
-- ============================================================================

function routing_apply()
    local http = require "luci.http"
    local json = require "luci.jsonc"
    
    local result = luci.sys.exec("/usr/bin/sentinel-nftables apply 2>&1")
    
    http.prepare_content("application/json")
    http.write(json.stringify({
        success = (result:find("✅") ~= nil),
        message = result
    }))
end

-- ============================================================================
-- KVM метрики
-- ============================================================================

function kvm_metrics()
    local http = require "luci.http"
    local json = require "luci.jsonc"
    
    http.prepare_content("application/json")
    
    local metrics = {
        ksm = get_ksm_stats(),
        balloon = get_balloon_stats(),
        vhost = get_vhost_stats()
    }
    
    http.write(json.stringify(metrics))
end

function get_ksm_stats()
    local stats = {
        enabled = false,
        pages_shared = 0,
        pages_sharing = 0,
        pages_unshared = 0,
        savings_mb = 0
    }
    
    local run = tonumber(luci.sys.exec("cat /sys/kernel/mm/ksm/run 2>/dev/null")) or 0
    stats.enabled = (run == 1)
    
    if stats.enabled then
        stats.pages_shared = tonumber(luci.sys.exec("cat /sys/kernel/mm/ksm/pages_shared 2>/dev/null")) or 0
        stats.pages_sharing = tonumber(luci.sys.exec("cat /sys/kernel/mm/ksm/pages_sharing 2>/dev/null")) or 0
        stats.pages_unshared = tonumber(luci.sys.exec("cat /sys/kernel/mm/ksm/pages_unshared 2>/dev/null")) or 0
        stats.savings_mb = (stats.pages_sharing * 4) / 1024  -- 4KB per page
    end
    
    return stats
end

function get_balloon_stats()
    local stats = {
        present = false,
        current = 0,
        target = 0,
        free = 0
    }
    
    -- Проверка наличия VirtIO balloon
    local balloon = luci.sys.exec("ls -d /sys/devices/virtio-balloon* 2>/dev/null | head -1")
    if #balloon > 0 then
        stats.present = true
        stats.current = tonumber(luci.sys.exec("cat " .. balloon .. "/free_page_reporting 2>/dev/null")) or 0
    end
    
    return stats
end

function get_vhost_stats()
    local stats = {
        vhost_net = false,
        queues = 0
    }
    
    -- Проверка vhost-net
    local vhost = luci.sys.exec("lsmod | grep vhost_net")
    stats.vhost_net = (#vhost > 0)
    
    -- Количество очередей
    stats.queues = tonumber(luci.sys.exec("ls -d /sys/class/net/*/queues/rx-* 2>/dev/null | wc -l")) or 0
    
    return stats
end

-- ============================================================================
-- Тестирование утечек
-- ============================================================================

function leaktest_dns()
    local http = require "luci.http"
    
    local result = luci.sys.exec("/usr/bin/sentinel-dns-leak-test 2>&1")
    
    http.prepare_content("text/plain")
    http.write(result)
end

function leaktest_ip()
    local http = require "luci.http"
    local json = require "luci.jsonc"
    
    local result = {
        vpn_ip = luci.sys.exec("curl -s --max-time 5 https://api.ipify.org 2>/dev/null"):gsub("\n", ""),
        direct_ip = luci.sys.exec("curl -s --max-time 5 --interface eth0 https://api.ipify.org 2>/dev/null"):gsub("\n", ""),
        ipv6 = luci.sys.exec("curl -6 -s --max-time 5 https://api6.ipify.org 2>/dev/null"):gsub("\n", "")
    }
    
    -- Геолокация
    if #result.vpn_ip > 0 then
        local geo = luci.sys.exec(string.format(
            "curl -s http://ip-api.com/json/%s 2>/dev/null", result.vpn_ip))
        result.geolocation = json.parse(geo) or {}
    end
    
    http.prepare_content("application/json")
    http.write(json.stringify(result))
end

-- ============================================================================
-- Логи
-- ============================================================================

function ajax_logs()
    local http = require "luci.http"
    local json = require "luci.jsonc"
    
    local logfile = http.formvalue("file") or "/var/log/sentinel-core.log"
    local lines = tonumber(http.formvalue("lines")) or 100
    
    local logs = luci.sys.exec(string.format("tail -n %d %s 2>/dev/null", lines, logfile))
    
    http.prepare_content("application/json")
    http.write(json.stringify({
        file = logfile,
        lines = lines,
        content = logs
    }))
end

-- ============================================================================
-- Резервное копирование и восстановление
-- ============================================================================

function settings_backup()
    local http = require "luci.http"
    
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local backup_file = "/tmp/sentinel-kvm-backup-" .. timestamp .. ".tar.gz"
    
    luci.sys.exec(string.format([[
        tar -czf %s \
            /etc/sentinel/ \
            /etc/nftables.d/ \
            /etc/config/sentinel* \
            /etc/wireguard/*.conf \
            /etc/openvpn/*.conf \
            /etc/xray/*.json \
            2>/dev/null
    ]], backup_file))
    
    http.header("Content-Disposition", "attachment; filename=sentinel-kvm-backup-" .. timestamp .. ".tar.gz")
    http.header("Content-Type", "application/gzip")
    http.write(luci.sys.exec("cat " .. backup_file))
    
    luci.sys.exec("rm -f " .. backup_file)
end

function settings_restore()
    local http = require "luci.http"
    
    local uploaded = http.formvalue("backup_file")
    
    if uploaded then
        local tmp_file = "/tmp/sentinel-kvm-restore.tar.gz"
        local fp = io.open(tmp_file, "w")
        fp:write(uploaded)
        fp:close()
        
        luci.sys.exec("tar -xzf " .. tmp_file .. " -C /")
        luci.sys.exec("rm -f " .. tmp_file)
        luci.sys.exec("/etc/init.d/sentinel-core-kvm restart")
        
        http.redirect(luci.dispatcher.build_url("admin/sentinel-kvm/settings"))
    else
        luci.template.render("sentinel-kvm/settings_restore")
    end
end