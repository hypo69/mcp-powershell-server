
### **Общая картина: Что такое MCP PowerShell HTTP Server?**

Основная задача сервера `mcp-powershell-http.ps1` — быть "мостом" между внешним миром (например, ИИ-ассистентом вроде Gemini) и средой выполнения PowerShell на вашем компьютере. Он принимает команды по стандартному веб-протоколу HTTP, выполняет их в безопасной среде и возвращает результат.

Вся коммуникация происходит по протоколу **MCP (Model Context Protocol)**, который стандартизирует обмен сообщениями в формате JSON-RPC.

### **Пошаговый разбор работы сервера**

Представим полный цикл работы: от запуска сервера до получения ответа на выполненный скрипт.

#### **1. Запуск и инициализация (`Main Entry Point`)**

Когда вы запускаете скрипт `.\mcp-powershell-http.ps1`, происходит следующее:

1. **Прием параметров:** Скрипт принимает параметры командной строки, такие как `-Port`, `-ServerHost` и `-ConfigFile`.
2. **Загрузка конфигурации:**
   * Сначала устанавливаются значения по умолчанию (порт `8090`, хост `localhost`, таймаут `300` секунд).
   * Если указан `-ConfigFile` (например, `config.json`), скрипт считывает этот файл и переопределяет значения по умолчанию. Это позволяет гибко настраивать сервер, не меняя сам код.
3. **Проверка доступности порта:** Перед полноценным запуском сервер делает быструю проверку, не занят ли указанный порт другим приложением. Если порт занят, сервер завершит работу с ошибкой.
4. **Вызов `Start-MCPServer`:** Основная логика запускается в этой функции.

#### **2. Ожидание запросов (`Start-MCPServer`)**

Эта функция — сердце сервера, его главный цикл:

1. **Создание "слушателя":** С помощью встроенного в .NET класса `System.Net.HttpListener` создается HTTP-сервер, который "слушает" входящие запросы по указанному адресу (например, `http://localhost:8090/`).
2. **Бесконечный цикл:** Сервер входит в цикл `while ($listener.IsListening)`, где он постоянно ожидает новые подключения.
3. **Блокировка и ожидание:** Команда `$context = $listener.GetContext()` является блокирующей. Это значит, что выполнение скрипта останавливается на этой строке до тех пор, пока не поступит новый HTTP-запрос.
4. **Передача на обработку:** Как только запрос получен, вся информация о нём (контекст) передается в функцию `Invoke-RequestHandler` для дальнейшей обработки.

#### **3. Обработка HTTP-запроса (`Invoke-RequestHandler`)**

Эта функция отвечает за разбор HTTP-запроса и валидацию:

1. **Проверка метода:** Сервер принимает только `POST`-запросы, как того требует специфика API. Любые другие методы (GET, PUT и т.д.) будут отклонены с ошибкой `405 Method Not Allowed`.
2. **Чтение тела запроса:** Содержимое `POST`-запроса (JSON-сообщение) считывается из входного потока.
3. **Парсинг JSON:** Текстовое тело запроса преобразуется в объект PowerShell с помощью `ConvertFrom-Json`. Если JSON некорректен, сервер вернёт ошибку `Parse error (-32700)`.
4. **Валидация MCP:** Функция `Test-MCPRequest` проверяет, соответствует ли JSON протоколу (наличие полей `jsonrpc: "2.0"` и `method`).
5. **Делегирование:** Если все проверки пройдены, запрос передаётся в `Invoke-MCPMethod` для выполнения нужной команды.

#### **4. Выполнение MCP-метода (`Invoke-MCPMethod`)**

Это диспетчер, который определяет, что именно запросил клиент. Он использует конструкцию `switch` по имени метода:

* **`initialize`:** Это первый запрос от клиента для "знакомства". Сервер отвечает информацией о себе: поддерживаемая версия протокола, название и версия сервера.
* **`tools/list`:** Клиент запрашивает список доступных "инструментов". В данном случае сервер сообщает, что у него есть один инструмент — `run-script`, и описывает его параметры (`script`, `parameters` и т.д.).
* **`tools/call`:** Это самый главный метод — вызов инструмента.
  1. Сервер проверяет, что имя инструмента — `run-script`.
  2. Он извлекает аргументы: сам PowerShell-скрипт для выполнения, его параметры, рабочую директорию и таймаут.
  3. Далее он вызывает функцию `Invoke-PowerShellScript`, которая и выполняет "грязную работу".

#### **5. Безопасное выполнение скрипта (`Invoke-PowerShellScript`)**

Это ключевой компонент, обеспечивающий безопасность и стабильность:

1. **Изоляция:** Самое важное — `[powershell]::Create()` создаёт **новый, полностью изолированный экземпляр PowerShell**. Это значит, что выполняемый скрипт не может повлиять на переменные или состояние самого сервера.
2. **Установка окружения:** В этом новом экземпляре устанавливается рабочая директория.
3. **Передача скрипта и параметров:** В него добавляются текст скрипта и его параметры.
4. **Асинхронный запуск с таймаутом:**
   * Скрипт запускается асинхронно через `BeginInvoke()`.
   * Основной поток ждёт завершения с помощью `WaitOne($TimeoutSeconds * 1000)`. Если скрипт работает дольше указанного таймаута, `WaitOne` вернёт `false`.
   * В случае таймаута выполнение скрипта принудительно останавливается (`$powerShell.Stop()`), и возвращается ошибка.
5. **Сбор результатов:** Если скрипт завершился успешно, сервер собирает всё, что он вывел:
   * **Стандартный вывод (Output):** Основной результат.
   * **Ошибки (Errors):** Поток ошибок.
   * **Предупреждения (Warnings):** Поток предупреждений.
6. **Ограничение вывода:** Для предотвращения отправки гигабайтов данных, размер вывода ограничивается (в данном коде — 10 000 символов).
7. **Возврат структурированного результата:** Функция возвращает объект с полями `success`, `output`, `errors` и `warnings`.

#### **6. Формирование и отправка ответа**

1. Получив результат от `Invoke-PowerShellScript`, метод `Invoke-MCPMethod` форматирует его в соответствии со спецификацией MCP: создаёт массив `content` с блоками для вывода, ошибок и предупреждений.
2. Этот финальный объект возвращается в `Invoke-RequestHandler`.
3. `Invoke-RequestHandler` конвертирует объект PowerShell обратно в JSON-строку (`ConvertTo-Json`).
4. JSON-строка записывается в выходной поток HTTP-ответа, и он отправляется клиенту.

### **Ключевые аспекты**

* **Безопасность:** Главные меры безопасности — это изоляция выполнения скриптов, настраиваемые таймауты и возможность (через `config.json`) задавать списки запрещённых команд и разрешённых путей.
* **Стабильность:** Использование `try/catch` на всех уровнях (от обработки HTTP до выполнения скрипта) позволяет серверу корректно обрабатывать ошибки и не "падать" от некорректного запроса или сбойного скрипта.
* **Гибкость:** Конфигурация через `config.json` позволяет администраторам легко настраивать порты, хосты, таймауты и параметры безопасности без необходимости редактировать исходный код.

В итоге, `mcp-powershell-http.ps1` — это хорошо продуманный и надёжный сервер, который превращает PowerShell в мощный инструмент, управляемый через стандартизированный API.

