-- SENTINEL OS KVM - Protocols List
-- /usr/lib/lua/luci/view/sentinel-kvm/protocols/list.htm

<%+header/>

<style>
.protocols-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(400px, 1fr));
    gap: 20px;
    padding: 20px;
}

.protocol-card {
    background: white;
    border-radius: 8px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    padding: 20px;
    transition: transform 0.3s ease;
    position: relative;
    border-left: 4px solid #ddd;
}

.protocol-card.running {
    border-left-color: #4CAF50;
}

.protocol-card.stopped {
    border-left-color: #f44336;
}

.protocol-card.error {
    border-left-color: #ff9800;
}

.protocol-card:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 15px rgba(0,0,0,0.15);
}

.protocol-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 15px;
}

.protocol-name {
    font-size: 18px;
    font-weight: bold;
}

.protocol-type {
    color: #666;
    font-size: 13px;
}

.protocol-badge {
    padding: 4px 8px;
    border-radius: 4px;
    font-size: 11px;
    font-weight: bold;
    text-transform: uppercase;
}

.badge-kvm {
    background: #673AB7;
    color: white;
}

.badge-running {
    background: #4CAF50;
    color: white;
}

.badge-stopped {
    background: #f44336;
    color: white;
}

.metrics-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 10px;
    margin: 15px 0;
    padding: 10px;
    background: #f5f5f5;
    border-radius: 4px;
}

.metric-item {
    text-align: center;
}

.metric-value {
    font-size: 16px;
    font-weight: bold;
    color: #333;
}

.metric-label {
    font-size: 11px;
    color: #666;
}

.actions {
    display: flex;
    gap: 5px;
    margin-top: 15px;
}

.btn {
    flex: 1;
    padding: 8px;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    font-weight: bold;
    transition: opacity 0.3s;
    text-align: center;
    text-decoration: none;
}

.btn:hover {
    opacity: 0.8;
}

.btn-start {
    background: #4CAF50;
    color: white;
}

.btn-stop {
    background: #f44336;
    color: white;
}

.btn-restart {
    background: #ff9800;
    color: white;
}

.btn-config {
    background: #2196F3;
    color: white;
}

.btn-kvm {
    background: #673AB7;
    color: white;
}

.kvm-optimizations {
    margin-top: 10px;
    padding: 10px;
    background: #ede7f6;
    border-radius: 4px;
    font-size: 12px;
    display: none;
}

.kvm-optimizations.show {
    display: block;
}

.filter-bar {
    display: flex;
    gap: 15px;
    margin: 20px;
    padding: 15px;
    background: #f5f5f5;
    border-radius: 8px;
    flex-wrap: wrap;
}

.filter-item {
    display: flex;
    align-items: center;
    gap: 5px;
}

.filter-item select, .filter-item input {
    padding: 5px;
    border: 1px solid #ddd;
    border-radius: 4px;
}

.loading {
    text-align: center;
    padding: 50px;
}

.spinner {
    border: 4px solid #f3f3f3;
    border-top: 4px solid #4CAF50;
    border-radius: 50%;
    width: 40px;
    height: 40px;
    animation: spin 1s linear infinite;
    margin: 0 auto 20px;
}

@keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
}
</style>

<script>
var protocols = {};
var refreshTimer = null;

function loadProtocols() {
    var grid = document.getElementById('protocols-grid');
    grid.innerHTML = '<div class="loading"><div class="spinner"></div>Загрузка...</div>';
    
    XHR.get('<%=luci.dispatcher.build_url("admin/sentinel-kvm/protocols/status")%>', null,
        function(xhr, data) {
            try {
                var result = JSON.parse(data);
                protocols = result.protocols || {};
                displayProtocols(protocols);
            } catch(e) {
                grid.innerHTML = '<div class="loading">❌ Ошибка загрузки</div>';
            }
        }
    );
}

function displayProtocols(protocols) {
    var grid = document.getElementById('protocols-grid');
    var filterType = document.getElementById('filter-type').value;
    var filterStatus = document.getElementById('filter-status').value;
    
    var filtered = {};
    for (var name in protocols) {
        var proto = protocols[name];
        if (filterType !== 'all' && proto.type !== filterType) continue;
        if (filterStatus !== 'all' && proto.status !== filterStatus) continue;
        filtered[name] = proto;
    }
    
    if (Object.keys(filtered).length === 0) {
        grid.innerHTML = '<div class="loading">🔍 Протоколы не найдены</div>';
        return;
    }
    
    var html = '';
    for (var name in filtered) {
        html += generateCard(name, filtered[name]);
    }
    
    grid.innerHTML = html;
}

