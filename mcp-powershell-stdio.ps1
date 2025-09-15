# MCP PowerShell Server (STDIO версия)
# -*- coding: utf-8 -*-

# Функция конвертации JSON в хеш-таблицу для PowerShell 5.x
function ConvertFrom-JsonToHashtable {
    param([string]$Json)
    
    $obj = ConvertFrom-Json $Json
    
    function ConvertTo-Hashtable($obj) {
        $hash = @{}
        $obj.PSObject.Properties | ForEach-Object {
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

# Настройка кодировки для корректной работы с JSON
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# Логирование в файл (так как stdout используется для MCP)
$LogFile = Join-Path $env:TEMP "mcp-powershell-server.log"

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logMessage -Encoding UTF8
}

# Функция валидации MCP запроса
function Test-MCPRequest {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Request
    )
    
    if (-not $Request.ContainsKey("jsonrpc") -or $Request.jsonrpc -ne "2.0") {
        return $false
    }
    
    if (-not $Request.ContainsKey("method")) {
        return $false
    }
    
    return $true
}

# Функция создания MCP ответа
function New-MCPResponse {
    param(
        [Parameter(Mandatory=$false)]
        [object]$Id = $null,
        
        [Parameter(Mandatory=$false)]
        [object]$Result = $null,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$Error = $null
    )
    
    $response = @{
        jsonrpc = "2.0"
        id = $Id
    }
    
    if ($Error) {
        $response.error = $Error
    } else {
        $response.result = $Result
    }
    
    return $response
}

# Функция выполнения PowerShell скрипта
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
    
    try {
        Write-Log "Выполнение PowerShell скрипта: $($Script.Substring(0, [Math]::Min(100, $Script.Length)))" -Level "DEBUG"
        
        # Создание нового PowerShell процесса для изоляции
        $powerShell = [powershell]::Create()
        
        # Установка рабочей директории
        if ($WorkingDirectory -ne $PWD) {
            $powerShell.AddScript("Set-Location -Path '$WorkingDirectory'")
        }
        
        # Добавление основного скрипта
        $powerShell.AddScript($Script)
        
        # Добавление параметров
        foreach ($param in $Parameters.GetEnumerator()) {
            $powerShell.AddParameter($param.Key, $param.Value)
        }
        
        # Выполнение с таймаутом
        $asyncResult = $powerShell.BeginInvoke()
        
        if ($asyncResult.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
            $result = $powerShell.EndInvoke($asyncResult)
            $errors = $powerShell.Streams.Error
            
            # Формирование ответа
            $output = @{
                success = $true
                output = ($result | Out-String -Width 120).Trim()
                errors = @()
                warnings = @()
            }
            
            # Добавление ошибок если есть
            if ($errors.Count -gt 0) {
                $output.errors = @($errors | ForEach-Object { $_.ToString() })
                $output.success = $errors.Count -eq 0
            }
            
            # Добавление предупреждений
            if ($powerShell.Streams.Warning.Count -gt 0) {
                $output.warnings = @($powerShell.Streams.Warning | ForEach-Object { $_.ToString() })
            }
            
            return $output
        } else {
            # Таймаут
            $powerShell.Stop()
            throw "Превышено время выполнения скрипта ($TimeoutSeconds секунд)"
        }
    }
    catch {
        Write-Log "Ошибка выполнения скрипта: $($_.Exception.Message)" -Level "ERROR"
        return @{
            success = $false
            output = ""
            errors = @($_.Exception.Message)
            warnings = @()
        }
    }
    finally {
        if ($powerShell) {
            $powerShell.Dispose()
        }
    }
}

