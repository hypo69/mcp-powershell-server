
# MCP PowerShell Server

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![MCP Protocol](https://img.shields.io/badge/MCP-2024--11--05-green.svg)](https://modelcontextprotocol.io/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

MCP PowerShell Server — это реализация сервера Model Context Protocol (MCP) для безопасного выполнения PowerShell скриптов. Сервер предоставляет стандартизированный интерфейс для выполнения PowerShell команд через MCP протокол с поддержкой изоляции процессов, таймаутов и детального логирования.

---

## 🚀 Возможности

* ✅ **MCP Protocol 2024-11-05** — Полная совместимость с последней версией протокола
* 🔒 **Безопасное выполнение** — Изоляция через отдельные PowerShell процессы
* ⏱️ **Контроль времени выполнения** — Настраиваемые таймауты (1–3600 секунд)
* 📁 **Гибкая рабочая среда** — Возможность указания рабочей директории
* 📊 **Детальное логирование** — Полная трассировка выполнения с разными уровнями
* 🔄 **STDIO интерфейс** — Работа через стандартные потоки ввода/вывода
* 🌐 **UTF-8 поддержка** — Корректная обработка Unicode символов
* ⚡ **Высокая производительность** — Минимальные накладные расходы

---

## 📋 Требования

### Системные требования

* **Windows** 10/11 или Windows Server 2016+
* **PowerShell** 7.x
* **Права администратора** (опционально, для выполнения системных команд)

### MCP Client

Любой MCP-совместимый клиент, поддерживающий:

* MCP Protocol версии 2024-11-05
* STDIO или HTTP(S) транспорт
* JSON-RPC 2.0

---

## 📦 Установка

### Быстрая установка (STDIO)

1. **Скачайте скрипт**:

```powershell
# Метод 1: Прямое скачивание
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/hypo69/mcp-powershell-server/main/mcp-powershell-stdio.ps1" -OutFile "mcp-powershell-stdio.ps1"

# Метод 2: Клонирование репозитория
git clone https://github.com/hypo69/mcp-powershell-server.git
cd mcp-powershell-server
```

2. **Проверьте права выполнения**:

```powershell
Get-ExecutionPolicy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

3. **Тестовый запуск**:

```powershell
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | .\mcp-powershell-stdio.ps1
```

---

### Установка HTTP(S) сервера

```powershell
# Запуск HTTP сервера на порту 8091 с токеном авторизации
powershell.exe -File .\mcp-powershell-http.ps1 `
    -Port 8091 `
    -ServerHost "localhost" `
    -AuthToken "supersecrettoken"

# Для HTTPS добавьте параметр -CertThumbprint "<Thumbprint>"
```

---

### Установка как системный сервис (опционально)

```powershell
New-Service -Name "MCP-PowerShell" -BinaryPathName "powershell.exe -File C:\Path\To\mcp-powershell-stdio.ps1" -DisplayName "MCP PowerShell Server"
```

---

## 🔧 Конфигурация

### Переменные окружения

```powershell
$env:MCP_LOG_PATH = "C:\Logs\mcp-powershell.log"
$env:MCP_LOG_LEVEL = "INFO"  # DEBUG, INFO, WARNING, ERROR
$env:MCP_MAX_LOG_SIZE = "50" # МБ
```

### Настройка MCP клиентов

#### Claude Desktop

```json
{
  "mcpServers": {
    "powershell": {
      "command": "powershell.exe",
      "args": ["-File", "C:\\Path\\To\\mcp-powershell-stdio.ps1"],
      "env": { "MCP_LOG_LEVEL": "INFO" }
    }
  }
}
```

#### Cline (VS Code Extension)

```json
{
  "mcp": {
    "powershell": {
      "command": "powershell.exe",
      "args": ["-File", "C:\\Path\\To\\mcp-powershell-stdio.ps1"]
    }
  }
}
```

---

## 🛠️ Примеры использования

### STDIO

```powershell
# 1️⃣ Тестовый запрос
$request = @{
    jsonrpc = "2.0"
    id = 1
    method = "tools/call"
    params = @{
        name = "run-script"
        arguments = @{
            script = "Get-Date"
            timeoutSeconds = 10
        }
    }
} | ConvertTo-Json -Depth 5

$request | .\mcp-powershell-stdio.ps1
```

```powershell
# 2️⃣ Системная информация
$scriptRequest = @{
    jsonrpc = "2.0"
    id = 3
    method = "tools/call"
    params = @{
        name = "run-script"
        arguments = @{
            script = "Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, TotalPhysicalMemory"
            timeoutSeconds = 30
        }
    }
} | ConvertTo-Json -Depth 5

$scriptRequest | .\mcp-powershell-stdio.ps1
```

```powershell
# 3️⃣ Работа с файлами
$script = "Get-ChildItem -Path $env:USERPROFILE -File | Sort-Object LastWriteTime -Descending | Select-Object -First 10 Name, Length, LastWriteTime"
$request = @{
    jsonrpc = "2.0"
    id = 4
    method = "tools/call"
    params = @{
        name = "run-script"
        arguments = @{
            script = $script
            workingDirectory = "C:\Users\Username"
            timeoutSeconds = 60
        }
    }
} | ConvertTo-Json -Depth 5

$request | .\mcp-powershell-stdio.ps1
```

```powershell
# 4️⃣ Мониторинг процессов
$script = "Get-Process | Where-Object {$_.CPU -gt 10} | Sort-Object CPU -Descending | Select-Object -First 5 Name, CPU, WorkingSet"
$request = @{
    jsonrpc = "2.0"
    id = 5
    method = "tools/call"
    params = @{
        name = "run-script"
        arguments = @{
            script = $script
            timeoutSeconds = 45
        }
    }
} | ConvertTo-Json -Depth 5

$request | .\mcp-powershell-stdio.ps1
```

```powershell
# 5️⃣ Скрипт с параметрами
$script = "param($ProcessName, $Top = 5) Get-Process $ProcessName | Sort-Object CPU -Descending | Select-Object -First $Top Name, CPU, WorkingSet"
$request = @{
    jsonrpc = "2.0"
    id = 8
    method = "tools/call"
    params = @{
        name = "run-script"
        arguments = @{
            script = $script
            parameters = @{
                ProcessName = "powershell"
                Top = 3
            }
            timeoutSeconds = 30
        }
    }
} | ConvertTo-Json -Depth 5

$request | .\mcp-powershell-stdio.ps1
```

### HTTP(S)

```powershell
$Url = "http://localhost:8091/"
$Token = "supersecrettoken"

$Body = @{
    jsonrpc = "2.0"
    id = 2
    method = "tools/call"
    params = @{
        name = "run-script"
        arguments = @{
            script = "Get-Date"
            timeoutSeconds = 10
        }
    }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri $Url -Method Post -Body $Body -Headers @{ Authorization = "Bearer $Token" } -ContentType "application/json"
```

---

## 🛡️ Безопасность

* **Изоляция процессов** — каждый скрипт выполняется в отдельном PowerShell процессе
* **Контролируемые таймауты** — автоматическое прерывание долгих скриптов
* **Валидация входных данных** — проверка всех MCP запросов
* **Логирование действий** — полная трассировка для аудита

**Рекомендации:**

```powershell
# 1. Запуск под ограниченной учетной записью
New-LocalUser -Name "MCPService" -NoPassword -UserMayNotChangePassword

# 2. Ограничение прав доступа
# Настройте права доступа только к необходимым папкам

# 3. Сетевая изоляция
# Настройте firewall для ограничения подключений

# 4. Мониторинг ресурсов
# Установите лимиты на CPU и память
```

---

## 🔍 Отладка и диагностика

```powershell
$logPath = Join-Path $env:TEMP "mcp-powershell-server.log"
Get-Content $logPath -Tail 10
```

```powershell
# Мониторинг в реальном времени
Get-Content $logPath -Wait | ForEach-Object { Write-Host $_ }
```

---

## 📈 Мониторинг и метрики

```powershell
function Get-MCPMetrics {
    $logPath = Join-Path $env:TEMP "mcp-powershell-server.log"
    if (-not (Test-Path $logPath)) { return }
    $logContent = Get-Content $logPath
    $todayLogs = $logContent | Where-Object { $_ -match (Get-Date -Format "yyyy-MM-dd") }
    return @{
        TotalRequests = ($todayLogs | Where-Object { $_ -match "Обработка MCP метода" }).Count
        Errors = ($todayLogs | Where-Object { $_ -match "\[ERROR\]" }).Count
        Warnings = ($todayLogs | Where-Object { $_ -match "\[WARNING\]" }).Count
        SuccessfulExecutions = ($todayLogs | Where-Object { $_ -match "успешно" }).Count
    }
}

Get-MCPMetrics | Format-Table -AutoSize
```

---

## 📚 Дополнительные ресурсы

* [Model Context Protocol](https://modelcontextprotocol.io/)
* [MCP Specification](https://spec.modelcontextprotocol.io/)
* [MCP SDK](https://github.com/modelcontextprotocol/servers)
* [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)
* [PowerShell Gallery](https://www.powershellgallery.com/)
* [PowerShell Community](https://github.com/PowerShell/PowerShell)

---

## 📄 Лицензия

MIT License — см. файл [LICENSE](LICENSE)

---

## 👥 Авторы и участники

* **Основной разработчик** — @hypo69
* **Участники** — [contributors](https://github.com/hypo69/mcp-powershell-server/contributors)

