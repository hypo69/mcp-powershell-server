# MCP PowerShell Server

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![MCP Protocol](https://img.shields.io/badge/MCP-2024--11--05-green.svg)](https://modelcontextprotocol.io/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

MCP PowerShell Server — реализация сервера **Model Context Protocol (MCP)** для безопасного выполнения PowerShell скриптов.
Сервер предоставляет стандартизированный интерфейс через **STDIO** и **HTTP/HTTPS**, поддерживает изоляцию процессов, таймауты и детальное логирование.

---

## 🚀 Возможности

* ✅ **MCP Protocol 2024-11-05** — Полная совместимость с протоколом
* 🔒 **Безопасное выполнение** — Изоляция через отдельные процессы PowerShell
* ⏱️ **Контроль времени выполнения** — Настраиваемые таймауты (1–3600 секунд)
* 📁 **Гибкая рабочая среда** — Указание рабочей директории
* 📊 **Детальное логирование** — Полная трассировка выполнения
* 🔄 **STDIO и HTTP/HTTPS интерфейсы**
* 🌐 **UTF-8 поддержка**
* ⚡ **Высокая производительность**

---

## 📋 Требования

* **Windows** 10/11 или Windows Server 2016+
* **PowerShell** 5.1 или выше
* **Права администратора** (опционально для системных команд)

Любой MCP-совместимый клиент, поддерживающий JSON-RPC 2.0 и STDIO или HTTP(S).

---

## 📦 Установка

### Быстрая установка

```powershell
# Метод 1: Прямое скачивание скрипта
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/hypo69/mcp-powershell-server/main/server/mcp-powershell-stdio.ps1" -OutFile "mcp-powershell-stdio.ps1"

# Метод 2: Клонирование репозитория
git clone https://github.com/hypo69/mcp-powershell-server.git
cd mcp-powershell-server/server
```

### Проверка ExecutionPolicy

```powershell
Get-ExecutionPolicy
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## 🖥️ Запуск STDIO сервера

```powershell
echo '{"jsonrpc":"2.0","id":1,"method":"initialize"}' | .\mcp-powershell-stdio.ps1
```

---

## 🌐 Запуск HTTP/HTTPS сервера

### HTTP

```powershell
powershell.exe -File .\mcp-powershell-http.ps1 `
    -Port 8091 `
    -ServerHost "localhost" `
    -AuthToken "supersecrettoken"
```

### HTTPS (с самоподписанным сертификатом)

```powershell
powershell.exe -File .\mcp-powershell-https.ps1 `
    -Port 8092 `
    -ServerHost "localhost" `
    -AuthToken "supersecrettoken" `
    -CertThumbprint "<Thumbprint>"
```

---


Установка как системный сервис (опционально)

```powershell
New-Service -Name "MCP-PowerShell" -BinaryPathName "powershell.exe -File C:\Path\To\mcp-powershell-stdio.ps1" -DisplayName "MCP PowerShell Server"
```

## 🔧 Конфигурация логирования

```powershell
$env:MCP_LOG_PATH = "C:\Logs\mcp-powershell.log"
$env:MCP_LOG_LEVEL = "INFO"
$env:MCP_MAX_LOG_SIZE = "50"
```

---

## 🛠️ Использование MCP

### Инициализация соединения (JSON-RPC)

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": {
      "name": "my-client",
      "version": "1.0.0"
    }
  }
}
```

### Выполнение скрипта

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "run-script",
    "arguments": {
      "script": "Get-Date",
      "timeoutSeconds": 10
    }
  }
}
```

---

## 📂 Примеры клиентов

### PowerShell

```powershell
$Url = "http://localhost:8091/"
$Token = "supersecrettoken"

$Body = @{
    jsonrpc = "2.0"
    id = 1
    method = "tools/call"
    params = @{
        name = "run-script"
        arguments = @{
            script = "Get-Process | Select-Object -First 5"
            timeoutSeconds = 30
        }
    }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri $Url -Method Post -Body $Body -Headers @{ Authorization = "Bearer $Token" } -ContentType "application/json"
```

### Python

```python
import requests
import json

url = "http://localhost:8091/"
token = "supersecrettoken"

payload = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
        "name": "run-script",
        "arguments": {
            "script": "Get-Process | Select-Object -First 5",
            "timeoutSeconds": 30
        }
    }
}

headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json"
}

response = requests.post(url, headers=headers, data=json.dumps(payload))
print(response.json())
```

### Node.js

```javascript
const axios = require("axios");

const url = "http://localhost:8091/";
const token = "supersecrettoken";

const payload = {
  jsonrpc: "2.0",
  id: 1,
  method: "tools/call",
  params: {
    name: "run-script",
    arguments: {
      script: "Get-Process | Select-Object -First 5",
      timeoutSeconds: 30
    }
  }
};

axios.post(url, payload, { headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" } })
  .then(res => console.log(res.data))
  .catch(err => console.error(err));
```

---

## 🔒 Безопасность

* Изоляция процессов
* Контролируемые таймауты
* Валидация входных данных
* Логирование всех действий

**Рекомендации:** запуск под ограниченной учетной записью, настройка прав доступа и мониторинг ресурсов.

---

## 🛠️ Отладка и диагностика

```powershell
# Просмотр последних логов
$logPath = Join-Path $env:TEMP "mcp-powershell-server.log"
Get-Content $logPath -Tail 20

# Включение детального логирования
$env:MCP_LOG_LEVEL = "DEBUG"
```

---

## 📈 Мониторинг

```powershell
function Get-MCPMetrics {
    $logPath = Join-Path $env:TEMP "mcp-powershell-server.log"
    if (-not (Test-Path $logPath)) { return }

    $logContent = Get-Content $logPath
    $today = Get-Date -Format "yyyy-MM-dd"
    $todayLogs = $logContent | Where-Object { $_ -match $today }

    return @{
        TotalRequests = ($todayLogs | Where-Object { $_ -match "Обработка MCP метода" }).Count
        Errors = ($todayLogs | Where-Object { $_ -match "\[ERROR\]" }).Count
        Warnings = ($todayLogs | Where-Object { $_ -match "\[WARNING\]" }).Count
        SuccessfulExecutions = ($todayLogs | Where-Object { $_ -match "успешно" }).Count
        Date = $today
    }
}

Get-MCPMetrics | Format-Table -AutoSize
```

---

## 📚 Ресурсы

* [Model Context Protocol](https://modelcontextprotocol.io/)
* [MCP SDK](https://github.com/modelcontextprotocol/servers)
* [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)

---

## 📄 Лицензия

MIT License — см. файл [LICENSE](LICENSE)

---

## 👥 Авторы

* Основной разработчик: @hypo69
* Участники: [contributors](https://github.com/hypo69/mcp-powershell-server/contributors)

---

Хочешь, я сразу сделаю готовые скрипты:

1. `mcp-powershell-stdio.ps1`
2. `mcp-powershell-http.ps1`
3. `mcp-powershell-https.ps1`

чтобы полностью готово было к запуску на Windows с STDIO и HTTP/HTTPS?
