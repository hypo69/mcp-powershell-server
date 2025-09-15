
# MCP PowerShell Server

[![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![MCP Protocol](https://img.shields.io/badge/MCP-2024--11--05-green.svg)](https://modelcontextprotocol.io/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**MCP PowerShell Server** — это реализация сервера Model Context Protocol (MCP) для безопасного выполнения PowerShell скриптов. Сервер предоставляет стандартизированный интерфейс для выполнения PowerShell команд через MCP протокол с поддержкой изоляции процессов, таймаутов и детального логирования.

---

## 🚀 Возможности

*   ✅ **MCP Protocol 2024-11-05** — Полная совместимость с последней версией протокола.
*   🔒 **Безопасное выполнение** — Изоляция каждого скрипта через отдельные PowerShell процессы.
*   ⏱️ **Контроль времени выполнения** — Настраиваемые таймауты (1–3600 секунд).
*   📁 **Гибкая рабочая среда** — Возможность указания рабочей директории.
*   📊 **Детальное логирование** — Полная трассировка выполнения с разными уровнями.
*   🔄 **Два режима работы** — Поддержка **STDIO** для локальной интеграции и **HTTP(S)** для сетевого доступа.
*   🌐 **UTF-8 поддержка** — Корректная обработка Unicode символов.
*   ⚡ **Высокая производительность** — Минимальные накладные расходы.

---

## 🔄 Схема работы MCP PowerShell Server

```
           +-------------------+
           | MCP Клиент        |
           | (например IDE)    |
           +---------+---------+
                     |
           JSON-RPC через STDIO/HTTP(S)
                     |
           +---------v---------+
           | MCP Server        |
           | PowerShell Bridge |
           +---------+---------+
                     |
             Запуск скрипта
                     |
           +---------v---------+
           | PowerShell Engine |
           | (отдельный proc)  |
           +---------+---------+
                     |
                Результат/Логи
                     |
           +---------v---------+
           | MCP Клиент        |
           +-------------------+
```

---

## 📋 Требования

### Системные требования

*   **Windows, Linux или macOS** с установленным PowerShell 7+.
*   **Права администратора/root** (для установки службы и выполнения системных команд).

### MCP Client

*   Любой MCP-совместимый клиент, поддерживающий STDIO или HTTP(S) транспорт и JSON-RPC 2.0.

---

## 📦 Установка и запуск

### Шаг 1: Скачайте скрипты

Выберите один из двух методов.

#### Метод А: Клонирование репозитория (рекомендуется)
Этот способ скачает все файлы проекта, включая оба скрипта и будущие обновления.
```powershell
git clone https://github.com/hypo69/mcp-powershell-server.git
cd mcp-powershell-server
```

#### Метод Б: Прямое скачивание (для отдельных файлов)
```powershell
# Скрипт для локальной интеграции (STDIO)
$uriStdio = "https://raw.githubusercontent.com/hypo69/mcp-powershell-server/main/mcp-powershell-stdio.ps1"
Invoke-WebRequest -Uri $uriStdio -OutFile "mcp-powershell-stdio.ps1"

# Скрипт для сетевого сервера (HTTP/S)
$uriHttp = "https://raw.githubusercontent.com/hypo69/mcp-powershell-server/main/mcp-powershell-http.ps1"
Invoke-WebRequest -Uri $uriHttp -OutFile "mcp-powershell-http.ps1"
```

### Шаг 2: Настройте среду выполнения (только для Windows)

```powershell
# Если команда Get-ExecutionPolicy вернет 'Restricted', измените ее:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Шаг 3: Выберите режим и запустите сервер

#### Режим 1: STDIO (локальное использование)
Идеально для интеграции с локальными IDE.
```powershell
# Тестовый запуск
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | pwsh .\mcp-powershell-stdio.ps1
```

#### Режим 2: HTTP(S) (сетевое использование)
Идеально для создания постоянно работающего сервиса.
```powershell
# Запуск HTTP сервера
pwsh -File .\mcp-powershell-http.ps1 -Port 8091 -AuthToken "supersecrettoken"

# Запуск HTTPS сервера (требуется отпечаток сертификата)
# pwsh -File .\mcp-powershell-http.ps1 -Port 8443 -AuthToken "supersecrettoken" -CertThumbprint "A1B2C3D4..."
```

---

## 🔧 Конфигурация

### Переменные окружения

Вы можете управлять поведением сервера, установив следующие переменные окружения перед запуском скрипта.

```powershell
# Путь для лог-файла (по умолчанию: %TEMP%\mcp-powershell-server.log)
$env:MCP_LOG_PATH = "C:\Logs\mcp-powershell.log"

# Уровень логирования (DEBUG, INFO, WARNING, ERROR)
$env:MCP_LOG_LEVEL = "INFO"

# Максимальный размер лога в МБ (по умолчанию: 10)
$env:MCP_MAX_LOG_SIZE = "50"
```

### 🔐 Настройка HTTPS: Как получить отпечаток сертификата (Thumbprint) в Windows

1.  **Создайте самоподписанный сертификат (для тестов)**. Откройте PowerShell **от имени администратора**:
    ```powershell
    New-SelfSignedCertificate -DnsName "localhost" -CertStoreLocation "Cert:\CurrentUser\My"
    ```
    В выводе команды вы сразу увидите `Thumbprint`.

2.  **Скопируйте отпечаток**. Эта команда найдет сертификат и скопирует его отпечаток в буфер обмена:
    ```powershell
    Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.DnsNameList -contains "localhost" } | Select -First 1 -ExpandProperty Thumbprint | Set-Clipboard
    ```

---

## 🚀 Запуск в качестве службы (автозагрузка при старте ОС)

Для надежной работы рекомендуется запускать `mcp-powershell-http.ps1` как службу.

### Windows (с помощью NSSM)

1.  **Скачайте [NSSM](https://nssm.cc/download)** и скопируйте `nssm.exe` в `C:\Windows\System32`.
2.  **Установите службу** (в PowerShell от имени администратора):
    ```powershell
    nssm install MCP-PowerShell-Server
    ```
3.  В открывшемся GUI укажите:
    *   **Path**: `C:\Program Files\PowerShell\7\pwsh.exe`
    *   **Startup directory**: `C:\Scripts\mcp-server` (где лежит ваш скрипт)
    *   **Arguments**: `-NoProfile -File "C:\Scripts\mcp-server\mcp-powershell-http.ps1" -Port 8443 -AuthToken "MySecretToken"`
4.  **Запустите и включите автозагрузку**:
    ```powershell
    Start-Service MCP-PowerShell-Server
    Set-Service -Name MCP-PowerShell-Server -StartupType Automatic
    ```

### Linux (systemd)

1.  **Создайте файл службы**: `sudo nano /etc/systemd/system/mcp-server.service`
2.  **Вставьте конфигурацию**:
    ```ini
    [Unit]
    Description=MCP PowerShell HTTP Server
    After=network.target

    [Service]
    ExecStart=/usr/bin/pwsh -NoProfile -File /opt/mcp-server/mcp-powershell-http.ps1 -Port 8443 -AuthToken "MySecretToken"
    WorkingDirectory=/opt/mcp-server
    User=www-data
    Restart=always

    [Install]
    WantedBy=multi-user.target
    ```
3.  **Включите и запустите**:
    ```bash
    sudo systemctl daemon-reload
    sudo systemctl enable --now mcp-server.service
    sudo systemctl status mcp-server.service
    ```

### macOS (launchd)

1.  **Создайте файл конфигурации**: `sudo nano /Library/LaunchDaemons/com.example.mcpserver.plist`
2.  **Вставьте конфигурацию**:
    ```xml
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.example.mcpserver</string>
        <key>ProgramArguments</key>
        <array>
            <string>/usr/local/bin/pwsh</string>
            <string>-NoProfile</string>
            <string>-File</string>
            <string>/opt/mcp-server/mcp-powershell-http.ps1</string>
            <string>-Port</string>
            <string>8443</string>
            <string>-AuthToken</string>
            <string>MySecretToken</string>
        </array>
        <key>RunAtLoad</key><true/>
        <key>KeepAlive</key><true/>
    </dict>
    </plist>
    ```
3.  **Загрузите службу**:
    ```bash
    sudo launchctl load /Library/LaunchDaemons/com.example.mcpserver.plist
    ```

---

## 🔧 Конфигурация клиентов (для STDIO)

#### Claude Desktop

```json
{
  "mcpServers": {
    "powershell": {
      "command": "pwsh",
      "args": ["-NoProfile", "-File", "C:\\Path\\To\\mcp-powershell-stdio.ps1"],
      "env": { "MCP_LOG_LEVEL": "INFO" }
    }
  }
}
```

#### VS Code (с расширением Cline)

```json
{
  "mcp": {
    "powershell": {
      "command": "pwsh",
      "args": ["-NoProfile", "-File", "C:\\Path\\To\\mcp-powershell-stdio.ps1"]
    }
  }
}
```

---

## 📑 Таблица методов MCP

| Метод MCP | Описание | Параметры |
| :--- | :--- | :--- |
| `initialize` | Инициализация сервера MCP | `{}` |
| `tools/call` | Выполнение PowerShell скрипта | `{ name, arguments }` |
| `tools/list` | Получение списка инструментов | `{}` |
| `tools/status` | Получение статуса сервера | `{}` |
| `tools/logs` | Получение последних логов | `{ count }` |

---

## 🛠️ Примеры использования

### Примеры для режима STDIO (MCP протокол)

```powershell
# 1️⃣ Инициализация соединения
@'
{
  "jsonrpc": "2.0", "id": 1, "method": "initialize",
  "params": { "protocolVersion": "2024-11-05" }
}
'@ | pwsh .\mcp-powershell-stdio.ps1

# 2️⃣ Выполнение скрипта с параметрами
$script = "param($ProcName) Get-Process -Name $ProcName"
$request = @{
    jsonrpc = "2.0"; id = 2; method = "tools/call"
    params = @{
        name = "run-script"
        arguments = @{
            script = $script
            parameters = @{ ProcName = "pwsh" }
        }
    }
} | ConvertTo-Json -Depth 5

$request | pwsh .\mcp-powershell-stdio.ps1
```

### Примеры клиентов на разных языках (HTTP/S)

#### 🟢 Node.js клиент

```javascript
import fetch from "node-fetch";
import https from "https";

// Агент для отключения проверки самоподписанных сертификатов
const httpsAgent = new https.Agent({ rejectUnauthorized: false });
const url = "https://localhost:8443/execute";
const headers = {
  "Authorization": "Bearer MySecretToken",
  "Content-Type": "application/json"
};
const payload = {
  command: "Get-Service | Where-Object Status -eq 'Running' | Select-Object -First 5 | ConvertTo-Json"
};

(async () => {
  try {
    const response = await fetch(url, {
      method: "POST", headers, body: JSON.stringify(payload), agent: httpsAgent
    });
    console.log(await response.json());
  } catch (err) { console.error(err); }
})();
```

#### 🐍 Python клиент

```python
import requests
import json
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
url = "https://localhost:8443/execute"
headers = {"Authorization": "Bearer MySecretToken", "Content-Type": "application/json"}
payload = {"command": "Get-Process | Sort-Object CPU -Desc | Select -First 3 Name, CPU | ConvertTo-Json"}

response = requests.post(url, headers=headers, data=json.dumps(payload), verify=False)
print(response.json())
```

#### 🔹 PowerShell клиент (`Invoke-RestMethod`)

```powershell
$Url = "https://localhost:8443/execute"
$Token = "MySecretToken"
$Headers = @{ "Authorization" = "Bearer $Token"; "Content-Type"  = "application/json" }
$Payload = @{ command = "Get-Process pwsh | ConvertTo-Json" } | ConvertTo-Json

$Response = Invoke-RestMethod -Uri $Url -Method Post -Headers $Headers -Body $Payload -SkipCertificateCheck
$Response | ConvertTo-Json -Depth 5
```

---

## 🛡️ Безопасность

*   **Изоляция процессов**: Каждый скрипт выполняется в отдельном, временном процессе.
*   **Логирование действий**: Полная трассировка для аудита безопасности.
*   **Рекомендации**: Запускайте под ограниченной учетной записью, используйте Firewall и HTTPS с надежным сертификатом в продакшене.

---

## 🔍 Отладка и мониторинг

```powershell
# Включить подробное логирование
$env:MCP_LOG_LEVEL = "DEBUG"

# Посмотреть последние 20 строк лога
$logPath = $env:MCP_LOG_PATH -or (Join-Path $env:TEMP "mcp-powershell-server.log")
Get-Content $logPath -Tail 20

# Отслеживать логи в реальном времени
Get-Content $logPath -Wait
```

### Сбор метрик

```powershell
function Get-MCPMetrics {
    $logPath = $env:MCP_LOG_PATH -or (Join-Path $env:TEMP "mcp-powershell-server.log")
    if (-not (Test-Path $logPath)) { return }
    $logContent = Get-Content $logPath
    $todayLogs = $logContent | Where-Object { $_ -match (Get-Date -Format "yyyy-MM-dd") }
    return @{
        TotalRequests = ($todayLogs | Where-Object { $_ -match "Обработка MCP" }).Count
        Errors = ($todayLogs | Where-Object { $_ -match "\[ERROR\]" }).Count
    }
}
Get-MCPMetrics
```

---

## 📚 Дополнительные ресурсы

*   [Официальный сайт Model Context Protocol](https://modelcontextprotocol.io/)
*   [Спецификация MCP](https://spec.modelcontextprotocol.io/)
*   [Документация PowerShell](https://docs.microsoft.com/powershell/)

---

## 📜 Лицензия

MIT © [hypo69](https://github.com/hypo69/mcp-powershell-server)

---

## 👥 Авторы

*   **Основной разработчик**: @hypo69
*   Смотрите также список [участников](https://github.com/hypo69/mcp-powershell-server/contributors), которые внесли свой вклад в этот проект.