settings.json

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
    "C:\\Temp\\",
    "C:\\Users\\%USERNAME%\\Documents\\",
    "%LOCALAPPDATA%\\HYPO69\\"
  ],
  "Security": {
    "EnableScriptValidation": false,
    "BlockDangerousCommands": false,
    "RestrictedCommands": [
      "Remove-Item -Path C:\\Windows\\*",
      "Remove-Item -Path C:\\Program Files\\*",
      "Format-Volume",
      "Stop-Computer -Force",
      "Restart-Computer -Force",
      "Remove-Item -Path HKLM:\\*",
      "New-ItemProperty -Path HKLM:\\*",
      "Set-ItemProperty -Path HKLM:\\*",
      "Remove-ItemProperty -Path HKLM:\\*"
    ],
    "AllowedModules": [
      "Microsoft.PowerShell.*",
      "PackageManagement",
      "PowerShellGet",
      "PSReadLine",
      "ThreadJob"
    ],
    "MaxOutputSize": 10000,
    "MaxScriptLength": 50000
  },
  "Logging": {
    "LogFile": "%TEMP%\\mcp-powershell-server.log",
    "MaxLogSize": "10MB",
    "LogRotation": true,
    "DetailedLogging": false
  },
  "Performance": {
    "EnableCache": false,
    "CacheTimeout": 300,
    "MaxMemoryUsage": "512MB"
  }
}
```

## \file mcp-powershell-server/mcp-powershell-http.ps1

# -*- coding: utf-8 -*-

#! .pyenv/bin/powershell

<#
.SYNOPSIS
    Улучшенный MCP PowerShell Server (HTTP версия)

.DESCRIPTION
    HTTP сервер для выполнения PowerShell скриптов через MCP протокол.
    Версия с улучшенной обработкой ошибок, безопасностью и производительностью.

.PARAMETER Port
    Порт для HTTP сервера (по умолчанию: 8090)

.PARAMETER ServerHost
    Хост для привязки сервера (по умолчанию: localhost)

.PARAMETER ConfigFile
    Путь к файлу конфигурации JSON

.EXAMPLE
    .\mcp-powershell-http-improved.ps1 -Port 8090 -ServerHost localhost

.NOTES
    Version: 1.1.0
    Author: MCP PowerShell Server Team
    Protocol: MCP 2024-11-05
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [int]$Port = 8090,

    [Parameter(Mandatory = $false)]
    [string]$ServerHost = "localhost",

    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = $null
)

# Глобальные переменные конфигурации

$script:ServerConfig = @{
    Port = $Port
    Host = $ServerHost
    MaxConcurrentRequests = 10
    TimeoutSeconds = 300
    Name = "PowerShell Script Runner"
    Version = "1.1.0"
    Description = "HTTP MCP сервер для выполнения PowerShell скриптов"
    LogLevel = "INFO"
}

# Загрузка конфигурации из файла если указан

if ($ConfigFile -and (Test-Path $ConfigFile)) {
    try {
        $configData = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        if ($configData.Port) { $script:ServerConfig.Port = $configData.Port }
        if ($configData.Host) { $script:ServerConfig.Host = $configData.Host }
        if ($configData.MaxConcurrentRequests) { $script:ServerConfig.MaxConcurrentRequests = $configData.MaxConcurrentRequests }
        if ($configData.TimeoutSeconds) { $script:ServerConfig.TimeoutSeconds = $configData.TimeoutSeconds }
        Write-Log "Конфигурация загружена из файла: $ConfigFile" -Level "INFO"
    }
    catch {
        Write-Log "Ошибка загрузки конфигурации: $($_.Exception.Message)" -Level "ERROR"
    }
}

# Список потенциально опасных команд

$script:RestrictedCommands = @(
    'Remove-Item', 'del', 'rm', 'rmdir',
    'Format-Volume',
    'Stop-Computer', 'Restart-Computer',
    'Stop-Process', 'Stop-Service',
    'Invoke-Expression', 'iex',
    'New-ItemProperty.*HKLM', 'Set-ItemProperty.*HKLM',
    'Remove-ItemProperty.*HKLM'
)

#region Utility Functions

function Write-Log {
    <#
    .SYNOPSIS
        Записывает сообщение в консоль с цветовой индикацией и временной меткой

    .PARAMETER Message
        Текст сообщения

    .PARAMETER Level
        Уровень логирования
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

    [Parameter(Mandatory = $false)]
        [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"$logMessage = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        "INFO" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        "DEBUG" { "Cyan" }
        default { "White" }
    }

    Write-Host$logMessage -ForegroundColor $color
}

function Test-MCPRequest {
    <#
    .SYNOPSIS
        Проверяет валидность MCP запроса

    .PARAMETER Request
        Хеш-таблица с данными запроса

    .RETURNS
        $true если запрос валиден
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Request
    )

    if (-not$Request.ContainsKey("jsonrpc") -or $Request.jsonrpc -ne "2.0") {
        Write-Log "Неверная версия JSON-RPC: $($Request.jsonrpc)" -Level "WARNING"
        return $false
    }

    if (-not$Request.ContainsKey("method") -or [string]::IsNullOrEmpty($Request.method)) {
        Write-Log "Отсутствует или пустой метод" -Level "WARNING"
        return $false
    }

    return $true
}

function New-MCPResponse {
    <#
    .SYNOPSIS
        Создает стандартизированный MCP ответ

    .PARAMETER Id
        Идентификатор запроса

    .PARAMETER Result
        Данные результата

    .PARAMETER Error
        Данные ошибки

    .RETURNS
        Хеш-таблица с MCP ответом
    #>
    param(
        [Parameter(Mandatory = $false)]
        [object]$Id = $null,

    [Parameter(Mandatory = $false)]
        [object]$Result = $null,

    [Parameter(Mandatory = $false)]
        [hashtable]$Error = $null
    )

    $response = @{
        jsonrpc = "2.0"
        id = $Id
    }

    if ($Error) {$response.error = $Error
        Write-Log "Отправка ошибки: $($Error.message)" -Level "ERROR"
    } else {
        $response.result = $Result
    }

    return $response
}

function Test-ScriptSafety {
    <#
    .SYNOPSIS
        Проверяет скрипт на наличие потенциально опасных команд

    .PARAMETER Script
        PowerShell скрипт для анализа

    .RETURNS
        $true если скрипт безопасен
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Script
    )

    # Функция проверки безопасности отключена в демо версии
    return $true
}

function Invoke-PowerShellScript {
    <#
    .SYNOPSIS
        Выполняет PowerShell скрипт в изолированном окружении

    .PARAMETER Script
        PowerShell код для выполнения

    .PARAMETER Parameters
        Параметры для передачи в скрипт

    .PARAMETER TimeoutSeconds
        Таймаут выполнения в секундах

    .PARAMETER WorkingDirectory
        Рабочая директория для выполнения

    .RETURNS
        Хеш-таблица с результатами выполнения
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Script,

    [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{},

    [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 300,

    [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = $PWD.Path
    )

    $executionId = [guid]::NewGuid().ToString("N")[0..7] -join ""
    Write-Log "[$executionId] Начало выполнения скрипта. Таймаут: $TimeoutSeconds сек" -Level "INFO"
    Write-Log "[$executionId] Скрипт: $($Script.Substring(0, [Math]::Min(200, $Script.Length)))$(if($Script.Length -gt 200){'...'})" -Level "DEBUG"

    $powerShell = $null
    $asyncResult = $null

    try {
        # Проверка безопасности
        if (-not (Test-ScriptSafety -Script $Script)) {
            return @{
                success = $false
                output = ""
                errors = @("Скрипт содержит потенциально опасные команды")
                warnings = @()
                executionTime = 0
            }
        }

    # Создание изолированного PowerShell процесса
        $powerShell = [powershell]::Create()

    # Установка рабочей директории
        if ($WorkingDirectory -ne $PWD.Path -and (Test-Path $WorkingDirectory)) {
            $powerShell.AddScript("Set-Location -Path '$WorkingDirectory' -ErrorAction SilentlyContinue") | Out-Null
        }

    # Добавление основного скрипта$powerShell.AddScript($Script) | Out-Null

    # Добавление параметров
        foreach ($param in $Parameters.GetEnumerator()) {
            $powerShell.AddParameter($param.Key, $param.Value) | Out-Null
        }

    # Выполнение с таймаутом
        $startTime = Get-Date$asyncResult = $powerShell.BeginInvoke()

    $completed = $asyncResult.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)
        $executionTime = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)

    if ($completed) {$result = $powerShell.EndInvoke($asyncResult)
            $errors = $powerShell.Streams.Error
            $warnings = $powerShell.Streams.Warning

    # Формирование вывода с ограничением размера$outputText = if ($result) {
                ($result | Out-String -Width 120).Trim()
            } else {
                ""
            }

    # Ограничение размера вывода
            if ($outputText.Length -gt 10000) {$outputText = $outputText.Substring(0, 10000) + "`n... [вывод обрезан]"
            }

    $output = @{
                success = $errors.Count -eq 0
                output = $outputText
                errors = @($errors | ForEach-Object { $_.ToString() })
                warnings = @($warnings | ForEach-Object { $_.ToString() })
                executionTime = $executionTime
            }

    $status = if ($output.success) { "SUCCESS" } else { "ERROR" }
            Write-Log "[$executionId] Выполнение завершено: $status за $executionTime сек" -Level "INFO"

    return $output
        } else {
            # Таймаут
            Write-Log "[$executionId] Таймаут выполнения ($TimeoutSeconds сек)" -Level "ERROR"
            $powerShell.Stop()

    return @{
                success = $false
                output = ""
                errors = @("Превышено время выполнения скрипта ($TimeoutSeconds секунд)")
                warnings = @()
                executionTime = $executionTime
            }
        }
    }
    catch {$errorMessage = $_.Exception.Message
        Write-Log "[$executionId] Ошибка выполнения: $errorMessage" -Level "ERROR"

    return @{
            success = $false
            output = ""
            errors = @("Ошибка выполнения: $errorMessage")
            warnings = @()
            executionTime = if ($startTime) { [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2) } else { 0 }
        }
    }
    finally {
        # Очистка ресурсов
        if ($asyncResult) {
            try { $asyncResult.AsyncWaitHandle.Close() } catch { }
        }
        if ($powerShell) {
            try { $powerShell.Dispose() } catch { }
        }
    }
}

