# MCP PowerShell Server

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![MCP Protocol](https://img.shields.io/badge/MCP-2024--11--05-green.svg)](https://modelcontextprotocol.io/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

MCP PowerShell Server - это реализация сервера Model Context Protocol (MCP) для безопасного выполнения PowerShell скриптов. Сервер предоставляет стандартизированный интерфейс для выполнения PowerShell команд через MCP протокол с поддержкой изоляции процессов, таймаутов и детального логирования.

## 🚀 Возможности

- ✅ **MCP Protocol 2024-11-05** - Полная совместимость с последней версией протокола
- 🔒 **Безопасное выполнение** - Изоляция через отдельные PowerShell процессы
- ⏱️ **Контроль времени выполнения** - Настраиваемые таймауты (1-3600 секунд)
- 📁 **Гибкая рабочая среда** - Возможность указания рабочей директории
- 📊 **Детальное логирование** - Полная трассировка выполнения с разными уровнями
- 🔄 **STDIO интерфейс** - Работа через стандартные потоки ввода/вывода
- 🌐 **UTF-8 поддержка** - Корректная обработка unicode символов
- ⚡ **Высокая производительность** - Минимальные накладные расходы

## 📋 Требования

### Системные требования
- **Windows** 10/11 или Windows Server 2016+
- **PowerShell** 5.1 или выше (включая PowerShell 7.x)
- **Права администратора** (опционально, для выполнения системных команд)

### MCP Client
Любой MCP-совместимый клиент, поддерживающий:
- MCP Protocol версии 2024-11-05
- STDIO транспорт
- JSON-RPC 2.0

## 📦 Установка

### Быстрая установка

1. **Скачайте скрипт**:
   ```powershell
   # Метод 1: Прямое скачивание
   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/your-repo/mcp-powershell-stdio.ps1" -OutFile "mcp-powershell-stdio.ps1"
   
   # Метод 2: Клонирование репозитория
   git clone https://github.com/your-repo/mcp-powershell-server.git
   cd mcp-powershell-server
   ```

2. **Проверьте права выполнения**:
   ```powershell
   # Проверка текущей политики выполнения
   Get-ExecutionPolicy
   
   # При необходимости разрешите выполнение (только для текущего пользователя)
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

3. **Тестовый запуск**:
   ```powershell
   # Запуск с тестовым сообщением
   echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | .\mcp-powershell-stdio.ps1
   ```

### Установка как системный сервис (опционально)

```powershell
# Создание службы Windows
New-Service -Name "MCP-PowerShell" -BinaryPathName "powershell.exe -File C:\Path\To\mcp-powershell-stdio.ps1" -DisplayName "MCP PowerShell Server"
```

## 🔧 Конфигурация

### Переменные окружения

```powershell
# Установка пути к лог-файлу (по умолчанию: %TEMP%\mcp-powershell-server.log)
$env:MCP_LOG_PATH = "C:\Logs\mcp-powershell.log"

# Установка уровня логирования (DEBUG, INFO, WARNING, ERROR)
$env:MCP_LOG_LEVEL = "INFO"

# Максимальный размер лог-файла в МБ (по умолчанию: 10)
$env:MCP_MAX_LOG_SIZE = "50"
```

### Настройка для разных MCP клиентов

#### Claude Desktop
Добавьте в конфигурацию `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "powershell": {
      "command": "powershell.exe",
      "args": ["-File", "C:\\Path\\To\\mcp-powershell-stdio.ps1"],
      "env": {
        "MCP_LOG_LEVEL": "INFO"
      }
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

## 🛠️ Использование

### Базовые команды

#### 1. Инициализация соединения
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

**Ответ:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "capabilities": {
      "tools": {
        "listChanged": true
      }
    },
    "serverInfo": {
      "name": "PowerShell Script Runner",
      "version": "1.0.0",
      "description": "Выполняет PowerShell скрипты через MCP"
    }
  }
}
```

#### 2. Получение списка инструментов
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list"
}
```

