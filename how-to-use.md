Конечно, вот полный текст обновленного файла `how-to-use.md` с добавленным разделом, объясняющим выбор режима работы.

---

# Подробное руководство по использованию MCP PowerShell Server

## Оглавление

1.  [Установка и настройка](#установка-и-настройка)
2.  [Выбор режима работы: HTTP vs. STDIO](#выбор-режима-работы-http-vs-stdio)
3.  [STDIO режим](#stdio-режим)
4.  [HTTP режим](#http-режим)
5.  [Интеграция с Gemini CLI](#интеграция-с-gemini-cli)
6.  [Примеры использования](#примеры-использования)
7.  [Конфигурация](#конфигурация)
8.  [Безопасность](#безопасность)
9.  [Расширение функциональности](#расширение-функциональности)
10. [Устранение неполадок](#устранение-неполадок)
11. [API Reference](#api-reference)

## Установка и настройка

### Предварительные требования

1.  **PowerShell 7.0+**
    ```powershell
    # Проверка версии PowerShell
    $PSVersionTable.PSVersion

    # Установка PowerShell 7 (если необходимо)
    # Скачайте с https://github.com/PowerShell/PowerShell
    ```

2.  **Права доступа**
    *   Для портов < 1024 требуются права администратора
    *   Права на выполнение PowerShell скриптов

3.  **Настройка политики выполнения**
    ```powershell
    # Проверка текущей политики
    Get-ExecutionPolicy

    # Установка политики для разрешения выполнения скриптов
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    ```

### Первоначальная настройка

1.  **Навигация к директории серверов**
    ```powershell
    # Переход в корень модуля
    cd C:\powershell\modules\mcp-powershell-server

    # Переход к серверам
    cd src\servers
    ```

2.  **Проверка файлов**
    ```powershell
    # Убедитесь, что все необходимые файлы присутствуют
    Get-ChildItem *.ps1 | Select-Object Name
    ```

## Выбор режима работы: HTTP vs. STDIO

Перед тем как погружаться в детали, важно понять, какой из двух режимов работы сервера вам подходит. Выбор зависит от того, **как и откуда** вы планируете отправлять команды.

*   **HTTP режим (`mcp-powershell-http.ps1`)**: Работает как **веб-сервис**. Он принимает команды по сети (HTTP) и может быть доступен с других компьютеров или из веб-приложений. Это универсальный способ для сетевых интеграций.

*   **STDIO режим (`mcp-powershell-stdio.ps1`)**: Работает как **консольное приложение**, управляемое другим процессом. Он получает команды через стандартный поток ввода (Standard Input) и отдает результат через стандартный поток вывода (Standard Output). Этот способ идеален для локальной интеграции, например, с `gemini-cli`.

### Когда использовать HTTP режим?

Выбирайте HTTP, если вам требуется **сетевая доступность**:

*   **Удаленное управление:** Клиентское приложение (например, скрипт на Python) находится на **другом компьютере**.
*   **Веб-интеграция:** Вы хотите вызывать PowerShell из веб-панели, отправляя запросы с помощью JavaScript.
*   **Микросервисная архитектура:** Разные сервисы в вашей сети должны обмениваться командами.
*   **Простое тестирование:** Вы хотите отправлять команды с помощью инструментов вроде `curl` или Postman.

> **Ключевой сценарий:** Клиент и сервер находятся в сети и общаются по стандартным веб-протоколам.

### Когда использовать STDIO режим?

Выбирайте STDIO для **локальной и более безопасной интеграции**:

*   **Интеграция с Gemini CLI:** Это **основной** и самый частый сценарий. `gemini-cli` сам запускает `mcp-powershell-stdio.ps1` как дочерний процесс и общается с ним напрямую.
*   **Локальные скрипты-обертки:** Ваше приложение на другом языке (например, Node.js) запускает сервер PowerShell как дочерний процесс и управляет им.
*   **Повышенная безопасность:** Этот режим не открывает сетевые порты, что исключает целый класс сетевых угроз.

> **Ключевой сценарий:** Клиент и сервер работают на **одной машине**, и клиент сам управляет жизненным циклом сервера.

Теперь, когда вы определились с режимом, переходите к соответствующему разделу ниже для получения подробных инструкций по запуску и использованию.

## STDIO режим

STDIO режим предназначен для интеграции с MCP-клиентами, такими как `gemini-cli`.

### Запуск STDIO сервера

```powershell
# Прямой запуск сервера (из папки src/servers)
.\mcp-powershell-stdio.ps1

# Или из корня проекта
.\src\servers\mcp-powershell-stdio.ps1
```

### Особенности STDIO режима

-   **Протокол**: JSON-RPC через стандартные потоки ввода-вывода
-   **Логирование**: В файл `%TEMP%\mcp-powershell-server.log`
-   **Кодировка**: UTF-8 для корректной работы с русскими символами
-   **Совместимость**: Работает с любыми MCP-клиентами

### Тестирование STDIO режима

```powershell
# Запуск тестового сервера для проверки (из папки src/servers)
.\test-mcp.ps1

# Или из корня проекта
.\src\servers\test-mcp.ps1
```

Пример ручного тестирования:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"run-script","arguments":{"script":"Get-Date"}}}
```

## HTTP режим

HTTP режим предназначен для веб-интеграций и REST API.

### Запуск HTTP сервера

```powershell
# Базовый запуск (localhost:8090) из папки src/servers
.\mcp-powershell-http.ps1

# Запуск на другом порту
.\mcp-powershell-http.ps1 -Port 9090

# Запуск на всех интерфейсах
.\mcp-powershell-http.ps1 -ServerHost "0.0.0.0" -Port 8080

# Запуск с конфигурационным файлом
.\mcp-powershell-http.ps1 -ConfigFile "config.json"

# Или из корня проекта
.\src\servers\mcp-powershell-http.ps1 -Port 8090
```

### HTTP API эндпоинты

Все запросы отправляются как POST на корневой URL сервера.

**URL**: `http://localhost:8090/`
**Method**: `POST`
**Content-Type**: `application/json`

### Тестирование HTTP режима

```powershell
# Тест с помощью Invoke-RestMethod
$body = @{
    jsonrpc = "2.0"
    id = 1
    method = "tools/list"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8090/" -Method POST -Body $body -ContentType "application/json"
```

```bash
# Тест с помощью curl
curl -X POST http://localhost:8090/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

## Интеграция с Gemini CLI

### Автоматическая настройка

```powershell
# Запуск с автоматической настройкой Gemini CLI
.\start-mcp-with-gemini.ps1 -ApiKey "your-gemini-api-key"

# С дополнительными параметрами
.\start-mcp-with-gemini.ps1 -ApiKey "your-key" -ServerPort 9090 -Wait 15
```

### Ручная настройка

1.  **Создание конфигурации MCP**
    ```powershell
    # Создание директории конфигурации
    $configDir = "$env:USERPROFILE\.config\gemini"
    New-Item -Path $configDir -ItemType Directory -Force

    # Создание файла конфигурации MCP
    $config = @{
        mcpServers = @{
            powershell = @{
                command = "pwsh"
                args = @("-File", "C:\path\to\mcp-powershell-stdio.ps1")
                env = @{}
            }
        }
    } | ConvertTo-Json -Depth 5

    $config | Set-Content "$configDir\mcp_servers.json" -Encoding UTF8
    ```

2.  **Использование с gemini-cli**
    ```bash
    # Интерактивный режим
    gemini --mcp-config "path/to/mcp_servers.json" -i

    # Одиночный запрос
    gemini --mcp-config "path/to/mcp_servers.json" -m gemini-2.5-pro -p "Выполни команду Get-Process | Select-Object -First 5"
    ```

## Примеры использования

### Базовые команды PowerShell

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "run-script",
    "arguments": {
      "script": "Get-ComputerInfo | Select-Object WindowsProductName, TotalPhysicalMemory"
    }
  }
}
```

### Работа с файлами

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "run-script",
    "arguments": {
      "script": "Get-ChildItem C:\\ -Directory | Select-Object Name, CreationTime | Format-Table",
      "workingDirectory": "C:\\",
      "timeoutSeconds": 30
    }
  }
}
```

### Скрипты с параметрами

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "run-script",
    "arguments": {
      "script": "param($ProcessName) Get-Process -Name $ProcessName -ErrorAction SilentlyContinue",
      "parameters": {
        "ProcessName": "notepad"
      }
    }
  }
}
```

### Системный мониторинг

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "run-script",
    "arguments": {
      "script": "$cpu = Get-Counter '\\Processor(_Total)\\% Processor Time' | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue; $memory = Get-Counter '\\Memory\\Available MBytes' | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue; Write-Output \"CPU: $([math]::Round($cpu, 2))%, Available Memory: $memory MB\""
    }
  }
}
```

## Конфигурация

### Файл config.json

```json
{
  "Port": 8090,
  "Host": "localhost",
  "MaxConcurrentRequests": 10,
  "TimeoutSeconds": 300,
  "LogLevel": "INFO",
  "AllowedPaths": [
    "C:\\Scripts\\",
    "C:\\Tools\\",
    "C:\\Temp\\"
  ],
  "Security": {
    "EnableScriptValidation": true,
    "BlockDangerousCommands": true,
    "RestrictedCommands": [
      "Remove-Item",
      "Format-Volume",
      "Stop-Computer",
      "Restart-Computer",
      "New-ItemProperty -Path 'HKLM:*'",
      "Remove-ItemProperty -Path 'HKLM:*'"
    ],
    "AllowedModules": [
      "Microsoft.PowerShell.*",
      "PackageManagement",
      "PowerShellGet"
    ]
  },
  "Logging": {
    "LogFile": "%TEMP%\\mcp-powershell-server.log",
    "MaxLogSize": "10MB",
    "LogRotation": true
  }
}
```

### Переменные окружения

```powershell
# Настройка через переменные окружения
$env:MCP_PS_PORT = "8090"
$env:MCP_PS_HOST = "localhost"
$env:MCP_PS_TIMEOUT = "300"
$env:MCP_PS_LOG_LEVEL = "INFO"
```

## Безопасность

### Рекомендации по безопасности

1.  **Ограничение команд**
    ```json
    "RestrictedCommands": [
      "Remove-Item",
      "Format-Volume",
      "Stop-Computer",
      "Restart-Computer",
      "Invoke-Expression",
      "iex",
      "& *"
    ]
    ```

2.  **Ограничение путей**
    ```json
    "AllowedPaths": [
      "C:\\Scripts\\",
      "C:\\Tools\\",
      "C:\\Temp\\"
    ]
    ```

3.  **Сетевые ограничения**
    ```powershell
    # Ограничение доступа только локальному хосту
    .\start-mcp-server.ps1 -ServerHost "127.0.0.1"
    ```

4.  **Тайм-ауты**
    ```json
    "TimeoutSeconds": 60  // Ограничение времени выполнения
    ```

### Аудит и мониторинг

```powershell
# Мониторинг логов в реальном времени
Get-Content "$env:TEMP\mcp-powershell-server.log" -Wait -Tail 10

# Анализ выполненных команд
Select-String -Path "$env:TEMP\mcp-powershell-server.log" -Pattern "Выполнение PowerShell скрипта"
```

## Расширение функциональности

### Добавление новых MCP инструментов

1.  **Структура инструмента**
    ```powershell
    # В функции Invoke-MCPMethod добавьте новый case
    "my-custom-tool" {
        # Валидация параметров
        if (-not $arguments.ContainsKey("required_param")) {
            return New-MCPResponse -Id $Id -Error @{
                code = -32602
                message = "Missing required parameter 'required_param'"
            }
        }

        # Логика выполнения
        $result = Invoke-MyCustomFunction -Param $arguments.required_param

        # Возврат результата
        return New-MCPResponse -Id $Id -Result @{
            content = @(
                @{
                    type = "text"
                    text = "Result: $result"
                }
            )
        }
    }
    ```

2.  **Регистрация в tools/list**
    ```powershell
    # Добавьте описание инструмента в метод tools/list
    @{
        name = "my-custom-tool"
        description = "Описание моего инструмента"
        inputSchema = @{
            type = "object"
            properties = @{
                required_param = @{
                    type = "string"
                    description = "Обязательный параметр"
                }
            }
            required = @("required_param")
        }
    }
    ```

### Пример кастомного инструмента

```powershell
# Добавление инструмента для работы с реестром
"registry-query" {
    if (-not $arguments.ContainsKey("path")) {
        return New-MCPResponse -Id $Id -Error @{
            code = -32602
            message = "Missing required parameter 'path'"
        }
    }

    try {
        $regPath = $arguments.path
        $regKey = Get-ItemProperty -Path $regPath -ErrorAction Stop
        $result = $regKey | Format-List | Out-String

        return New-MCPResponse -Id $Id -Result @{
            content = @(
                @{
                    type = "text"
                    text = "Registry values at ${regPath}:`n$result"
                }
            )
        }
    }
    catch {
        return New-MCPResponse -Id $Id -Error @{
            code = -32603
            message = "Registry query failed: $($_.Exception.Message)"
        }
    }
}```

## Устранение неполадок

### Диагностические команды

```powershell
# Проверка версии PowerShell
$PSVersionTable.PSVersion

# Проверка доступности порта
Test-NetConnection -ComputerName localhost -Port 8090

# Проверка логов
Get-Content "$env:TEMP\mcp-powershell-server.log" -Tail 50

# Проверка процессов PowerShell
Get-Process -Name pwsh*
```

### Частые проблемы

1.  **"Порт уже используется"**
    ```powershell
    # Найти процесс, использующий порт
    Get-NetTCPConnection -LocalPort 8090 | Get-Process

    # Или использовать другой порт
    .\start-mcp-server.ps1 -Port 9090
    ```

2.  **"Доступ запрещен"**
    ```powershell
    # Запуск с правами администратора для портов < 1024
    Start-Process pwsh -Verb RunAs -ArgumentList "-File", "start-mcp-server.ps1"
    ```

3.  **"Проблемы с кодировкой"**
    ```powershell
    # Проверка кодировки консоли
    [Console]::OutputEncoding
    [Console]::InputEncoding

    # Принудительная установка UTF-8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    ```

4.  **"Скрипт не выполняется"**
    ```powershell
    # Проверка политики выполнения
    Get-ExecutionPolicy -List

    # Временное разрешение
    powershell.exe -ExecutionPolicy Bypass -File "script.ps1"
    ```

### Отладка

```powershell
# Включение детального логирования
$DebugPreference = "Continue"

# Трассировка выполнения скриптов
Set-PSDebug -Trace 1

# Выключение трассировки
Set-PSDebug -Off
```

## API Reference

### MCP Methods

#### initialize

Инициализация MCP сервера.

**Request:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05"
  }
}
```

**Response:**

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

#### tools/list

Получение списка доступных инструментов.

**Request:**

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list"
}
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "run-script",
        "description": "Выполняет PowerShell скрипт с заданными параметрами",
        "inputSchema": {
          "type": "object",
          "properties": {
            "script": {
              "type": "string",
              "description": "PowerShell код для выполнения"
            },
            "parameters": {
              "type": "object",
              "description": "Параметры для скрипта (опционально)"
            },
            "workingDirectory": {
              "type": "string",
              "description": "Рабочая директория для выполнения"
            },
            "timeoutSeconds": {
              "type": "integer",
              "description": "Тайм-аут выполнения в секундах",
              "default": 300,
              "minimum": 1,
              "maximum": 3600
            }
          },
          "required": ["script"]
        }
      }
    ]
  }
}```

#### tools/call

Выполнение инструмента.

**Request:**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "run-script",
    "arguments": {
      "script": "Get-Date",
      "timeoutSeconds": 30
    }
  }
}```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Вывод команды:\n```\nВторник, 25 сентября 2025 г. 14:30:45\n```"
      }
    ],
    "isError": false,
    "_meta": {
      "executionTime": "2025-09-25 14:30:45",
      "success": true,
      "errorCount": 0,
      "warningCount": 0
    }
  }
}
```

### Error Codes

| Код    | Описание                             |
| :----- | :----------------------------------- |
| -32700 | Parse error - Ошибка парсинга JSON   |
| -32600 | Invalid Request - Неверный запрос    |
| -32601 | Method not found - Метод не найден   |
| -32602 | Invalid params - Неверные параметры  |
| -32603 | Internal error - Внутренняя ошибка сервера |

### Logging Levels

| Уровень | Описание                               |
| :------ | :------------------------------------- |
| DEBUG   | Подробная отладочная информация        |
| INFO    | Общая информация о работе              |
| WARNING | Предупреждения о потенциальных проблемах |
| ERROR   | Ошибки, требующие внимания             |

## Заключение

MCP PowerShell Server предоставляет мощный и безопасный способ интеграции PowerShell с ИИ-ассистентами и другими приложениями через стандартизированный протокол MCP. Следуйте рекомендациям по безопасности и используйте логирование для мониторинга работы сервера.