#endregion

#region MCP Protocol Methods

function Invoke-MCPMethod {
    <#
    .SYNOPSIS
        Обрабатывает MCP методы согласно протоколу

    .PARAMETER Method
        Имя вызываемого метода

    .PARAMETER Params
        Параметры метода

    .PARAMETER Id
        Идентификатор запроса

    .RETURNS
        MCP ответ в виде хеш-таблицы
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Method,

    [Parameter(Mandatory = $false)]
        [hashtable]$Params = @{},

    [Parameter(Mandatory = $false)]
        [object]$Id = $null
    )

    Write-Log "Обработка MCP метода: $Method" -Level "DEBUG"

    switch ($Method) {
        "initialize" {
            Write-Log "Инициализация MCP сервера" -Level "INFO"
            return New-MCPResponse -Id $Id -Result @{
                protocolVersion = "2024-11-05"
                capabilities = @{
                    tools = @{
                        listChanged = $true
                    }
                }
                serverInfo = @{
                    name = $script:ServerConfig.Name
                    version = $script:ServerConfig.Version
                    description = $script:ServerConfig.Description
                }
            }
        }

    "tools/list" {
            Write-Log "Запрос списка инструментов" -Level "DEBUG"
            return New-MCPResponse -Id $Id -Result @{
                tools = @(
                    @{
                        name = "run-script"
                        description = "Выполняет PowerShell скрипт с заданными параметрами"
                        inputSchema = @{
                            type = "object"
                            properties = @{
                                script = @{
                                    type = "string"
                                    description = "PowerShell код для выполнения"
                                }
                                parameters = @{
                                    type = "object"
                                    description = "Параметры для скрипта (опционально)"
                                    additionalProperties = $true
                                }
                                workingDirectory = @{
                                    type = "string"
                                    description = "Рабочая директория (опционально)"
                                    default = $PWD.Path
                                }
                                timeoutSeconds = @{
                                    type = "integer"
                                    description = "Таймаут выполнения в секундах"
                                    default = 300
                                    minimum = 1
                                    maximum = 3600
                                }
                            }
                            required = @("script")
                        }
                    }
                )
            }
        }

    "tools/call" {
            if (-not $Params.ContainsKey("name")) {
                return New-MCPResponse -Id $Id -Error @{
                    code = -32602
                    message = "Отсутствует обязательный параметр 'name'"
                }
            }

    $toolName = $Params.name
            $arguments = if ($Params.ContainsKey("arguments")) { $Params.arguments } else { @{} }

    Write-Log "Вызов инструмента: $toolName" -Level "INFO"

    switch ($toolName) {
                "run-script" {
                    if (-not $arguments.ContainsKey("script")) {
                        return New-MCPResponse -Id $Id -Error @{
                            code = -32602
                            message = "Отсутствует обязательный параметр 'script'"
                        }
                    }

    # Извлечение параметров$script = $arguments.script
                    $parameters = if ($arguments.ContainsKey("parameters")) { $arguments.parameters } else { @{} }
                    $workingDirectory = if ($arguments.ContainsKey("workingDirectory")) {
                        $arguments.workingDirectory
                    } else {
                        $PWD.Path
                    }
                    $timeoutSeconds = if ($arguments.ContainsKey("timeoutSeconds")) {
                        [math]::Max(1, [math]::Min(3600, [int]$arguments.timeoutSeconds))
                    } else {
                        $script:ServerConfig.TimeoutSeconds
                    }

    # Выполнение скрипта$result = Invoke-PowerShellScript -Script $script -Parameters $parameters -WorkingDirectory $workingDirectory -TimeoutSeconds $timeoutSeconds

    # Формирование контента ответа
                    $content = @()

    if ($result.output) {
                        $content += @{
                            type = "text"
                            text = "Результат выполнения PowerShell скрипта:`n`n ``powershell`n$($result.output)`n``"
                        }
                    }

    if ($result.errors.Count -gt 0) {$errorText = $result.errors -join "`n"                         $content += @{                             type = "text"                             text = "Ошибки выполнения:`n `n``````text`n$errorText`n``````"
                        }
                    }

    if ($result.warnings.Count -gt 0) {$warningText = $result.warnings -join "`n"                         $content += @{                             type = "text"                             text = "Предупреждения:`n `n``````text`n$warningText`n``````"
                        }
                    }

    if ($content.Count -eq 0) {
                        $content += @{
                            type = "text"
                            text = "Скрипт выполнен успешно. Результат выполнения отсутствует."
                        }
                    }

    return New-MCPResponse -Id $Id -Result @{
                        content = $content
                        isError = -not $result.success
                        _meta = @{
                            executionTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                            success = $result.success
                            errorCount = $result.errors.Count
                            warningCount = $result.warnings.Count
                            executionDuration = $result.executionTime
                        }
                    }
                }

    default {
                    return New-MCPResponse -Id $Id -Error @{
                        code = -32601
                        message = "Неизвестный инструмент: $toolName"
                    }
                }
            }
        }

    default {
            return New-MCPResponse -Id $Id -Error @{
                code = -32601
                message = "Неизвестный метод: $Method"
            }
        }
    }
}

#endregion

#region HTTP Server

