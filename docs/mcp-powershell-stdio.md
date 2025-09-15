# MCP PowerShell Server Documentation

## Описание

MCP PowerShell Server - это сервер, реализующий протокол Model Context Protocol (MCP) для выполнения PowerShell скриптов. Сервер работает в STDIO режиме и предоставляет инструменты для безопасного выполнения PowerShell команд через стандартизированный интерфейс.

## Архитектура

### Основные компоненты

1. **JSON Конвертер** - функция для преобразования JSON в хэш-таблицы PowerShell
2. **Логирование** - система записи событий в файл
3. **MCP Обработчик** - основная логика обработки MCP запросов
4. **PowerShell Исполнитель** - изолированное выполнение скриптов
5. **STDIO Интерфейс** - коммуникация через стандартные потоки

### Структура файла

```
mcp-powershell-stdio.ps1
├── ConvertFrom-JsonToHashtable    # Функция конвертации JSON
├── Write-Log                      # Функция логирования
├── Test-MCPRequest               # Валидация MCP запросов
├── New-MCPResponse               # Создание MCP ответов
├── Invoke-PowerShellScript       # Выполнение PowerShell скриптов
├── Invoke-MCPMethod              # Обработка MCP методов
├── Send-MCPResponse              # Отправка ответов
├── Start-MCPServer               # Основной цикл сервера
└── Инициализация и запуск
```

## Функции

### ConvertFrom-JsonToHashtable

```powershell
function ConvertFrom-JsonToHashtable {
    param([string]$Json)
}
```

**Назначение**: Функция преобразует JSON строку в хэш-таблицы PowerShell для совместимости с PowerShell 5.x.

**Параметры**:
- `Json` (string) - JSON строка для преобразования

**Возвращает**: Хэш-таблицу с преобразованными данными

**Особенности**:
- Рекурсивное преобразование вложенных объектов
- Обработка массивов и коллекций
- Совместимость с PowerShell 5.x

### Write-Log

```powershell
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
}
```

**Назначение**: Функция записывает логи в файл, поскольку stdout используется для MCP коммуникации.

**Параметры**:
- `Message` (string) - Сообщение для записи в лог
- `Level` (string) - Уровень логирования (INFO, WARNING, ERROR, DEBUG)

**Особенности**:
- Запись в файл `$env:TEMP\mcp-powershell-server.log`
- Временные метки в формате `yyyy-MM-dd HH:mm:ss`
- UTF-8 кодировка

### Test-MCPRequest

```powershell
function Test-MCPRequest {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Request
    )
}
```

**Назначение**: Функция валидирует MCP запрос на соответствие протоколу.

**Параметры**:
- `Request` (hashtable) - MCP запрос для валидации

**Возвращает**: Boolean - результат валидации

**Проверки**:
- Наличие поля `jsonrpc` со значением "2.0"
- Наличие обязательного поля `method`

### New-MCPResponse

```powershell
function New-MCPResponse {
    param(
        [Parameter(Mandatory=$false)]
        [object]$Id = $null,
        
        [Parameter(Mandatory=$false)]
        [object]$Result = $null,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$Error = $null
    )
}
```

**Назначение**: Функция создает стандартизированный MCP ответ.

**Параметры**:
- `Id` (object) - Идентификатор запроса
- `Result` (object) - Результат выполнения операции
- `Error` (hashtable) - Информация об ошибке

**Возвращает**: Hashtable с MCP ответом

### Invoke-PowerShellScript

```powershell
function Invoke-PowerShellScript {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Script,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$Parameters = @{},
        
        [Parameter(Mandatory=$false)]
        [int]$TimeoutSeconds = 300,
        
        [Parameter(Mandatory=$false)]
        [string]$WorkingDirectory = $PWD
    )
}
```

**Назначение**: Функция выполняет PowerShell скрипт в изолированном процессе.

**Параметры**:
- `Script` (string) - PowerShell скрипт для выполнения
- `Parameters` (hashtable) - Параметры для скрипта
- `TimeoutSeconds` (int) - Таймаут выполнения (по умолчанию 300 сек)
- `WorkingDirectory` (string) - Рабочая директория

