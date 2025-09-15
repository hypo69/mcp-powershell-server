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

Вы можете управлять поведением сервера, установив следующие переменные окружения перед запуском.

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

### Linux (systemd) и macOS (launchd)

Инструкции по настройке служб для Linux и macOS доступны в [полной документации](docs/SERVICE_SETUP.md).

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

#### VS Code

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

---

## 🛠️ Примеры использования

### Примеры для режима STDIO

#### Пример 1: Тестовый запрос (Get-Date)
```powershell
$request = @{
    jsonrpc = "2.0"; id = 1; method = "tools/call"
    params = @{ name = "run-script"; arguments = @{ script = "Get-Date"; timeoutSeconds = 10 } }
} | ConvertTo-Json -Depth 5

$request | pwsh .\mcp-powershell-stdio.ps1
```

#### Пример 2: Системная информация
```powershell
$request = @{
    jsonrpc = "2.0"; id = 2; method = "tools/call"
    params = @{ name = "run-script"; arguments = @{ script = "Get-ComputerInfo | Select OsName, OsVersion, CsTotalPhysicalMemory" } }
} | ConvertTo-Json -Depth 5

$request | pwsh .\mcp-powershell-stdio.ps1
```

#### Пример 3: Работа с файлами
```powershell
$script = "Get-ChildItem -Path $env:USERPROFILE -File | Sort LastWriteTime -Desc | Select -First 10 Name, Length"
$request = @{
    jsonrpc = "2.0"; id = 3; method = "tools/call"
    params = @{ name = "run-script"; arguments = @{ script = $script; timeoutSeconds = 60 } }
} | ConvertTo-Json -Depth 5

$request | pwsh .\mcp-powershell-stdio.ps1
```

#### Пример 4: Скрипт с параметрами
```powershell
$script = "param($ProcessName, $Top = 5) Get-Process $ProcessName | Sort CPU -Desc | Select -First $Top Name, CPU"
$request = @{
    jsonrpc = "2.0"; id = 4; method = "tools/call"
    params = @{
        name = "run-script"
        arguments = @{ script = $script; parameters = @{ ProcessName = "pwsh"; Top = 3 } }
    }
} | ConvertTo-Json -Depth 5

$request | pwsh .\mcp-powershell-stdio.ps1
```

### Примеры клиентов для режима HTTP(S)

#### 🔹 PowerShell клиент (`Invoke-RestMethod`)
```powershell
$Url = "https://localhost:8443/execute"
$Token = "MySecretToken"
$Headers = @{ "Authorization" = "Bearer $Token"; "Content-Type"  = "application/json" }
$Payload = @{ command = "Get-Process pwsh | ConvertTo-Json" } | ConvertTo-Json

# Для PowerShell 7+ используйте -SkipCertificateCheck
$Response = Invoke-RestMethod -Uri $Url -Method Post -Headers $Headers -Body $Payload -SkipCertificateCheck
$Response | ConvertTo-Json -Depth 5
```

#### cURL
```bash
curl --insecure -X POST "https://localhost:8443/execute" \
  -H "Authorization: Bearer MySecretToken" \
  -H "Content-Type: application/json" \
  -d '{"command": "Get-Process | Sort-Object CPU -Descending | Select-Object -First 3 Name, CPU | ConvertTo-Json"}'
```

#### 🟢 Node.js клиент
```javascript
import fetch from "node-fetch";
import https from "https-proxy-agent";

const agent = new https.Agent({ rejectUnauthorized: false });
const url = "https://localhost:8443/execute";
const headers = { "Authorization": "Bearer MySecretToken", "Content-Type": "application/json" };
const payload = { command: "Get-Service -Name Spooler | ConvertTo-Json" };

fetch(url, { method: "POST", headers, body: JSON.stringify(payload), agent })
  .then(res => res.json())
  .then(json => console.log(json))
  .catch(err => console.error(err));
```

#### 🐍 Python клиент
```python
import requests, json, urllib3

urllib3.disable_warnings()
url = "https://localhost:8443/execute"
headers = {"Authorization": "Bearer MySecretToken", "Content-Type": "application/json"}
payload = {"command": "Get-Process pwsh | Select Name, CPU | ConvertTo-Json"}

response = requests.post(url, headers=headers, data=json.dumps(payload), verify=False)
print(response.json())
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

---

## 📜 Лицензия

MIT © [hypo69](https://github.com/hypo69/mcp-powershell-server)

---

## 👥 Авторы

*   **Основной разработчик**: @hypo69
*   Смотрите также список [участников](https://github.com/hypo69/mcp-powershell-server/contributors), которые внесли свой вклад в этот проект.