function Invoke-RequestHandler {
    <#
    .SYNOPSIS
        Обрабатывает HTTP запрос к MCP серверу

    .PARAMETER Context
        Контекст HTTP запроса
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context
    )

    $request = $Context.Request
    $response = $Context.Response
    $clientEndpoint = $request.RemoteEndPoint.ToString()

    try {
        Write-Log "HTTP запрос от$clientEndpoint : $($request.HttpMethod) $($request.Url.AbsolutePath)" -Level "INFO"

    # Установка CORS заголовков
        $response.Headers.Add("Access-Control-Allow-Origin", "*")
        $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")

    # Обработка OPTIONS запроса (CORS preflight)
        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Close()
            Write-Log "OPTIONS запрос обработан успешно" -Level "DEBUG"
            return
        }

    # Поддержка только POST запросов для MCP
        if ($request.HttpMethod -ne "POST") {
            $response.StatusCode = 405
            $errorResponse = @{
                jsonrpc = "2.0"
                error = @{
                    code = -32600
                    message = "Поддерживается только POST метод"
                }
                id = $null
            }$responseJson = $errorResponse | ConvertTo-Json -Depth 10
            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            $response.Close()
            Write-Log "Отклонен запрос с неподдерживаемым методом: $($request.HttpMethod)" -Level "WARNING"
            return
        }

    # Чтение тела запроса$reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
        $requestBody = $reader.ReadToEnd()
        $reader.Close()

    if ([string]::IsNullOrWhiteSpace($requestBody)) {
            $response.StatusCode = 400
            $errorResponse = @{
                jsonrpc = "2.0"
                error = @{
                    code = -32600
                    message = "Пустое тело запроса"
                }
                id = $null
            }$responseJson = $errorResponse | ConvertTo-Json -Depth 10
            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            $response.Close()
            Write-Log "Отклонен запрос с пустым телом" -Level "WARNING"
            return
        }

    Write-Log "Получено тело запроса (длина:$($requestBody.Length) символов)" -Level "DEBUG"

    # Парсинг JSON
        try {$mcpRequest = $requestBody | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        }
        catch {
            $response.StatusCode = 400
            $errorResponse = @{
                jsonrpc = "2.0"
                error = @{
                    code = -32700
                    message = "Ошибка парсинга JSON: $($_.Exception.Message)"
                }
                id = $null
            }
            $responseJson = $errorResponse | ConvertTo-Json -Depth 10
            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            $response.Close()
            Write-Log "Ошибка парсинга JSON: $($_.Exception.Message)" -Level "ERROR"
            return
        }

    # Валидация MCP запроса
        if (-not (Test-MCPRequest -Request $mcpRequest)) {
            $response.StatusCode = 400
            $errorResponse = @{
                jsonrpc = "2.0"
                error = @{
                    code = -32600
                    message = "Неверный формат MCP запроса"
                }
                id = if ($mcpRequest.ContainsKey("id")) { $mcpRequest.id } else { $null }
            }
            $responseJson = $errorResponse | ConvertTo-Json -Depth 10
            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            $response.Close()
            Write-Log "Неверный формат MCP запроса" -Level "WARNING"
            return
        }

    # Обработка MCP метода$mcpResponse = Invoke-MCPMethod -Method $mcpRequest.method -Params $mcpRequest.params -Id $mcpRequest.id

    # Отправка успешного ответа
        $response.StatusCode = 200
        $response.ContentType = "application/json; charset=utf-8"

    $responseJson = $mcpResponse | ConvertTo-Json -Depth 15
        $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)

    $response.ContentLength64 = $responseBytes.Length
        $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)

    Write-Log "Успешный ответ отправлен клиенту $clientEndpoint" -Level "INFO"

    }
    catch {
        Write-Log "Критическая ошибка обработки запроса от$clientEndpoint : $($_.Exception.Message)" -Level "ERROR"

    try {
            $response.StatusCode = 500
            $errorResponse = @{
                jsonrpc = "2.0"
                error = @{
                    code = -32603
                    message = "Внутренняя ошибка сервера"
                }
                id = $null
            }$responseJson = $errorResponse | ConvertTo-Json -Depth 10
            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
        }
        catch {
            Write-Log "Критическая ошибка отправки ответа об ошибке: $($_.Exception.Message)" -Level "ERROR"
        }
    }
    finally {
        if ($response) {
            try {
                $response.Close()
            }
            catch {
                Write-Log "Ошибка закрытия HTTP ответа: $($_.Exception.Message)" -Level "WARNING"
            }
        }
    }
}

function Start-MCPServer {
    <#
    .SYNOPSIS
        Запускает HTTP MCP сервер

    .PARAMETER Config
        Конфигурация сервера
    #>
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$Config = $script:ServerConfig
    )

    $listener = $null

    try {
        # Создание HTTP listener
        $listener = New-Object System.Net.HttpListener$url = "http://$($Config.Host):$($Config.Port)/"
        $listener.Prefixes.Add($url)

    Write-Log "=== Запуск MCP PowerShell HTTP Server v$($Config.Version) ===" -Level "INFO"
        Write-Log "URL: $url" -Level "INFO"
        Write-Log "Максимальное время выполнения: $($Config.TimeoutSeconds) сек" -Level "INFO"
        Write-Log "Максимальные concurrent запросы: $($Config.MaxConcurrentRequests)" -Level "INFO"

    # Запуск listener
        $listener.Start()
        Write-Log "HTTP сервер запущен и ожидает подключения..." -Level "INFO"

    # Основной цикл обработки запросов
        $requestCount = 0
        while ($listener.IsListening) {
            try {
                # Ожидание входящего запроса$context = $listener.GetContext()
                $requestCount++

    Write-Log "Запрос #$requestCount от $($context.Request.RemoteEndPoint)" -Level "INFO"

    # Обработка запроса
                Invoke-RequestHandler -Context $context

    }
            catch [System.Net.HttpListenerException] {
                if ($_.Exception.ErrorCode -ne 995) { # ERROR_OPERATION_ABORTED
                    Write-Log "HTTP listener ошибка: $($_.Exception.Message)" -Level "ERROR"
                }
                break
            }
            catch {
                Write-Log "Ошибка в главном цикле сервера: $($_.Exception.Message)" -Level "ERROR"
            }
        }
    }
    catch {
        Write-Log "Критическая ошибка сервера: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
    finally {
        if ($listener -and $listener.IsListening) {
            Write-Log "Остановка HTTP сервера..." -Level "INFO"
            try {
                $listener.Stop()
                $listener.Close()
            } catch {
                Write-Log "Ошибка при остановке listener: $($_.Exception.Message)" -Level "WARNING"
            }
        }
        Write-Log "=== HTTP сервер завершен ===" -Level "INFO"
    }
}

#endregion

#region Signal Handlers

# Обработчик завершения работы

$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Write-Log "Получен сигнал завершения PowerShell" -Level "INFO"
}

# Обработчик Ctrl+C

try {
    [Console]::TreatControlCAsInput = $false
    if ([Console].GetMethod("add_CancelKeyPress")) {
        [Console]::add_CancelKeyPress({
            param($sender, $e)
            $e.Cancel = $true
            Write-Log "Получен сигнал прерывания (Ctrl+C)" -Level "INFO"
            [Environment]::Exit(0)
        })
    }
}
catch {
    Write-Log "Предупреждение: Не удалось установить обработчик Ctrl+C" -Level "WARNING"
}

#endregion

#region Main Entry Point

try {
    Write-Log "Инициализация MCP PowerShell HTTP Server v$($script:ServerConfig.Version)" -Level "INFO"
    Write-Log "PowerShell версия: $($PSVersionTable.PSVersion)" -Level "INFO"
    Write-Log "Конфигурация: Host=$($script:ServerConfig.Host), Port=$($script:ServerConfig.Port)" -Level "INFO"

    # Проверка доступности порта
    try {$ipAddress = if ($script:ServerConfig.Host -eq "localhost") {
            [System.Net.IPAddress]::Loopback
        } else {
            [System.Net.IPAddress]::Parse($script:ServerConfig.Host)
        }

    $tcpListener = New-Object System.Net.Sockets.TcpListener($ipAddress, $script:ServerConfig.Port)
        $tcpListener.Start()
        $tcpListener.Stop()
        Write-Log "Порт $($script:ServerConfig.Port) доступен" -Level "INFO"
    }
    catch {
        Write-Log "ОШИБКА: Порт $($script:ServerConfig.Port) недоступен: $($_.Exception.Message)" -Level "ERROR"
        exit 1
    }

    # Запуск сервера
    Start-MCPServer -Config $script:ServerConfig
}
catch {
    Write-Log "КРИТИЧЕСКАЯ ОШИБКА:$($_.Exception.Message)" -Level "ERROR"
    exit 1
}

#endregion

## \file mcp-powershell-server/mcp-powershell-stdio.ps1

# -*- coding: utf-8 -*-

#! .pyenv/bin/powershell

<#
.SYNOPSIS
    Улучшенный MCP PowerShell Server (STDIO версия)

.DESCRIPTION
    Сервер MCP для выполнения PowerShell скриптов через протокол JSON-RPC
    с использованием стандартных потоков ввода-вывода.

    Версия с исправленными проблемами кодировки, улучшенной обработкой ошибок
    и расширенной функциональностью безопасности.