**Возвращает**: Hashtable с результатами выполнения:
- `success` (bool) - Статус выполнения
- `output` (string) - Вывод команды
- `errors` (array) - Массив ошибок
- `warnings` (array) - Массив предупреждений

**Особенности**:
- Изоляция через отдельный PowerShell процесс
- Поддержка таймаута
- Сбор всех потоков вывода (output, error, warning)
- Автоматическое освобождение ресурсов

## MCP Методы

### initialize

**Назначение**: Инициализация MCP сервера и обмен информацией о возможностях.

**Ответ**:
```json
{
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
```

### tools/list

**Назначение**: Получение списка доступных инструментов.

**Ответ**: Массив инструментов с описанием схем входных параметров.

### tools/call

**Назначение**: Вызов конкретного инструмента с параметрами.

**Параметры**:
- `name` (string) - Имя инструмента
- `arguments` (object) - Аргументы для инструмента

## Инструменты

### run-script

**Назначение**: Выполняет PowerShell скрипт с заданными параметрами.

**Схема входных параметров**:
```json
{
  "type": "object",
  "properties": {
    "script": {
      "type": "string",
      "description": "PowerShell скрипт для выполнения"
    },
    "parameters": {
      "type": "object",
      "description": "Параметры для скрипта (опционально)",
      "additionalProperties": true
    },
    "workingDirectory": {
      "type": "string",
      "description": "Рабочая директория для выполнения (опционально)",
      "default": "<текущая директория>"
    },
    "timeoutSeconds": {
      "type": "integer",
      "description": "Таймаут выполнения в секундах (опционально)",
      "default": 300,
      "minimum": 1,
      "maximum": 3600
    }
  },
  "required": ["script"]
}
```

**Ответ**: Структура с результатами выполнения, включающая:
- Вывод команды в форматированном виде
- Ошибки (если есть)
- Предупреждения (если есть)
- Метаданные выполнения

## Конфигурация

### Кодировка

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
```

Сервер настроен на работу с UTF-8 кодировкой для корректной обработки JSON данных.

### Логирование

- **Файл логов**: `$env:TEMP\mcp-powershell-server.log`
- **Кодировка**: UTF-8
- **Уровни**: INFO, WARNING, ERROR, DEBUG
- **Формат**: `[yyyy-MM-dd HH:mm:ss] [LEVEL] Message`

### Безопасность

- Изоляция скриптов через отдельные PowerShell процессы
- Таймауты для предотвращения зависания
- Валидация всех входящих запросов
- Логирование всех операций

## Использование

### Запуск сервера

```powershell
.\mcp-powershell-stdio.ps1
```

Сервер запускается в STDIO режиме и ожидает MCP команды через стандартный ввод.

### Примеры MCP запросов

#### Инициализация
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": {
      "name": "test-client",
      "version": "1.0.0"
    }
  }
}
```

#### Список инструментов
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list"
}
```

#### Выполнение скрипта
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "run-script",
    "arguments": {
      "script": "Get-Process | Select-Object -First 5 Name, CPU",
      "timeoutSeconds": 60
    }
  }
}
```

## Обработка ошибок

### Коды ошибок MCP

- `-32700`: Ошибка парсинга JSON
- `-32600`: Невалидный MCP запрос
- `-32601`: Неизвестный метод или инструмент
- `-32602`: Неверные параметры
- `-32603`: Внутренняя ошибка сервера

### Логирование ошибок

Все ошибки логируются в файл с детальной информацией:
- Временная метка
- Уровень ошибки
- Подробное описание
- Stack trace (при необходимости)

## Ограничения

1. **Таймаут выполнения**: Максимум 3600 секунд (1 час)
2. **Изоляция процессов**: Каждый скрипт выполняется в отдельном процессе
3. **Кодировка**: Только UTF-8
4. **Совместимость**: PowerShell 5.x и выше

## Производительность

- Минимальные накладные расходы на создание процессов
- Эффективная сериализация JSON
- Автоматическая очистка ресурсов
- Оптимизированное логирование

## Масштабируемость

Сервер разработан для обработки одного запроса за раз в синхронном режиме. Для параллельной обработки требуется запуск нескольких экземпляров сервера.

---

*Версия документации: 1.0.0*  
*Дата создания: 15 сентября 2025*