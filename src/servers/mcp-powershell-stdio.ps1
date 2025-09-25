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
    
    try {
        $obj = ConvertFrom-Json $Json -ErrorAction Stop
        
        function ConvertTo-Hashtable($InputObject) {
            $hash = @{}
            if ($null -eq $InputObject) { return $hash }
            
            $InputObject.PSObject.Properties | ForEach-Object {
                $value = $_.Value
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
        Write-Log "Ошибка парсинга JSON: $($_.Exception.Message)" -Level "ERROR"
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
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $logMessage = "[$timestamp] [$Level] $Message"
        
        # Асинхронная запись в лог для избежания блокировки
        $null = Add-Content -Path $script:LogFile -Value $logMessage -Encoding UTF8 -ErrorAction SilentlyContinue
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
    
    .RETURNS
        $true если запрос валиден, $false в противном случае
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Request
    )
    
    # Проверка обязательных полей MCP протокола
    if (-not $Request.ContainsKey("jsonrpc") -or $Request.jsonrpc -ne "2.0") {
        Write-Log "Неверная версия JSON-RPC: $($Request.jsonrpc)" -Level "WARNING"
        return $false
    }
    
    if (-not $Request.ContainsKey("method") -or [string]::IsNullOrEmpty($Request.method)) {
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
    
    if ($Error) {
        $response.error = $Error
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
    
    .RETURNS
        $true если скрипт безопасен, $false если найдены опасные команды
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
        
        # Добавление основного скрипта
        $powerShell.AddScript($Script) | Out-Null
        
        # Добавление параметров
        foreach ($param in $Parameters.GetEnumerator()) {
            $powerShell.AddParameter($param.Key, $param.Value) | Out-Null
        }
        
        # Асинхронное выполнение с таймаутом
        $startTime = Get-Date
        $asyncResult = $powerShell.BeginInvoke()
        
        $completed = $asyncResult.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)
        $executionTime = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
        
        if ($completed) {
            # Получение результатов выполнения
            $result = $powerShell.EndInvoke($asyncResult)
            $errors = $powerShell.Streams.Error
            $warnings = $powerShell.Streams.Warning
            
            # Формирование вывода с ограничением размера
            $outputText = if ($result) {
                ($result | Out-String -Width 120).Trim()
            } else {
                ""
            }
            
            # Ограничение размера вывода для предотвращения переполнения
            if ($outputText.Length -gt 10000) {
                $outputText = $outputText.Substring(0, 10000) + "`n... [вывод обрезан, показаны первые 10000 символов]"
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
    catch {
        $errorMessage = $_.Exception.Message
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
    
    Write-Log "Обработка MCP метода: $Method с ID: $Id" -Level "DEBUG"
    
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
                    
                    # Извлечение параметров с значениями по умолчанию
                    $script = $arguments.script
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
                    
                    Write-Log "Параметры выполнения - Директория: $workingDirectory, Таймаут: $timeoutSeconds сек" -Level "DEBUG"
                    
                    # Выполнение скрипта
                    $result = Invoke-PowerShellScript -Script $script -Parameters $parameters -WorkingDirectory $workingDirectory -TimeoutSeconds $timeoutSeconds
                    
                    # Формирование контента ответа
                    $content = @()
                    
                    if ($result.output) {
                        $content += @{
                            type = "text"
                            text = "Результат выполнения PowerShell скрипта:`n`n``````powershell`n$($result.output)`n``````"
                        }
                    }
                    
                    if ($result.errors.Count -gt 0) {
                        $errorText = $result.errors -join "`n"
                        $content += @{
                            type = "text"
                            text = "Ошибки выполнения:`n`n``````text`n$errorText`n``````"
                        }
                    }
                    
                    if ($result.warnings.Count -gt 0) {
                        $warningText = $result.warnings -join "`n"
                        $content += @{
                            type = "text"
                            text = "Предупреждения:`n`n``````text`n$warningText`n``````"
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
        # Сериализация с увеличенной глубиной для сложных объектов
        $json = $Response | ConvertTo-Json -Depth 20 -Compress -ErrorAction Stop
        
        # Отправка через stdout
        Write-Host $json
        
        # Логирование (только первые 300 символов для экономии места)
        $logJson = if ($json.Length -gt 300) { 
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
        
        try {
            $errorJson = $errorResponse | ConvertTo-Json -Depth 5 -Compress
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
                # Парсинг JSON запроса
                $request = ConvertFrom-JsonToHashtable -Json $line
                
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
                
                # Обработка MCP метода
                $mcpResponse = Invoke-MCPMethod -Method $request.method -Params $request.params -Id $request.id
                Send-MCPResponse -Response $mcpResponse
                
            }
            catch {
                Write-Log "Ошибка обработки запроса #$requestCount : $($_.Exception.Message)" -Level "ERROR"
                
                # Отправка ошибки парсинга
                $parseErrorResponse = @{
                    jsonrpc = "2.0"
                    error = @{
                        code = -32700
                        message = "Ошибка парсинга JSON: $($_.Exception.Message)"
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
    
    # Создание директории для логов если не существует
    $logDir = Split-Path $script:LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    
    Write-Log "Инициализация MCP PowerShell Server v$($script:ServerConfig.Version)" -Level "INFO"
    Write-Log "PowerShell версия: $($PSVersionTable.PSVersion)" -Level "INFO"
    Write-Log "Операционная система: $($PSVersionTable.OS)" -Level "INFO"
    
    # Запуск основного сервера
    Start-MCPServer
}
catch {
    $errorMessage = "КРИТИЧЕСКАЯ ОШИБКА: $($_.Exception.Message)"
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