### Практические примеры

#### 📊 Системная информация
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "run-script",
    "arguments": {
      "script": "Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, TotalPhysicalMemory",
      "timeoutSeconds": 30
    }
  }
}
```

#### 📁 Работа с файлами
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "run-script",
    "arguments": {
      "script": "Get-ChildItem -Path $env:USERPROFILE -File | Sort-Object LastWriteTime -Descending | Select-Object -First 10 Name, Length, LastWriteTime",
      "workingDirectory": "C:\\Users\\Username",
      "timeoutSeconds": 60
    }
  }
}
```

#### 🔍 Мониторинг процессов
```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "tools/call",
  "params": {
    "name": "run-script",
    "arguments": {
      "script": "Get-Process | Where-Object {$_.CPU -gt 10} | Sort-Object CPU -Descending | Select-Object -First 5 Name, CPU, WorkingSet",
      "timeoutSeconds": 45
    }
  }
}
```

#### 🌐 Сетевые подключения
```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "method": "tools/call",
  "params": {
    "name": "run-script",
    "arguments": {
      "script": "Get-NetTCPConnection | Where-Object {$_.State -eq 'Established'} | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort | Sort-Object LocalPort",
      "timeoutSeconds": 30
    }
  }
}
```

#### 📦 Управление службами
```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "method": "tools/call",
  "params": {
    "name": "run-script",
    "arguments": {
      "script": "Get-Service | Where-Object {$_.Status -eq 'Running'} | Sort-Object Name | Select-Object Name, Status, StartType",
      "timeoutSeconds": 60
    }
  }
}
```

#### 📋 Скрипт с параметрами
```json
{
  "jsonrpc": "2.0",
  "id": 8,
  "method": "tools/call",
  "params": {
    "name": "run-script",
    "arguments": {
      "script": "param($ProcessName, $Top = 5) Get-Process $ProcessName | Sort-Object CPU -Descending | Select-Object -First $Top Name, CPU, WorkingSet",
      "parameters": {
        "ProcessName": "powershell",
        "Top": 3
      },
      "timeoutSeconds": 30
    }
  }
}
```

### Командная строка

#### Интерактивное тестирование
```powershell
# Создание тестового запроса
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

# Отправка запроса серверу
$request | .\mcp-powershell-stdio.ps1
```

#### Пакетная обработка
```powershell
# Файл с множественными запросами
$requests = @(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}',
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"run-script","arguments":{"script":"Get-Date"}}}'
)

# Выполнение всех запросов
$requests | ForEach-Object { 
    Write-Host "Request: $_"
    $_ | .\mcp-powershell-stdio.ps1
    Write-Host "---"
}
```

## 🔧 Расширенная конфигурация

### Кастомизация логирования

```powershell
# В начале скрипта mcp-powershell-stdio.ps1 можно изменить:

# Кастомный путь к лог-файлу
$LogFile = "C:\MyApp\Logs\mcp-powershell-$(Get-Date -Format 'yyyyMMdd').log"

# Функция ротации логов
function Rotate-LogFile {
    param([string]$LogPath, [int]$MaxSizeMB = 10)
    
    if ((Test-Path $LogPath) -and ((Get-Item $LogPath).Length / 1MB -gt $MaxSizeMB)) {
        $backupPath = $LogPath -replace '\.log$', "_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        Move-Item $LogPath $backupPath
    }
}
```

### Добавление кастомных инструментов

```powershell
# В функции Invoke-MCPMethod добавьте новый case:
"my-custom-tool" {
    # Проверка параметров
    if (-not $arguments.ContainsKey("parameter1")) {
        return New-MCPResponse -Id $Id -Error @{
            code = -32602
            message = "Missing required parameter 'parameter1'"
        }
    }
    
    # Выполнение кастомной логики
    $result = My-CustomFunction -Param1 $arguments.parameter1
    
    # Возврат результата
    return New-MCPResponse -Id $Id -Result @{
        content = @(
            @{
                type = "text"
                text = "Custom tool result: $result"
            }
        )
    }
}
```