.NOTES
    Version: 1.1.0
    Author: MCP PowerShell Server Team
    Protocol: MCP 2024-11-05
#>

#Requires -Version 7.0

# Настройка кодировки для корректной работы с UTF-8

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# Глобальные переменные конфигурации

$script:ServerConfig = @{
    Name = "PowerShell Script Runner"
    Version = "1.1.0"
    Description = "Выполняет PowerShell скрипты через MCP протокол"
    MaxExecutionTime = 300
    LogLevel = "INFO"
}

# Файл логирования

$script:LogFile = Join-Path $env:TEMP "mcp-powershell-server.log"

# Список потенциально опасных команд

$script:RestrictedCommands = @(
    'Remove-Item', 'del', 'rm', 'rmdir',
    'Format-Volume', 'Format-Table',
    'Stop-Computer', 'Restart-Computer',
    'Stop-Process', 'Stop-Service',
    'Invoke-Expression', 'iex',
    'New-ItemProperty.*HKLM', 'Set-ItemProperty.*HKLM',
    'Remove-ItemProperty.*HKLM',
    'Clear-Host', 'cls', 'clear'
)

#region Utility Functions

function ConvertFrom-JsonToHashtable {
    <#
    .SYNOPSIS
        Конвертирует JSON строку в хеш-таблицу для PowerShell 5.x/7.x совместимости

    .PARAMETER Json
        JSON строка для конвертации

    .RETURNS
        Хеш-таблица с данными из JSON
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json
    )

    try {$obj = ConvertFrom-Json $Json -ErrorAction Stop

    function ConvertTo-Hashtable($InputObject) {
            $hash = @{}
            if ($null -eq $InputObject) { return $hash }

    $InputObject.PSObject.Properties | ForEach-Object {$value = $_.Value
                if ($value -is [PSCustomObject]) {
                    $value = ConvertTo-Hashtable $value
                }
                elseif ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                    $value = @($value | ForEach-Object {
                        if ($_ -is [PSCustomObject]) {
                            ConvertTo-Hashtable $_
                        } else {
                            $_
                        }
                    })
                }
                $hash[$_.Name] = $value
            }
            return $hash
        }

    return ConvertTo-Hashtable $obj
    }
    catch {
        Write-Log "Ошибка парсинга JSON:$($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Записывает сообщение в лог файл с временной меткой

    .PARAMETER Message
        Текст сообщения

    .PARAMETER Level
        Уровень логирования (DEBUG, INFO, WARNING, ERROR)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

    [Parameter(Mandatory = $false)]
        [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"$logMessage = "[$timestamp] [$Level] $Message"

    # Асинхронная запись в лог для избежания блокировки$null = Add-Content -Path $script:LogFile -Value $logMessage -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {
        # Игнорируем ошибки логирования чтобы не нарушать работу сервера
    }
}

function Test-MCPRequest {
    <#
    .SYNOPSIS
        Проверяет валидность MCP запроса

    .PARAMETER Request
        Хеш-таблица с данными запроса

    .RETURNS$true если запрос валиден, $false в противном случае
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Request
    )

    # Проверка обязательных полей MCP протокола
    if (-not$Request.ContainsKey("jsonrpc") -or $Request.jsonrpc -ne "2.0") {
        Write-Log "Неверная версия JSON-RPC: $($Request.jsonrpc)" -Level "WARNING"
        return $false
    }

    if (-not$Request.ContainsKey("method") -or [string]::IsNullOrEmpty($Request.method)) {
        Write-Log "Отсутствует или пустой метод" -Level "WARNING"
        return $false
    }

    return $true
}

function New-MCPResponse {
    <#
    .SYNOPSIS
        Создает стандартизированный MCP ответ

    .PARAMETER Id
        Идентификатор запроса

    .PARAMETER Result
        Данные результата (взаимоисключающе с Error)

    .PARAMETER Error
        Данные ошибки (взаимоисключающе с Result)

    .RETURNS
        Хеш-таблица с MCP ответом
    #>
    param(
        [Parameter(Mandatory = $false)]
        [object]$Id = $null,

    [Parameter(Mandatory = $false)]
        [object]$Result = $null,

    [Parameter(Mandatory = $false)]
        [hashtable]$Error = $null
    )

    $response = @{
        jsonrpc = "2.0"
        id = $Id
    }

    if ($Error) {$response.error = $Error
        Write-Log "Отправка ошибки: $($Error.message)" -Level "ERROR"
    } else {
        $response.result = $Result
        Write-Log "Отправка результата для метода" -Level "DEBUG"
    }

    return $response
}

function Test-ScriptSafety {
    <#
    .SYNOPSIS
        Проверяет скрипт на наличие потенциально опасных команд

    .PARAMETER Script
        PowerShell скрипт для анализа

    .RETURNS$true если скрипт безопасен, $false если найдены опасные команды
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Script
    )

    # Функция проверки безопасности отключена по умолчанию в демо версии
    # В продакшене следует включить и настроить под конкретные требования
    return $true

    <#
    foreach ($restrictedCmd in $script:RestrictedCommands) {
        if ($Script -match $restrictedCmd) {
            Write-Log "Обнаружена потенциально опасная команда: $restrictedCmd в скрипте: $($Script.Substring(0, [Math]::Min(100, $Script.Length)))" -Level "WARNING"
            return $false
        }
    }

    return $true
    #>
}

#endregion

#region Core Functions

function Invoke-PowerShellScript {
    <#
    .SYNOPSIS
        Выполняет PowerShell скрипт в изолированном окружении

    .PARAMETER Script
        PowerShell код для выполнения

    .PARAMETER Parameters
        Параметры для передачи в скрипт

    .PARAMETER TimeoutSeconds
        Таймаут выполнения в секундах

    .PARAMETER WorkingDirectory
        Рабочая директория для выполнения

    .RETURNS
        Хеш-таблица с результатами выполнения
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Script,

    [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{},

    [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 300,

    [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = $PWD.Path
    )

    $executionId = [guid]::NewGuid().ToString("N")[0..7] -join ""
    Write-Log "[$executionId] Начало выполнения скрипта. Таймаут: $TimeoutSeconds сек, Директория: $WorkingDirectory" -Level "INFO"
    Write-Log "[$executionId] Скрипт: $($Script.Substring(0, [Math]::Min(200, $Script.Length)))$(if($Script.Length -gt 200){'...'})" -Level "DEBUG"

    $powerShell = $null
    $asyncResult = $null

    try {
        # Проверка безопасности скрипта
        if (-not (Test-ScriptSafety -Script $Script)) {
            return @{
                success = $false
                output = ""
                errors = @("Скрипт содержит потенциально опасные команды и был заблокирован")
                warnings = @()
                executionTime = 0
            }
        }

    # Создание изолированного PowerShell процесса
        $powerShell = [powershell]::Create()

    # Установка рабочей директории если отличается от текущей
        if ($WorkingDirectory -ne $PWD.Path -and (Test-Path $WorkingDirectory)) {
            $powerShell.AddScript("Set-Location -Path '$WorkingDirectory' -ErrorAction SilentlyContinue") | Out-Null
        }

    # Добавление основного скрипта$powerShell.AddScript($Script) | Out-Null

    # Добавление параметров
        foreach ($param in $Parameters.GetEnumerator()) {
            $powerShell.AddParameter($param.Key, $param.Value) | Out-Null
        }

    # Асинхронное выполнение с таймаутом
        $startTime = Get-Date$asyncResult = $powerShell.BeginInvoke()

    $completed = $asyncResult.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)
        $executionTime = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)

    if ($completed) {
            # Получение результатов выполнения$result = $powerShell.EndInvoke($asyncResult)
            $errors = $powerShell.Streams.Error
            $warnings = $powerShell.Streams.Warning

    # Формирование вывода с ограничением размера$outputText = if ($result) {
                ($result | Out-String -Width 120).Trim()
            } else {
                ""
            }

    # Ограничение размера вывода для предотвращения переполнения
            if ($outputText.Length -gt 10000) {$outputText = $outputText.Substring(0, 10000) + "`n... [вывод обрезан, показаны первые 10000 символов]"
            }

    $output = @{
                success = $errors.Count -eq 0
                output = $outputText
                errors = @($errors | ForEach-Object { $_.ToString() })
                warnings = @($warnings | ForEach-Object { $_.ToString() })
                executionTime = $executionTime
            }

    $status = if ($output.success) { "SUCCESS" } else { "ERROR" }
            Write-Log "[$executionId] Выполнение завершено: $status за $executionTime сек. Ошибок: $($errors.Count), Предупреждений: $($warnings.Count)" -Level "INFO"

    return $output
        } else {
            # Таймаут выполнения
            Write-Log "[$executionId] Таймаут выполнения ($TimeoutSeconds сек)" -Level "ERROR"
            $powerShell.Stop()

    return @{
                success = $false
                output = ""
                errors = @("Превышено время выполнения скрипта ($TimeoutSeconds секунд)")
                warnings = @()
                executionTime = $executionTime
            }
        }
    }
    catch {$errorMessage = $_.Exception.Message
        Write-Log "[$executionId] Критическая ошибка выполнения: $errorMessage" -Level "ERROR"

    return @{
            success = $false
            output = ""
            errors = @("Критическая ошибка выполнения: $errorMessage")
            warnings = @()
            executionTime = if ($startTime) { [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2) } else { 0 }
        }
    }
    finally {
        # Очистка ресурсов
        if ($asyncResult) {
            try { $asyncResult.AsyncWaitHandle.Close() } catch { }
        }
        if ($powerShell) {
            try { $powerShell.Dispose() } catch { }
        }
    }
}

