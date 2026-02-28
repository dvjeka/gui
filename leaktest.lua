-- SENTINEL OS KVM - DNS Leak Test Page
-- /usr/lib/lua/luci/view/sentinel-kvm/leaktest/dns.htm

<%+header%>

<style>
.leaktest-container {
    padding: 20px;
}

.test-card {
    background: white;
    border-radius: 8px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    padding: 20px;
    margin-bottom: 20px;
}

.test-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 15px;
    padding-bottom: 10px;
    border-bottom: 2px solid #4CAF50;
}

.test-header h3 {
    margin: 0;
    color: #333;
}

.test-status {
    padding: 4px 12px;
    border-radius: 20px;
    font-size: 0.9em;
    font-weight: bold;
}

.status-pending {
    background: #ff9800;
    color: white;
}

.status-success {
    background: #4CAF50;
    color: white;
}

.status-failed {
    background: #f44336;
    color: white;
}

.test-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    gap: 15px;
    margin: 15px 0;
}

.result-item {
    padding: 15px;
    background: #f5f5f5;
    border-radius: 4px;
}

.result-label {
    font-size: 0.9em;
    color: #666;
    margin-bottom: 5px;
}

.result-value {
    font-size: 1.2em;
    font-weight: bold;
    word-break: break-all;
}

.result-value.good {
    color: #4CAF50;
}

.result-value.bad {
    color: #f44336;
}

.result-value.warning {
    color: #ff9800;
}

.detail-table {
    width: 100%;
    border-collapse: collapse;
    margin-top: 15px;
}

.detail-table th {
    text-align: left;
    padding: 8px;
    background: #f0f0f0;
    font-weight: 600;
}

.detail-table td {
    padding: 8px;
    border-bottom: 1px solid #ddd;
}

.detail-table tr:hover {
    background: #f9f9f9;
}

.progress-bar {
    height: 4px;
    background: #e0e0e0;
    border-radius: 2px;
    overflow: hidden;
    margin: 10px 0;
}

.progress-fill {
    height: 100%;
    background: #4CAF50;
    transition: width 0.3s ease;
}

.recommendations {
    margin-top: 20px;
    padding: 15px;
    background: #fff3e0;
    border-left: 4px solid #ff9800;
    border-radius: 4px;
}

.recommendations h4 {
    margin-top: 0;
    color: #ff9800;
}

.recommendations ul {
    margin: 10px 0;
    padding-left: 20px;
}

.recommendations li {
    margin: 5px 0;
}

.kvm-badge {
    display: inline-block;
    padding: 2px 8px;
    background: #673AB7;
    color: white;
    border-radius: 12px;
    font-size: 0.8em;
    margin-left: 10px;
}

.btn-run {
    background: #4CAF50;
    color: white;
    border: none;
    padding: 10px 20px;
    border-radius: 4px;
    cursor: pointer;
    font-size: 16px;
    font-weight: bold;
    transition: background 0.3s;
}

.btn-run:hover {
    background: #45a049;
}

.btn-run:disabled {
    background: #ccc;
    cursor: not-allowed;
}

.spinner {
    border: 3px solid #f3f3f3;
    border-top: 3px solid #4CAF50;
    border-radius: 50%;
    width: 20px;
    height: 20px;
    animation: spin 1s linear infinite;
    display: inline-block;
    margin-right: 10px;
}

@keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
}
</style>

<script>
function runDNSTest() {
    var btn = document.getElementById('run-btn');
    var status = document.getElementById('test-status');
    var results = document.getElementById('results');
    
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> Выполнение теста...';
    status.className = 'test-status status-pending';
    status.textContent = 'Выполняется...';
    results.style.display = 'none';
    
    XHR.get('<%=luci.dispatcher.build_url("admin/sentinel-kvm/leaktest/dns/run")%>', null,
        function(xhr, data) {
            try {
                var result = JSON.parse(data);
                displayDNSResults(result);
                status.className = 'test-status ' + (result.leaks_detected ? 'status-failed' : 'status-success');
                status.textContent = result.leaks_detected ? 'Обнаружены утечки!' : 'Утечек не обнаружено';
            } catch(e) {
                status.className = 'test-status status-failed';
                status.textContent = 'Ошибка теста';
            } finally {
                btn.disabled = false;
                btn.innerHTML = '▶ Запустить тест';
            }
        }
    );
}

