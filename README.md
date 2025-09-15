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
- 🌐 **UTF-8 поддержка** - Корректная обработка Unicode символов
- ⚡ **Высокая производительность** - Минимальные накладные расходы
- 🌐 **HTTP/HTTPS сервер** - mcp-powershell-http с поддержкой Bearer-токена
- 🔐 **Авторизация** - Возможность ограничить доступ через токен
- 💻 **Локальные и удалённые вызовы** - MCP запросы через HTTP(S) POST

## 📋 Требования

### Системные требования
- **Windows** 10/11 или Windows Server 2016+
- **PowerShell** 5.1 или выше (включая PowerShell 7.x)
- **Права администратора** (опционально, для HTTPS сертификатов и системных команд)

### MCP Client
Любой MCP-совместимый клиент, поддерживающий:
- MCP Protocol версии 2024-11-05
- STDIO или HTTP(S) транспорт
- JSON-RPC 2.0

## 📦 Установка

### Быстрая установка STDIO сервера
1. **Скачайте скрипт**:

    ```powershell
       Invoke-WebRequest -Uri "https://raw.githubusercontent.com/hypo69/mcp-powershell-stdio.ps1" -OutFile "mcp-powershell-stdio.ps1"
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

### Быстрая установка HTTP(S) сервера

1. **Скачайте скрипт**:

   ```powershell
   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/hypo69/mcp-powershell-http.ps1" -OutFile "mcp-powershell-http.ps1"
   ```

2. **Настройте SSL сертификат** (для HTTPS):

   ```powershell
   # Создание self-signed сертификата (один раз)
   New-SelfSignedCertificate -DnsName "localhost" -CertStoreLocation "Cert:\LocalMachine\My"
   ```

3. **Привязка сертификата к порту**:

   ```powershell
   netsh http add sslcert ipport=0.0.0.0:8091 certhash=<Thumbprint> appid='{00000000-0000-0000-0000-000000000000}'
   ```

4. **Запуск сервера**:

   ```powershell
   powershell.exe -File .\mcp-powershell-http.ps1 -Port 8091 -ServerHost "localhost" -CertThumbprint "<Thumbprint>" -AuthToken "ваш_токен"
   ```

## 🔧 Конфигурация

### Переменные окружения

```powershell
$env:MCP_LOG_PATH = "C:\Logs\mcp-powershell.log"
$env:MCP_LOG_LEVEL = "INFO"
$env:MCP_MAX_LOG_SIZE = "50"
```

### Настройка для разных MCP клиентов

#### Claude Desktop

```json
{
  "mcpServers": {
    "powershell": {
      "command": "powershell.exe",
      "args": ["-File", "C:\\Path\\To\\mcp-powershell-http.ps1", "-Port", "8091", "-AuthToken", "token123"],
      "env": {
        "MCP_LOG_LEVEL": "INFO"
      }
    }
  }
}
```

#### VS Code Extension (Cline)

```json
{
  "mcp": {
    "powershell": {
      "command": "powershell.exe",
      "args": ["-File", "C:\\Path\\To\\mcp-powershell-http.ps1", "-Port", "8091", "-AuthToken", "token123"]
    }
  }
}
```

## 🛠️ Использование HTTP(S) сервера

### Пример запроса

```http
POST https://localhost:8091/
Authorization: Bearer token123
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "run-script",
    "arguments": {
      "script": "Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion",
      "timeoutSeconds": 30
    }
  }
}
```

**Ответ сервера:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Windows 10 Pro, Version 22H2"
      }
    ]
  }
}
```

### Особенности HTTP сервера

* Поддержка POST запросов с JSON-RPC 2.0
* Авторизация через Bearer токен
* Возможность работы через HTTPS с SSL сертификатом
* Настраиваемый порт и хост

---

Остальные разделы README остаются без изменений: **Базовые команды**, **Практические примеры**, **Командная строка**, **Расширенная конфигурация**, **Безопасность**, **Отладка и диагностика**, **Мониторинг и метрики**, **Разработка и вклад**, **Дополнительные ресурсы**, **Лицензия**, **Авторы**, **Поддержка**.

---

**Теперь README полностью описывает как `mcp-powershell-stdio`, так и `mcp-powershell-http` серверы.**

```