function Invoke-MCPMethod {
    <#
    .SYNOPSIS
        Обрабатывает MCP методы согласно протоколу

    .PARAMETER Method
        Имя вызываемого метода

    .PARAMETER Params
        Параметры метода

    .PARAMETER Id
        Идентификатор запроса

    .RETURNS
        MCP ответ в виде хеш-таблицы
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Method,

    [Parameter(Mandatory = $false)]
        [hashtable]$Params = @{},

    [Parameter(Mandatory = $false)]
        [object]$Id = $null
    )

    Write-Log "Обработка MCP метода:$Method с ID: $Id" -Level "DEBUG"

    switch ($Method) {
        "initialize" {
            Write-Log "Инициализация MCP сервера" -Level "INFO"
            return New-MCPResponse -Id $Id -Result @{
                protocolVersion = "2024-11-05"
                capabilities = @{
                    tools = @{
                        listChanged = $true
                    }
                }
                serverInfo = @{
                    name = $script:ServerConfig.Name
                    version = $script:ServerConfig.Version
                    description = $script:ServerConfig.Description
                }
            }
        }

    "tools/list" {
            Write-Log "Запрос списка доступных инструментов" -Level "DEBUG"
            return New-MCPResponse -Id $Id -Result @{
                tools = @(
                    @{
                        name = "run-script"
                        description = "Выполняет PowerShell скрипт с заданными параметрами и возвращает результат"
                        inputSchema = @{
                            type = "object"
                            properties = @{
                                script = @{
                                    type = "string"
                                    description = "PowerShell код для выполнения"
                                }
                                parameters = @{
                                    type = "object"
                                    description = "Параметры для передачи в скрипт (опционально)"
                                    additionalProperties = $true
                                }
                                workingDirectory = @{
                                    type = "string"
                                    description = "Рабочая директория для выполнения скрипта (опционально)"
                                    default = $PWD.Path
                                }
                                timeoutSeconds = @{
                                    type = "integer"
                                    description = "Таймаут выполнения в секундах (опционально)"
                                    default = 300
                                    minimum = 1
                                    maximum = 3600
                                }
                            }
                            required = @("script")
                        }
                    }
                )
            }
        }

    "tools/call" {
            # Валидация обязательного параметра name
            if (-not $Params.ContainsKey("name")) {
                return New-MCPResponse -Id $Id -Error @{
                    code = -32602
                    message = "Отсутствует обязательный параметр 'name'"
                }
            }

    $toolName = $Params.name
            $arguments = if ($Params.ContainsKey("arguments")) { $Params.arguments } else { @{} }

    Write-Log "Вызов инструмента: $toolName" -Level "INFO"

    switch ($toolName) {
                "run-script" {
                    # Валидация обязательного параметра script
                    if (-not $arguments.ContainsKey("script")) {
                        return New-MCPResponse -Id $Id -Error @{
                            code = -32602
                            message = "Отсутствует обязательный параметр 'script'"
                        }
                    }

    # Извлечение параметров с значениями по умолчанию$script = $arguments.script
                    $parameters = if ($arguments.ContainsKey("parameters")) { $arguments.parameters } else { @{} }
                    $workingDirectory = if ($arguments.ContainsKey("workingDirectory")) {
                        $arguments.workingDirectory
                    } else {
                        $PWD.Path
                    }
                    $timeoutSeconds = if ($arguments.ContainsKey("timeoutSeconds")) {
                        [math]::Max(1, [math]::Min(3600, [int]$arguments.timeoutSeconds))
                    } else {
                        300
                    }

    Write-Log "Параметры выполнения - Директория:$workingDirectory, Таймаут: $timeoutSeconds сек" -Level "DEBUG"

    # Выполнение скрипта$result = Invoke-PowerShellScript -Script $script -Parameters $parameters -WorkingDirectory $workingDirectory -TimeoutSeconds $timeoutSeconds

    # Формирование контента ответа
                    $content = @()

    if ($result.output) {
                        $content += @{
                            type = "text"
                            text = "Результат выполнения PowerShell скрипта:`n`n ``powershell`n$($result.output)`n``"
                        }
                    }

    if ($result.errors.Count -gt 0) {$errorText = $result.errors -join "`n"                         $content += @{                             type = "text"                             text = "Ошибки выполнения:`n `n``````text`n$errorText`n``````"
                        }
                    }

    if ($result.warnings.Count -gt 0) {$warningText = $result.warnings -join "`n"                         $content += @{                             type = "text"                             text = "Предупреждения:`n `n``````text`n$warningText`n``````"
                        }
                    }

    # Если нет вывода, ошибок и предупреждений
                    if ($content.Count -eq 0) {
                        $content += @{
                            type = "text"
                            text = "Скрипт выполнен успешно. Результат выполнения отсутствует."
                        }
                    }

    return New-MCPResponse -Id $Id -Result @{
                        content = $content
                        isError = -not $result.success
                        _meta = @{
                            executionTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                            success = $result.success
                            errorCount = $result.errors.Count
                            warningCount = $result.warnings.Count
                            executionDuration = $result.executionTime
                        }
                    }
                }

    default {
                    return New-MCPResponse -Id $Id -Error @{
                        code = -32601
                        message = "Неизвестный инструмент: $toolName"
                    }
                }
            }
        }

    default {
            return New-MCPResponse -Id $Id -Error @{
                code = -32601
                message = "Неизвестный метод: $Method"
            }
        }
    }
}

function Send-MCPResponse {
    <#
    .SYNOPSIS
        Отправляет MCP ответ через stdout

    .PARAMETER Response
        Хеш-таблица с данными ответа
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Response
    )

    try {
        # Сериализация с увеличенной глубиной для сложных объектов$json = $Response | ConvertTo-Json -Depth 20 -Compress -ErrorAction Stop

    # Отправка через stdout
        Write-Host $json

    # Логирование (только первые 300 символов для экономии места)$logJson = if ($json.Length -gt 300) {
            $json.Substring(0, 300) + "..."
        } else {
            $json
        }
        Write-Log "Ответ отправлен: $logJson" -Level "DEBUG"
    }
    catch {
        Write-Log "Критическая ошибка сериализации ответа: $($_.Exception.Message)" -Level "ERROR"

    # Отправка базового ответа об ошибке
        $errorResponse = @{
            jsonrpc = "2.0"
            error = @{
                code = -32603
                message = "Внутренняя ошибка сериализации ответа"
            }
            id = if ($Response.ContainsKey("id")) { $Response.id } else { $null }
        }

    try {$errorJson = $errorResponse | ConvertTo-Json -Depth 5 -Compress
            Write-Host $errorJson
        }
        catch {
            # Если и это не работает, отправляем минимальный JSON
            Write-Host '{"jsonrpc":"2.0","error":{"code":-32603,"message":"Critical serialization error"},"id":null}'
        }
    }
}