## 🛡️ Безопасность

### Принципы безопасности

1. **Изоляция процессов** - каждый скрипт выполняется в отдельном PowerShell процессе
2. **Контролируемые таймауты** - автоматическое прерывание долго выполняющихся скриптов  
3. **Валидация входных данных** - проверка всех MCP запросов
4. **Логирование действий** - полная трассировка для аудита

### Рекомендации по безопасности

```powershell
# 1. Запуск под ограниченной учетной записью
# Создайте отдельного пользователя для MCP сервера
New-LocalUser -Name "MCPService" -NoPassword -UserMayNotChangePassword

# 2. Ограничение прав доступа
# Настройте права доступа только к необходимым папкам

# 3. Сетевая изоляция
# При необходимости используйте файрвол для ограничения сетевых подключений

# 4. Мониторинг ресурсов
# Установите лимиты на использование CPU и памяти
```

### Валидация и фильтрация

```powershell
# Добавьте дополнительные проверки в Invoke-PowerShellScript:

# Черный список команд
$BlacklistedCommands = @(
    'Remove-Item', 'Delete', 'Format-Volume', 
    'Stop-Computer', 'Restart-Computer'
)

# Проверка скрипта на запрещенные команды
foreach ($cmd in $BlacklistedCommands) {
    if ($Script -match $cmd) {
        throw "Script contains blacklisted command: $cmd"
    }
}
```

## 🔍 Отладка и диагностика

### Включение детального логирования

```powershell
# Установка уровня DEBUG для подробных логов
$env:MCP_LOG_LEVEL = "DEBUG"

# Или изменение в коде:
function Write-Log {
    # Изменить уровень по умолчанию
    [string]$Level = "DEBUG"  # Вместо "INFO"
}
```

### Анализ логов

```powershell
# Поиск ошибок в логах
Get-Content $LogFile | Where-Object { $_ -match "ERROR" } | Select-Object -Last 10

# Статистика по уровням логирования
$logContent = Get-Content $LogFile
$stats = @{}
@("INFO", "WARNING", "ERROR", "DEBUG") | ForEach-Object {
    $stats[$_] = ($logContent | Where-Object { $_ -match "\[$_\]" }).Count
}
$stats

# Последние действия
Get-Content $LogFile | Select-Object -Last 20
```

### Тестирование производительности

```powershell
# Скрипт для тестирования производительности
$testScript = @"
{
  "jsonrpc": "2.0",
  "id": 999,
  "method": "tools/call",
  "params": {
    "name": "run-script",
    "arguments": {
      "script": "Measure-Command { Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 }",
      "timeoutSeconds": 30
    }
  }
}
"@

# Измерение времени ответа
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$result = $testScript | .\mcp-powershell-stdio.ps1
$stopwatch.Stop()
Write-Host "Response time: $($stopwatch.ElapsedMilliseconds)ms"
```

## ❗ Устранение неисправностей

### Типичные проблемы и решения

#### 1. Сервер не отвечает на запросы

**Проблема**: Запросы отправляются, но ответов нет.

**Решение**:
```powershell
# Проверка процесса
Get-Process | Where-Object { $_.ProcessName -match "powershell" }

# Проверка логов
Get-Content $LogFile -Tail 20

# Тестовый запрос с таймаутом
$testRequest = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
$testRequest | .\mcp-powershell-stdio.ps1
```

#### 2. Ошибки кодировки

**Проблема**: Некорректное отображение русских символов.

**Решение**:
```powershell
# Установка кодировки в начале скрипта
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
chcp 65001
```

#### 3. Таймауты выполнения

**Проблема**: Скрипты прерываются по таймауту.

**Решение**:
```powershell
# Увеличение таймаута для конкретного запроса
{
  "arguments": {
    "script": "Long-Running-Command",
    "timeoutSeconds": 1800  # 30 минут
  }
}

# Или изменение значения по умолчанию в коде
[int]$TimeoutSeconds = 1800  # Вместо 300
```