# Обработчик MCP методов
function Invoke-MCPMethod {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Method,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$Params = @{},
        
        [Parameter(Mandatory=$false)]
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
                    name = "PowerShell Script Runner"
                    version = "1.0.0"
                    description = "Выполняет PowerShell скрипты через MCP"
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
                                    description = "PowerShell скрипт для выполнения"
                                }
                                parameters = @{
                                    type = "object"
                                    description = "Параметры для скрипта (опционально)"
                                    additionalProperties = $true
                                }
                                workingDirectory = @{
                                    type = "string"
                                    description = "Рабочая директория для выполнения (опционально)"
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
                    
                    $script = $arguments.script
                    $parameters = if ($arguments.ContainsKey("parameters")) { $arguments.parameters } else { @{} }
                    $workingDirectory = if ($arguments.ContainsKey("workingDirectory")) { $arguments.workingDirectory } else { $PWD.Path }
                    $timeoutSeconds = if ($arguments.ContainsKey("timeoutSeconds")) { $arguments.timeoutSeconds } else { 300 }
                    
                    Write-Log "Выполнение скрипта в директории: $workingDirectory" -Level "DEBUG"
                    
                    # Выполнение скрипта
                    $result = Invoke-PowerShellScript -Script $script -Parameters $parameters -WorkingDirectory $workingDirectory -TimeoutSeconds $timeoutSeconds
                    
                    # Формирование ответа
                    $content = @()
                    $newLine = [Environment]::NewLine
                    $codeBlock = '```'
                    
                    if ($result.output) {
                        $outputText = "Вывод команды:" + $newLine + $codeBlock + $newLine + $result.output + $newLine + $codeBlock
                        $content += @{
                            type = "text"
                            text = $outputText
                        }
                    }
                    
                    if ($result.errors.Count -gt 0) {
                        $errorText = $result.errors -join $newLine
                        $errorMessage = "Ошибки:" + $newLine + $codeBlock + $newLine + $errorText + $newLine + $codeBlock
                        $content += @{
                            type = "text"
                            text = $errorMessage
                        }
                    }
                    
                    if ($result.warnings.Count -gt 0) {
                        $warningText = $result.warnings -join $newLine
                        $warningMessage = "Предупреждения:" + $newLine + $codeBlock + $newLine + $warningText + $newLine + $codeBlock
                        $content += @{
                            type = "text"
                            text = $warningMessage
                        }
                    }
                    
                    if ($content.Count -eq 0) {
                        $content += @{
                            type = "text"
                            text = "Команда выполнена успешно (нет вывода)"
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

# Функция отправки ответа
function Send-MCPResponse {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Response
    )
    
    try {
        $json = $Response | ConvertTo-Json -Depth 20 -Compress
        Write-Host $json
        Write-Log "Отправлен ответ: $($json.Substring(0, [Math]::Min(200, $json.Length)))" -Level "DEBUG"
    }
    catch {
        Write-Log "Ошибка отправки ответа: $($_.Exception.Message)" -Level "ERROR"
        $errorResponse = @{
            jsonrpc = "2.0"
            error = @{
                code = -32603
                message = "Внутренняя ошибка сериализации"
            }
            id = $null
        }
        $errorJson = $errorResponse | ConvertTo-Json -Depth 5 -Compress
        Write-Host $errorJson
    }
}

# Основной цикл обработки
function Start-MCPServer {
    Write-Log "Запуск MCP PowerShell сервера (STDIO режим)" -Level "INFO"
    Write-Log "Лог-файл: $LogFile" -Level "INFO"
    
    try {
        while ($true) {
            # Чтение строки из stdin
            $line = [Console]::ReadLine()
            
            if ($null -eq $line) {
                Write-Log "Получен EOF, завершение работы" -Level "INFO"
                break
            }
            
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            
            Write-Log "Получен запрос: $line" -Level "DEBUG"
            
            try {
                # Парсинг JSON
                $request = ConvertFrom-JsonToHashtable -Json $line
                
                # Валидация MCP запроса
                if (-not (Test-MCPRequest -Request $request)) {
                    $errorResponse = @{
                        jsonrpc = "2.0"
                        error = @{
                            code = -32600
                            message = "Неверный MCP запрос"
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
                Write-Log "Ошибка обработки запроса: $($_.Exception.Message)" -Level "ERROR"
                $errorResponse = @{
                    jsonrpc = "2.0"
                    error = @{
                        code = -32700
                        message = "Ошибка парсинга JSON: $($_.Exception.Message)"
                    }
                    id = $null
                }
                Send-MCPResponse -Response $errorResponse
            }
        }
    }
    catch {
        Write-Log "Критическая ошибка: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
    finally {
        Write-Log "MCP PowerShell сервер завершён" -Level "INFO"
    }
}

# Инициализация и запуск
try {
    # Очистка старого лог-файла
    if (Test-Path $LogFile) {
        Remove-Item $LogFile -Force
    }
    
    Write-Log "Инициализация MCP PowerShell сервера (STDIO версия) v1.0.0" -Level "INFO"
    Start-MCPServer
}
catch {
    Write-Log "Фатальная ошибка: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}