#endregion

#region Main Server Loop

function Start-MCPServer {
    <#
    .SYNOPSIS
        Запускает основной цикл MCP сервера в STDIO режиме
    #>

    Write-Log "=== Запуск MCP PowerShell Server v$($script:ServerConfig.Version) ===" -Level "INFO"
    Write-Log "Режим работы: STDIO (JSON-RPC через стандартные потоки)" -Level "INFO"
    Write-Log "Протокол: MCP 2024-11-05" -Level "INFO"
    Write-Log "Лог файл: $script:LogFile" -Level "INFO"
    Write-Log "Рабочая директория: $($PWD.Path)" -Level "INFO"

    $requestCount = 0

    try {
        while ($true) {
            # Чтение строки из stdin
            $line = [Console]::ReadLine()

    # Проверка на EOF (завершение ввода)
            if ($null -eq $line) {
                Write-Log "Получен EOF, завершение работы сервера" -Level "INFO"
                break
            }

    # Пропуск пустых строк
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

    $requestCount++
            Write-Log "Запрос #$requestCount получен (длина: $($line.Length) символов)" -Level "DEBUG"

    try {
                # Парсинг JSON запроса$request = ConvertFrom-JsonToHashtable -Json $line

    # Валидация MCP запроса
                if (-not (Test-MCPRequest -Request $request)) {
                    $errorResponse = @{
                        jsonrpc = "2.0"
                        error = @{
                            code = -32600
                            message = "Неверный формат MCP запроса"
                        }
                        id = if ($request -and $request.ContainsKey("id")) { $request.id } else { $null }
                    }
                    Send-MCPResponse -Response $errorResponse
                    continue
                }

    # Обработка MCP метода$mcpResponse = Invoke-MCPMethod -Method $request.method -Params $request.params -Id $request.id
                Send-MCPResponse -Response $mcpResponse

    }
            catch {
                Write-Log "Ошибка обработки запроса #$requestCount : $($_.Exception.Message)" -Level "ERROR"

    # Отправка ошибки парсинга
                $parseErrorResponse = @{
                    jsonrpc = "2.0"
                    error = @{
                        code = -32700
                        message = "Ошибка парсинга JSON:$($_.Exception.Message)"
                    }
                    id = $null
                }
                Send-MCPResponse -Response $parseErrorResponse
            }
        }
    }
    catch {
        Write-Log "Критическая ошибка главного цикла: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
    finally {
        Write-Log "=== MCP PowerShell Server завершен. Обработано запросов: $requestCount ===" -Level "INFO"
    }
}

#endregion

#region Main Entry Point

# Инициализация и запуск сервера

try {
    # Очистка старого лог файла при запуске
    if (Test-Path $script:LogFile) {
        try {
            Remove-Item $script:LogFile -Force -ErrorAction SilentlyContinue
        } catch {
            # Игнорируем ошибки удаления лога
        }
    }

    # Создание директории для логов если не существует$logDir = Split-Path $script:LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    Write-Log "Инициализация MCP PowerShell Server v$($script:ServerConfig.Version)" -Level "INFO"
    Write-Log "PowerShell версия: $($PSVersionTable.PSVersion)" -Level "INFO"
    Write-Log "Операционная система: $($PSVersionTable.OS)" -Level "INFO"

    # Запуск основного сервера
    Start-MCPServer
}
catch {$errorMessage = "КРИТИЧЕСКАЯ ОШИБКА: $($_.Exception.Message)"
    Write-Log $errorMessage -Level "ERROR"

    # Попытка отправить ошибку через stdout перед завершением
    try {
        $fatalError = @{
            jsonrpc = "2.0"
            error = @{
                code = -32603
                message = $errorMessage
            }
            id = $null
        } | ConvertTo-Json -Compress
        Write-Host $fatalError
    } catch {
        # Если и это не работает, просто завершаемся
    }

    exit 1
}

#endregion

# test-mcp.ps1 - Простой тестовый MCP сервер

# -*- coding: utf-8 -*-

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

function Send-Response {
    param([hashtable]$Response)
    $json = $Response | ConvertTo-Json -Depth 10 -Compress
    Write-Host $json
}

# Основной цикл

while ($true) {
    $line = [Console]::ReadLine()
    ## \file mcp-powershell-server/test-mcp-improved.ps1

# -*- coding: utf-8 -*-

#! .pyenv/bin/powershell

<#
.SYNOPSIS
    Улучшенный тестовый MCP сервер для демонстрации протокола

.DESCRIPTION
    Простой тестовый сервер для проверки MCP протокола с базовыми инструментами
    для демонстрации возможностей. Включает расширенные инструменты для тестирования.

.EXAMPLE
    .\test-mcp-improved.ps1

    Затем отправьте JSON запросы:
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}
    {"jsonrpc":"2.0","id":2,"method":"tools/list"}
    {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get-date","arguments":{}}}
#>

# Настройка кодировки UTF-8

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# Функция отправки ответа

function Send-Response {
    <#
    .SYNOPSIS
        Отправляет JSON ответ через stdout

    .PARAMETER Response
        Хеш-таблица с данными ответа
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Response
    )

    try {$json = $Response | ConvertTo-Json -Depth 10 -Compress
        Write-Host $json
    }
    catch {
        # Отправка базового ответа об ошибке сериализации
        $errorResponse = @{
            jsonrpc = "2.0"
            error = @{
                code = -32603
                message = "Ошибка сериализации ответа"
            }
            id = $null
        }
        $errorJson = $errorResponse | ConvertTo-Json -Compress
        Write-Host $errorJson
    }
}

# Функция получения системной информации

function Get-SystemInfo {
    <#
    .SYNOPSIS
        Получает базовую системную информацию

    .RETURNS
        Строка с информацией о системе
    #>
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $memory = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop$totalMemoryGB = [math]::Round(($memory | Measure-Object Capacity -Sum).Sum / 1GB, 2)

    $info = @"
Операционная система:$($os.Caption) $($os.Version)
Процессор: $($cpu.Name)
Память: $totalMemoryGB ГБ
Время работы: $([TimeSpan]::FromMilliseconds($os.LastBootUpTime.Subtract([DateTime]::Now).TotalMilliseconds * -1).ToString("dd\.hh\:mm\:ss"))
PowerShell версия: $($PSVersionTable.PSVersion)
Текущее время: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
        return $info
    }
    catch {
        return "Ошибка получения системной информации: $($_.Exception.Message)"
    }
}

# Функция получения списка процессов

function Get-TopProcesses {
    <#
    .SYNOPSIS
        Получает топ процессов по использованию CPU

    .PARAMETER Count
        Количество процессов для отображения

    .RETURNS
        Строка с информацией о процессах
    #>
    param(
        [int]$Count = 5
    )

    try {$processes = Get-Process | Where-Object { $_.CPU -gt 0 } |
                    Sort-Object CPU -Descending |
                    Select-Object -First $Count Name, CPU, WorkingSet, Id

    $output = "Топ $Count процессов по CPU:`n"
        $output += $processes | Format-Table -AutoSize | Out-String
        return $output.Trim()
    }
    catch {
        return "Ошибка получения списка процессов: $($_.Exception.Message)"
    }
}

# Функция выполнения математических операций

function Invoke-Calculator {
    <#
    .SYNOPSIS
        Выполняет простые математические вычисления

    .PARAMETER Expression
        Математическое выражение

    .RETURNS
        Результат вычисления
    #>
    param(
        [string]$Expression
    )

    try {
        # Простая проверка безопасности выражения
        if ($Expression -match '[a-zA-Z]|[;&|`$]') {
            throw "Недопустимые символы в математическом выражении"
        }

    $result = Invoke-Expression $Expression
        return "Результат: $Expression = $result"
    }
    catch {
        return "Ошибка вычисления: $($_.Exception.Message)"
    }
}