#### 4. Проблемы с правами доступа

**Проблема**: "Access Denied" или "Execution Policy" ошибки.

**Решение**:
```powershell
# Проверка текущих прав
whoami /groups
Get-ExecutionPolicy -List

# Временное изменение политики выполнения
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# Запуск с правами администратора (если необходимо)
Start-Process powershell -Verb RunAs -ArgumentList "-File mcp-powershell-stdio.ps1"
```

### Полная диагностика

```powershell
# Скрипт диагностики MCP сервера
Write-Host "=== MCP PowerShell Server Diagnostics ===" -ForegroundColor Green

# 1. Версия PowerShell
Write-Host "`n1. PowerShell Version:" -ForegroundColor Yellow
$PSVersionTable

# 2. Execution Policy
Write-Host "`n2. Execution Policy:" -ForegroundColor Yellow
Get-ExecutionPolicy -List

# 3. Доступность скрипта
$scriptPath = ".\mcp-powershell-stdio.ps1"
Write-Host "`n3. Script Accessibility:" -ForegroundColor Yellow
Write-Host "Exists: $(Test-Path $scriptPath)"
if (Test-Path $scriptPath) {
    Write-Host "Size: $((Get-Item $scriptPath).Length) bytes"
    Write-Host "Last Modified: $((Get-Item $scriptPath).LastWriteTime)"
}