function displayDNSResults(result) {
    var results = document.getElementById('results');
    var html = '<div class="test-grid">';
    
    // Основные метрики
    html += '<div class="result-item">';
    html += '<div class="result-label">Текущий резолвер</div>';
    html += '<div class="result-value' + (result.resolver ? ' good' : '') + '">' + 
            (result.resolver || 'Не определен') + '</div>';
    html += '</div>';
    
    html += '<div class="result-item">';
    html += '<div class="result-label">Тестов выполнено</div>';
    html += '<div class="result-value">' + (result.tests ? result.tests.length : 0) + '</div>';
    html += '</div>';
    
    html += '<div class="result-item">';
    html += '<div class="result-label">DNSSEC</div>';
    html += '<div class="result-value ' + (result.dnssec ? 'good' : 'bad') + '">' + 
            (result.dnssec ? '✅ Работает' : '❌ Отключен') + '</div>';
    html += '</div>';
    
    html += '</div>';
    
    // Детальная таблица
    html += '<table class="detail-table">';
    html += '<tr><th>Домен</th><th>System IP</th><th>DoH IP</th><th>Статус</th></tr>';
    
    if (result.tests) {
        result.tests.forEach(function(test) {
            var status = test.matches ? '✅' : '❌';
            var statusClass = test.matches ? 'good' : 'bad';
            
            html += '<tr>';
            html += '<td>' + test.domain + '</td>';
            html += '<td>' + (test.ips.join(', ') || '-') + '</td>';
            html += '<td>' + (test.doh_ips.join(', ') || '-') + '</td>';
            html += '<td class="' + statusClass + '">' + status + '</td>';
            html += '</tr>';
        });
    }
    
    html += '</table>';
    
    // Рекомендации при обнаружении утечек
    if (result.leaks_detected) {
        html += '<div class="recommendations">';
        html += '<h4>⚠️ Обнаружены утечки DNS!</h4>';
        html += '<ul>';
        html += '<li>Проверьте настройки DNS в AdGuard Home (порт 53)</li>';
        html += '<li>Убедитесь, что dnsmasq отключен (port=0)</li>';
        html += '<li>Проверьте правила nftables: nft list table inet sentinel_dns</li>';
        html += '<li>Перезапустите DNS цепочку: /etc/init.d/adguardhome restart</li>';
        html += '</ul>';
        html += '</div>';
    }
    
    // KVM оптимизации
    if (result.kvm_optimized) {
        html += '<div class="recommendations" style="background: #ede7f6; border-left-color: #673AB7;">';
        html += '<h4 style="color: #673AB7;">⚡ KVM оптимизации применены</h4>';
        html += '<ul>';
        html += '<li>VirtIO multi-queue: ' + (result.kvm_queues || 4) + ' очередей</li>';
        html += '<li>CPU affinity: ' + (result.cpu_affinity || 'не настроено') + '</li>';
        html += '</ul>';
        html += '</div>';
    }
    
    results.innerHTML = html;
    results.style.display = 'block';
}

// Автозапуск при загрузке
document.addEventListener('DOMContentLoaded', function() {
    setTimeout(runDNSTest, 500);
});
</script>

<h2>🔍 DNS Leak Test</h2>

<div class="leaktest-container">
    <div class="test-card">
        <div class="test-header">
            <h3>Проверка утечек DNS</h3>
            <span class="test-status status-pending" id="test-status">Ожидание...</span>
        </div>
        
        <button class="btn-run" id="run-btn" onclick="runDNSTest()">
            ▶ Запустить тест
        </button>
        
        <div id="results" style="display: none; margin-top: 20px;"></div>
    </div>
</div>

<%+footer%>