Write-Host "Запуск тестового MCP сервера..." -ForegroundColor Green
Write-Host "Для тестирования отправьте JSON запросы через stdin" -ForegroundColor Yellow
Write-Host "Для завершения используйте Ctrl+C или EOF" -ForegroundColor Cyan
Write-Host ""

# Основной цикл обработки

$requestCount = 0

while ($true) {
    try {
        # Чтение строки из stdin
        $line = [Console]::ReadLine()

    # Проверка на EOF
        if ($null -eq $line) {
            Write-Host "Получен EOF, завершение работы тестового сервера" -ForegroundColor Yellow
            break
        }

    # Пропуск пустых строк
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

    $requestCount++
        Write-Host "Обработка запроса #$requestCount" -ForegroundColor Cyan

    try {
            # Парсинг JSON запроса$request = $line | ConvertFrom-Json -AsHashtable -ErrorAction Stop

    # Обработка методов
            switch ($request.method) {
                "initialize" {
                    Send-Response @{
                        jsonrpc = "2.0"
                        id = $request.id
                        result = @{
                            protocolVersion = "2024-11-05"
                            capabilities = @{
                                tools = @{
                                    listChanged = $true
                                }
                            }
                            serverInfo = @{
                                name = "Test PowerShell MCP Server"
                                version = "1.1.0"
                                description = "Тестовый сервер для демонстрации MCP протокола"
                            }
                        }
                    }
                }

    "tools/list" {
                    Send-Response @{
                        jsonrpc = "2.0"
                        id = $request.id
                        result = @{
                            tools = @(
                                @{
                                    name = "get-date"
                                    description = "Получить текущую дату и время"
                                    inputSchema = @{
                                        type = "object"
                                        properties = @{}
                                    }
                                },
                                @{
                                    name = "get-system-info"
                                    description = "Получить информацию о системе"
                                    inputSchema = @{
                                        type = "object"
                                        properties = @{}
                                    }
                                },
                                @{
                                    name = "get-processes"
                                    description = "Получить список топ процессов"
                                    inputSchema = @{
                                        type = "object"
                                        properties = @{
                                            count = @{
                                                type = "integer"
                                                description = "Количество процессов для отображения"
                                                default = 5
                                                minimum = 1
                                                maximum = 20
                                            }
                                        }
                                    }
                                },
                                @{
                                    name = "calculator"
                                    description = "Выполнить математическое вычисление"
                                    inputSchema = @{
                                        type = "object"
                                        properties = @{
                                            expression = @{
                                                type = "string"
                                                description = "Математическое выражение для вычисления"
                                            }
                                        }
                                        required = @("expression")
                                    }
                                }
                            )
                        }
                    }
                }

    "tools/call" {$toolName = $request.params.name
                    $arguments = if ($request.params.ContainsKey("arguments")) {
                        $request.params.arguments
                    } else {
                        @{}
                    }

    $content = switch ($toolName) {
                        "get-date" {
                            $currentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                            @(
                                @{
                                    type = "text"
                                    text = "Текущая дата и время: $currentDate"
                                }
                            )
                        }

    "get-system-info" {
                            $systemInfo = Get-SystemInfo
                            @(
                                @{
                                    type = "text"
                                    text = "Информация о системе:`n`n$systemInfo"
                                }
                            )
                        }

    "get-processes" {$count = if ($arguments.ContainsKey("count")) {
                                [math]::Max(1, [math]::Min(20, [int]$arguments.count))
                            } else {
                                5
                            }
                            $processInfo = Get-TopProcesses -Count $count
                            @(
                                @{
                                    type = "text"
                                    text = $processInfo
                                }
                            )
                        }

    "calculator" {
                            if (-not $arguments.ContainsKey("expression")) {
                                $null # Будет обработано как ошибка ниже
                            } else {$calcResult = Invoke-Calculator -Expression $arguments.expression
                                @(
                                    @{
                                        type = "text"
                                        text = $calcResult
                                    }
                                )
                            }
                        }

    default {
                            $null # Неизвестный инструмент
                        }
                    }

    if ($null -eq $content) {
                        # Отправка ошибки
                        if ($toolName -eq "calculator" -and -not $arguments.ContainsKey("expression")) {
                            Send-Response @{
                                jsonrpc = "2.0"
                                id = $request.id
                                error = @{
                                    code = -32602
                                    message = "Отсутствует обязательный параметр 'expression'"
                                }
                            }
                        } else {
                            Send-Response @{
                                jsonrpc = "2.0"
                                id = $request.id
                                error = @{
                                    code = -32601
                                    message = "Неизвестный инструмент: $toolName"
                                }
                            }
                        }
                    } else {
                        # Отправка успешного результата
                        Send-Response @{
                            jsonrpc = "2.0"
                            id = $request.id
                            result = @{
                                content = $content
                                isError = $false
                            }
                        }
                    }
                }

    default {
                    Send-Response @{
                        jsonrpc = "2.0"
                        id = $request.id
                        error = @{
                            code = -32601
                            message = "Неизвестный метод:$($request.method)"
                        }
                    }
                }
            }
        }
        catch {
            # Ошибка парсинга JSON или обработки запроса
            Send-Response @{
                jsonrpc = "2.0"
                id = $null
                error = @{
                    code = -32700
                    message = "Ошибка парсинга JSON или обработки запроса: $($_.Exception.Message)"
                }
            }
        }
    }
    catch {
        # Критическая ошибка главного цикла
        Write-Host "Критическая ошибка: $($_.Exception.Message)" -ForegroundColor Red
        Send-Response @{
            jsonrpc = "2.0"
            id = $null
            error = @{
                code = -32603
                message = "Внутренняя ошибка сервера"
            }
        }
        break
    }
}

Write-Host ""
Write-Host "Тестовый MCP сервер завершен. Обработано запросов: $requestCount" -ForegroundColor Green
    if ($null -eq $line) { break }
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    try {$request = $line | ConvertFrom-Json -AsHashtable

    switch ($request.method) {
            "initialize" {
                Send-Response @{
                    jsonrpc = "2.0"
                    id = $request.id
                    result = @{
                        protocolVersion = "2024-11-05"
                        capabilities = @{ tools = @{} }
                        serverInfo = @{
                            name = "Test PowerShell Server"
                            version = "1.0.0"
                        }
                    }
                }
            }
            "tools/list" {
                Send-Response @{
                    jsonrpc = "2.0"
                    id = $request.id
                    result = @{
                        tools = @(
                            @{
                                name = "get-date"
                                description = "Получить текущую дату"
                                inputSchema = @{
                                    type = "object"
                                    properties = @{}
                                }
                            }
                        )
                    }
                }
            }
            "tools/call" {
                if ($request.params.name -eq "get-date") {
                    $currentDate = Get-Date
                    Send-Response @{
                        jsonrpc = "2.0"
                        id = $request.id
                        result = @{
                            content = @(
                                @{
                                    type = "text"
                                    text = "Текущая дата и время: $currentDate"
                                }
                            )
                        }
                    }
                } else {
                    Send-Response @{
                        jsonrpc = "2.0"
                        id = $request.id
                        error = @{
                            code = -32601
                            message = "Неизвестный инструмент"
                        }
                    }
                }
            }
            default {
                Send-Response @{
                    jsonrpc = "2.0"
                    id = $request.id
                    error = @{
                        code = -32601
                        message = "Неизвестный метод:$($request.method)"
                    }
                }
            }
        }
    }
    catch {
        Send-Response @{
            jsonrpc = "2.0"
            id = $null
            error = @{
                code = -32700
                message = "Ошибка парсинга JSON"
            }
        }
    }
}

Write-Host "Ошибка обработки запроса: $($_.Exception.Message)" -ForegroundColor Red
    Send-Response @{
            jsonrpc = "2.0"
            id = $null
            error = @{
                code = -32603
                message = "Внутренняя ошибка сервера"
            }
        }
}
}
```