# 4. Тест базового запроса
Write-Host "`n4. Basic Request Test:" -ForegroundColor Yellow
$initRequest = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
try {
    $response = $initRequest | & $scriptPath
    Write-Host "Response received: $($response.Length) characters"
    $response | ConvertFrom-Json | ConvertTo-Json -Depth 3
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

# 5. Логи
Write-Host "`n5. Recent Logs:" -ForegroundColor Yellow
$logPath = Join-Path $env:TEMP "mcp-powershell-server.log"
if (Test-Path $logPath) {
    Write-Host "Log file exists: $logPath"
    Get-Content $logPath -Tail 5
} else {
    Write-Host "No log file found at: $logPath"
}
```

## 📈 Мониторинг и метрики

### Базовые метрики

```powershell
# Скрипт для сбора метрик MCP сервера
function Get-MCPMetrics {
    $logPath = Join-Path $env:TEMP "mcp-powershell-server.log"
    
    if (-not (Test-Path $logPath)) {
        Write-Warning "Log file not found: $logPath"
        return
    }
    
    $logContent = Get-Content $logPath
    $today = Get-Date -Format "yyyy-MM-dd"
    
    # Фильтрация записей за сегодня
    $todayLogs = $logContent | Where-Object { $_ -match $today }
    
    # Подсчет по уровням
    $metrics = @{
        TotalRequests = ($todayLogs | Where-Object { $_ -match "Обработка MCP метода" }).Count
        Errors = ($todayLogs | Where-Object { $_ -match "\[ERROR\]" }).Count
        Warnings = ($todayLogs | Where-Object { $_ -match "\[WARNING\]" }).Count
        SuccessfulExecutions = ($todayLogs | Where-Object { $_ -match "успешно" }).Count
        Date = $today
    }
    
    return $metrics
}

# Использование
$metrics = Get-MCPMetrics
$metrics | Format-Table -AutoSize
```

### Мониторинг в реальном времени

```powershell
# Скрипт мониторинга логов в реальном времени
function Start-LogMonitoring {
    param([string]$LogPath = (Join-Path $env:TEMP "mcp-powershell-server.log"))
    
    Write-Host "Monitoring MCP server logs: $LogPath" -ForegroundColor Green
    Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
    
    Get-Content $LogPath -Wait | ForEach-Object {
        $color = "White"
        if ($_ -match "\[ERROR\]") { $color = "Red" }
        elseif ($_ -match "\[WARNING\]") { $color = "Yellow" }
        elseif ($_ -match "\[INFO\]") { $color = "Green" }
        elseif ($_ -match "\[DEBUG\]") { $color = "Gray" }
        
        Write-Host $_ -ForegroundColor $color
    }
}

# Запуск мониторинга
Start-LogMonitoring
```

## 🤝 Разработка и вклад в проект

### Структура проекта

```
mcp-powershell-server/
├── mcp-powershell-stdio.ps1     # Основной скрипт сервера
├── README.md                    # Документация
├── LICENSE                      # Лицензия
├── examples/                    # Примеры использования
│   ├── basic-usage.json        # Базовые примеры запросов
│   ├── advanced-scripts.ps1    # Продвинутые скрипты
│   └── client-configs/         # Конфигурации для разных клиентов
├── tests/                       # Тесты
│   ├── unit-tests.ps1          # Модульные тесты
│   ├── integration-tests.ps1   # Интеграционные тесты
│   └── performance-tests.ps1   # Тесты производительности
└── docs/                        # Дополнительная документация
    ├── API.md                  # Описание API
    ├── TROUBLESHOOTING.md      # Устранение неисправностей
    └── CHANGELOG.md            # История изменений
```

### Запуск тестов

```powershell
# Установка Pester (если не установлен)
Install-Module -Name Pester -Force -SkipPublisherCheck

# Запуск всех тестов
Invoke-Pester -Path ".\tests\" -Output Detailed

# Запуск конкретного теста
Invoke-Pester -Path ".\tests\unit-tests.ps1" -TestName "Test-MCPRequest"
```

### Создание pull request

1. Fork репозитория
2. Создайте feature branch: `git checkout -b feature/amazing-feature`
3. Внесите изменения и добавьте тесты
4. Запустите все тесты: `Invoke-Pester`
5. Commit изменения: `git commit -m 'Add amazing feature'`
6. Push в branch: `git push origin feature/amazing-feature`
7. Создайте Pull Request

## 📚 Дополнительные ресурсы

### Документация MCP
- [Model Context Protocol](https://modelcontextprotocol.io/) - Официальная документация
- [MCP Specification](https://spec.modelcontextprotocol.io/) - Спецификация протокола
- [MCP SDK](https://github.com/modelcontextprotocol/servers) - Официальные SDK и примеры

### PowerShell ресурсы
- [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/) - Официальная документация PowerShell
- [PowerShell Gallery](https://www.powershellgallery.com/) - Репозиторий модулей PowerShell
- [PowerShell Community](https://github.com/PowerShell/PowerShell) - GitHub сообщество

### Связанные проекты
- [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk) - Python реализация MCP
- [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk) - TypeScript реализация MCP

## 📄 Лицензия

Этот проект распространяется под лицензией MIT. См. файл [LICENSE](LICENSE) для подробностей.

## 👥 Авторы и участники

- **Основной разработчик** - @hypo69
- **Участники** - См. список [contributors](https://github.com/hypo69/mcp-powershell-server/contributors)

## 🙏 Благодарности

- Всем участникам проекта за вклад в развитие

---

## 📞 Поддержка

Если у вас возникли вопросы или проблемы:

1. **Проверьте FAQ** в разделе "Устранение неисправностей"
2. **Поищите в Issues** - возможно, ваша проблема уже решена
3. **Создайте новый Issue** с подробным описанием проблемы
4. **Обратитесь в Discussions** для общих вопросов

### Шаблон для сообщения о проблеме

```markdown
**Описание проблемы**
Краткое описание того, что происходит.

**Шаги для воспроизведения**
1. Выполните команду '...'
2. Отправьте запрос '...'
3. Увидьте ошибку

**Ожидаемое поведение**
Описание того, что должно было произойти.

**Фактическое поведение**
Описание того, что произошло на самом деле.

**Среда**
- ОС: [например, Windows 10]
- PowerShell версия: [например, 5.1]
- MCP Client: [например, Claude Desktop]

**Дополнительная информация**
Логи, скриншоты или другая полезная информация.
```

**Сделайте свой workflow с PowerShell еще более мощным с MCP PowerShell Server! 🚀**