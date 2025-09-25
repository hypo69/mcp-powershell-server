# MCP PowerShell Server

Сервер MCP (Model Context Protocol) для выполнения PowerShell скриптов, поддерживающий как HTTP, так и STDIO режимы работы.

## Описание

MCP PowerShell Server позволяет ИИ-ассистентам выполнять PowerShell команды и скрипты через стандартизированный протокол MCP. Сервер поддерживает два режима работы:

- **STDIO режим**: Для интеграции с gemini-cli и другими MCP-клиентами
- **HTTP режим**: Для веб-приложений и REST API интеграции

## Особенности

- ✅ Поддержка MCP протокола версии 2024-11-05
- ✅ Два режима работы: STDIO и HTTP
- ✅ Изоляция выполнения скриптов в отдельных PowerShell процессах
- ✅ Настраиваемые тайм-ауты выполнения
- ✅ Детальное логирование всех операций
- ✅ Обработка ошибок и предупреждений PowerShell
- ✅ Поддержка параметров скриптов
- ✅ Настраиваемая рабочая директория
- ✅ Автоматические launcher'ы для упрощения запуска

## Системные требования

- PowerShell 7.0 или новее
- Windows 10/11 или Windows Server 2019+
- .NET 6.0 или новее

## Структура проекта

## Структура проекта

```
mcp-powershell-server/
├── src/
│   ├── clients/           # Клиентские приложения
│   │   ├── node/         # Node.js клиент
│   │   ├── powershell/   # PowerShell клиент  
│   │   └── python/       # Python клиент
│   └── servers/          # Серверные компоненты
│       ├── mcp-powershell-stdio.ps1   # STDIO версия сервера
│       ├── mcp-powershell-http.ps1    # HTTP версия сервера  
│       ├── test-mcp.ps1               # Тестовый сервер
│       └── config.json                # Файл конфигурации
├── docs/                 # Документация
├── README.md            # Этот файл
└── how-to-use.md        # Подробное руководство
```

## Быстрый старт

### STDIO режим (для gemini-cli)

1. **Запуск сервера:**
   ```powershell
   .\src\servers\mcp-powershell-stdio.ps1
   ```

2. **Тестирование:**
   ```powershell
   .\src\servers\test-mcp.ps1
   ```

### HTTP режим

1. **Базовый запуск:**
   ```powershell
   .\src\servers\mcp-powershell-http.ps1
   ```

2. **С настраиваемыми параметрами:**
   ```powershell
   .\src\servers\mcp-powershell-http.ps1 -Port 9090 -ServerHost "0.0.0.0"
   ```

3. **С файлом конфигурации:**
   ```powershell
   .\src\servers\mcp-powershell-http.ps1 -ConfigFile ".\src\servers\config.json"
   ```

## Доступные MCP инструменты

### `run-script`
Выполняет PowerShell скрипт с заданными параметрами.

**Параметры:**
- `script` (обязательный) - PowerShell код для выполнения
- `parameters` (опциональный) - Хеш-таблица параметров
- `workingDirectory` (опциональный) - Рабочая директория
- `timeoutSeconds` (опциональный) - Тайм-аут выполнения (1-3600 сек)

**Пример использования через MCP:**
```json
{
  "name": "run-script",
  "arguments": {
    "script": "Get-Process | Select-Object -First 5 | Format-Table",
    "workingDirectory": "C:\\",
    "timeoutSeconds": 30
  }
}
```

## Конфигурация

Сервер поддерживает конфигурацию через файл `config.json`:

```json
{
  "Port": 8090,
  "Host": "localhost", 
  "MaxConcurrentRequests": 10,
  "TimeoutSeconds": 300,
  "AllowedPaths": [
    "C:\\Scripts\\",
    "C:\\Tools\\"
  ],
  "Security": {
    "EnableScriptValidation": true,
    "BlockDangerousCommands": true,
    "RestrictedCommands": [
      "Remove-Item",
      "Format-Volume", 
      "Stop-Computer",
      "Restart-Computer"
    ]
  }
}
```

## Безопасность

- Выполнение скриптов происходит в изолированных PowerShell процессах
- Поддержка списка запрещенных команд
- Ограничение по времени выполнения
- Логирование всех выполняемых команд
- Возможность ограничения доступных путей

## Логирование

- **STDIO режим**: Логи записываются в `%TEMP%\mcp-powershell-server.log`
- **HTTP режим**: Логи выводятся в консоль с цветовой индикацией

Уровни логирования: DEBUG, INFO, WARNING, ERROR

## Интеграция с ИИ-ассистентами

### Gemini CLI
```bash
gemini --mcp-config "path/to/mcp_servers.json" -m gemini-2.5-pro -p "Покажи первые 5 процессов в системе"
```

### Другие MCP-клиенты
Сервер совместим со всеми клиентами, поддерживающими MCP протокол 2024-11-05.

## Устранение неполадок

### Общие проблемы

1. **Порт занят**: Измените порт в конфигурации или остановите процесс, использующий порт
2. **Права доступа**: Запуск на привилегированных портах (<1024) требует прав администратора
3. **Кодировка**: Убедитесь, что PowerShell настроен на UTF-8
4. **Версия PowerShell**: Требуется PowerShell 7+

### Диагностика

Проверьте логи сервера для диагностики проблем:
```powershell
Get-Content "$env:TEMP\mcp-powershell-server.log" -Tail 20
```

## Разработка и расширение

Сервер легко расширяется новыми MCP инструментами. См. `how-to-use.md` для подробных инструкций по разработке.

## Лицензия

Этот проект распространяется под лицензией MIT. См. файл LICENSE для подробностей.

## Поддержка

- Создайте Issue в GitHub репозитории
- Проверьте документацию в `how-to-use.md`
- Ознакомьтесь с примерами использования

## Версии

- **1.0.0** - Начальная версия с поддержкой STDIO и HTTP режимов