function generateCard(name, proto) {
    var statusClass = proto.status;
    var statusText = proto.status === 'running' ? 'Активен' : 
                     (proto.status === 'stopped' ? 'Остановлен' : 'Ошибка');
    
    var mem = proto.memory ? proto.memory.toFixed(1) + ' MB' : '—';
    var cpu = proto.cpu ? proto.cpu.toFixed(1) + '%' : '—';
    
    return '<div class="protocol-card ' + statusClass + '" id="proto-' + name + '">' +
        '<div class="protocol-header">' +
        '<div>' +
        '<div class="protocol-name">' + name + '</div>' +
        '<div class="protocol-type">' + proto.type + '</div>' +
        '</div>' +
        '<div>' +
        (proto.kvm_optimized ? '<span class="protocol-badge badge-kvm">KVM</span> ' : '') +
        '<span class="protocol-badge ' + (proto.status === 'running' ? 'badge-running' : 'badge-stopped') + '">' + statusText + '</span>' +
        '</div>' +
        '</div>' +
        
        '<div class="metrics-grid">' +
        '<div class="metric-item"><div class="metric-value">' + (proto.pid || '—') + '</div><div class="metric-label">PID</div></div>' +
        '<div class="metric-item"><div class="metric-value">' + mem + '</div><div class="metric-label">RAM</div></div>' +
        '<div class="metric-item"><div class="metric-value">' + cpu + '</div><div class="metric-label">CPU</div></div>' +
        '</div>' +
        
        '<div class="actions">' +
        '<button class="btn btn-start" onclick="control(\'' + name + '\', \'start\')" ' + (proto.status === 'running' ? 'disabled' : '') + '>▶ Пуск</button>' +
        '<button class="btn btn-stop" onclick="control(\'' + name + '\', \'stop\')" ' + (proto.status !== 'running' ? 'disabled' : '') + '>⏹ Стоп</button>' +
        '<button class="btn btn-restart" onclick="control(\'' + name + '\', \'restart\')">↻ Перезапуск</button>' +
        '<button class="btn btn-config" onclick="window.location=\'<%=luci.dispatcher.build_url("admin/sentinel-kvm/protocols/config")%>?name=' + encodeURIComponent(name) + '\'">⚙️ Настройки</button>' +
        '</div>' +
        
        (proto.kvm_optimizations ? 
        '<div class="kvm-optimizations" id="kvm-' + name + '">' +
        '<strong>⚡ KVM оптимизации:</strong><br>' +
        'Queues: ' + (proto.kvm_optimizations.rx_queues || '—') + '<br>' +
        'TCP Fast Open: ' + (proto.kvm_optimizations.tcp_fastopen ? '✓' : '✗') +
        '</div>' : '') +
        '</div>';
}

function control(protocol, action) {
    XHR.post('<%=luci.dispatcher.build_url("admin/sentinel-kvm/protocols/control")%>', {
        action: action,
        protocol: protocol
    }, function() {
        setTimeout(loadProtocols, 1000);
    });
}

function applyFilters() {
    displayProtocols(protocols);
}

document.addEventListener('DOMContentLoaded', function() {
    loadProtocols();
    refreshTimer = setInterval(loadProtocols, 10000);
});
</script>

<h2>📋 Управление протоколами (KVM Edition)</h2>

<div class="filter-bar">
    <div class="filter-item">
        <label>Тип:</label>
        <select id="filter-type" onchange="applyFilters()">
            <option value="all">Все</option>
            <option value="wireguard">WireGuard</option>
            <option value="xray">Xray</option>
            <option value="openvpn">OpenVPN</option>
        </select>
    </div>
    <div class="filter-item">
        <label>Статус:</label>
        <select id="filter-status" onchange="applyFilters()">
            <option value="all">Все</option>
            <option value="running">Активные</option>
            <option value="stopped">Остановленные</option>
        </select>
    </div>
    <div style="flex:1"></div>
    <a href="<%=luci.dispatcher.build_url("admin/sentinel-kvm/protocols/add")%>" class="btn btn-start">➕ Добавить протокол</a>
</div>

<div id="protocols-grid" class="protocols-grid"></div>

<%+footer%>