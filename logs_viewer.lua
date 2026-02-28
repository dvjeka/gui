-- SENTINEL OS KVM - Logs Viewer
-- /usr/lib/lua/luci/view/sentinel-kvm/logs.htm

<%+header%>

<style>
.logs-container {
    padding: 20px;
}

.logs-controls {
    display: flex;
    gap: 15px;
    margin-bottom: 20px;
    padding: 15px;
    background: #f5f5f5;
    border-radius: 8px;
    flex-wrap: wrap;
    align-items: center;
}

.logs-controls select, .logs-controls input {
    padding: 8px;
    border: 1px solid #ddd;
    border-radius: 4px;
}

.logs-controls button {
    padding: 8px 16px;
    background: #2196F3;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
}

.logs-controls button:hover {
    background: #1976D2;
}

.logs-content {
    background: #1e1e1e;
    color: #d4d4d4;
    padding: 15px;
    border-radius: 4px;
    font-family: 'Courier New', monospace;
    font-size: 12px;
    line-height: 1.5;
    max-height: 600px;
    overflow-y: auto;
    white-space: pre-wrap;
}

.log-line {
    padding: 2px 5px;
    border-bottom: 1px solid #333;
}

.log-line:hover {
    background: #2d2d2d;
}

.log-error {
    color: #f44336;
}

.log-warning {
    color: #ff9800;
}

.log-info {
    color: #2196F3;
}

.log-success {
    color: #4CAF50;
}

.search-highlight {
    background: #ffeb3b;
    color: #000;
    font-weight: bold;
}

.tail-active {
    animation: pulse 1s infinite;
}

@keyframes pulse {
    0% { opacity: 1; }
    50% { opacity: 0.7; }
    100% { opacity: 1; }
}
</style>

<script>
var tailInterval = null;

function loadLogs() {
    var logFile = document.getElementById('log-file').value;
    var lines = document.getElementById('log-lines').value;
    var search = document.getElementById('log-search').value;
    
    var contentDiv = document.getElementById('log-content');
    contentDiv.innerHTML = '<div style="text-align: center; padding: 20px;">⏳ Загрузка...</div>';
    
    XHR.get('<%=luci.dispatcher.build_url("admin/sentinel-kvm/logs/ajax")%>', {
        file: logFile,
        lines: lines
    }, function(xhr, data) {
        try {
            var result = JSON.parse(data);
            displayLogs(result.content, search);
        } catch(e) {
            contentDiv.innerHTML = '<div style="color: red;">❌ Ошибка: ' + e + '</div>';
        }
    });
}

function displayLogs(content, search) {
    var contentDiv = document.getElementById('log-content');
    if (!content) {
        contentDiv.innerHTML = '<div style="text-align: center; color: #666;">Нет данных</div>';
        return;
    }
    
    var lines = content.split('\n');
    var html = '';
    
    lines.forEach(function(line) {
        if (!line) return;
        
        var className = '';
        if (line.includes('ERROR') || line.includes('❌')) className = 'log-error';
        else if (line.includes('WARNING') || line.includes('⚠️')) className = 'log-warning';
        else if (line.includes('INFO')) className = 'log-info';
        else if (line.includes('✅')) className = 'log-success';
        
        var displayLine = line;
        if (search && search.length > 2) {
            var regex = new RegExp(search, 'gi');
            displayLine = line.replace(regex, '<span class="search-highlight">$&</span>');
        }
        
        html += '<div class="log-line ' + className + '">' + displayLine + '</div>';
    });
    
    contentDiv.innerHTML = html;
    
    // Прокрутка вниз
    if (document.getElementById('auto-scroll').checked) {
        contentDiv.scrollTop = contentDiv.scrollHeight;
    }
}

function toggleTail() {
    var btn = document.getElementById('tail-btn');
    if (tailInterval) {
        clearInterval(tailInterval);
        tailInterval = null;
        btn.textContent = '▶ Следить';
        btn.classList.remove('tail-active');
    } else {
        tailInterval = setInterval(loadLogs, 2000);
        btn.textContent = '⏸ Остановить';
        btn.classList.add('tail-active');
    }
}

function downloadLogs() {
    var logFile = document.getElementById('log-file').value;
    window.location = '<%=luci.dispatcher.build_url("admin/sentinel-kvm/logs/download")%>?file=' + 
        encodeURIComponent(logFile);
}

function clearLogs() {
    if (!confirm('Очистить лог-файл?')) return;
    
    var logFile = document.getElementById('log-file').value;
    
    XHR.post('<%=luci.dispatcher.build_url("admin/sentinel-kvm/logs/clear")%>', {
        file: logFile
    }, function() {
        loadLogs();
    });
}

// Инициализация
document.addEventListener('DOMContentLoaded', function() {
    loadLogs();
});
</script>

<h2>📝 Логи системы</h2>

<div class="logs-container">
    <div class="logs-controls">
        <select id="log-file" onchange="loadLogs()">
            <option value="/var/log/sentinel-core.log">sentinel-core.log</option>
            <option value="/var/log/sentinel-dns.log">sentinel-dns.log</option>
            <option value="/var/log/sentinel-nftables.log">sentinel-nftables.log</option>
            <option value="/var/log/adguard-home.log">adguard-home.log</option>
            <option value="/var/log/messages">system.log</option>
        </select>
        
        <select id="log-lines" onchange="loadLogs()">
            <option value="50">50 строк</option>
            <option value="100" selected>100 строк</option>
            <option value="200">200 строк</option>
            <option value="500">500 строк</option>
            <option value="1000">1000 строк</option>
        </select>
        
        <input type="text" id="log-search" placeholder="🔍 Поиск..." onkeyup="loadLogs()">
        
        <button onclick="loadLogs()">🔄 Обновить</button>
        <button id="tail-btn" onclick="toggleTail()">▶ Следить</button>
        <button onclick="downloadLogs()">📥 Скачать</button>
        <button onclick="clearLogs()">🗑️ Очистить</button>
        
        <label style="margin-left: auto;">
            <input type="checkbox" id="auto-scroll" checked> Автопрокрутка
        </label>
    </div>
    
    <div id="log-content" class="logs-content">
        <div style="text-align: center; padding: 20px;">Загрузка...</div>
    </div>
</div>

<%+footer%>