## \file mcp-powershell-server/mcp-powershell-stdio.ps1

<#
.SYNOPSIS
    Улучшенный MCP PowerShell Server (STDIO версия)

.DESCRIPTION
    Сервер MCP для выполнения PowerShell скриптов через протокол JSON-RPC 
    с использованием стандартных потоков ввода-вывода.

.NOTES
    Version: 1.1.1
    Author: MCP PowerShell Server Team
    Protocol: MCP 2024-11-05
#>

#Requires -Version 7.0

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

#region Configuration Loading

$ConfigFileName = '../config/mcp-powershell-stdio.config.json'

function Load-ServerConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    $ScriptDir = Split-Path -Parent $PSCommandPath
    $FullPath = Join-Path -Path $ScriptDir -ChildPath $Path
    
    $DefaultConfig = @{
        Name = 'PowerShell Script Runner'
        Version = '1.1.1'
        Description = 'Выполняет PowerShell скрипты через MCP протокол'
        MaxExecutionTime = 300
        LogLevel = 'INFO'
        Security = @{
            EnableScriptValidation = $false
            BlockDangerousCommands = $false
            MaxOutputSize = 10000
            MaxScriptLength = 50000
        }
        Logging = @{
            LogFile = 'mcp-powershell-server.log'
            DetailedLogging = $false
        }
    }
    
    if (-not (Test-Path $FullPath)) {
        Write-Error "Файл конфигурации не найден: $FullPath. Используется конфигурация по умолчанию."
        return $DefaultConfig
    }
    
    try {
        $ConfigJson = Get-Content -Path $FullPath -Raw | ConvertFrom-Json -ErrorAction Stop
        
        if ($ConfigJson.PSObject.Properties.Name -contains 'ServerConfig') {
            $LoadedConfig = $ConfigJson.ServerConfig
        } else {
            $LoadedConfig = $ConfigJson
        }
        
        function ConvertTo-Hashtable {
            param($InputObject)
            
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
        
        $ConfigHash = ConvertTo-Hashtable -InputObject $LoadedConfig
        
        foreach ($key in $DefaultConfig.Keys) {
            if (-not $ConfigHash.ContainsKey($key)) {
                $ConfigHash[$key] = $DefaultConfig[$key]
            }
        }
        
        Write-Error "Конфигурация загружена из: $FullPath"
        return $ConfigHash
        
    }
    catch {
        Write-Error "Ошибка чтения конфигурации: $($_.Exception.Message). Используется конфигурация по умолчанию."
        return $DefaultConfig
    }
}

$script:ServerConfig = Load-ServerConfig -Path $ConfigFileName
$script:LogFile = Join-Path $env:TEMP $script:ServerConfig.Logging.LogFile

$script:RestrictedCommands = if ($script:ServerConfig.Security.RestrictedCommands) {
    $script:ServerConfig.Security.RestrictedCommands
} else {
    @(
        'Remove-Item.*C:\\Windows',
        'Remove-Item.*C:\\Program Files',
        'Format-Volume',
        'Stop-Computer',
        'Restart-Computer',
        'Stop-Process',
        'Stop-Service',
        'Invoke-Expression',
        'iex',
        'New-ItemProperty.*HKLM',
        'Set-ItemProperty.*HKLM',
        'Remove-ItemProperty.*HKLM'
    )
}

#endregion

#region Utility Functions

function ConvertFrom-JsonToHashtable {
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
        Write-Log "Ошибка парсинга JSON: $($_.Exception.Message)" -Level 'ERROR'
        throw
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )
    
    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $logMessage = "[$timestamp] [$Level] $Message"
        
        $null = Add-Content -Path $script:LogFile -Value $logMessage -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch { }
}

function Test-MCPRequest {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Request
    )
    
    if (-not $Request.ContainsKey('jsonrpc') -or $Request.jsonrpc -ne '2.0') {
        Write-Log "Неверная версия JSON-RPC: $($Request.jsonrpc)" -Level 'WARNING'
        return $false
    }
    
    if (-not $Request.ContainsKey('method') -or [string]::IsNullOrEmpty($Request.method)) {
        Write-Log 'Отсутствует или пустой метод' -Level 'WARNING'
        return $false
    }
    
    return $true
}

function New-MCPResponse {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Id = $null,
        
        [Parameter(Mandatory = $false)]
        [object]$Result = $null,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Error = $null
    )
    
    $response = @{
        jsonrpc = '2.0'
        id = $Id
    }
    
    if ($Error) {
        $response.error = $Error
        Write-Log "Отправка ошибки: $($Error.message)" -Level 'ERROR'
    } else {
        $response.result = $Result
        Write-Log 'Отправка результата для метода' -Level 'DEBUG'
    }
    
    return $response
}

function Test-ScriptSafety {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Script
    )
    
    if (-not $script:ServerConfig.Security.BlockDangerousCommands) {
        return $true
    }
    
    foreach ($restrictedCmd in $script:RestrictedCommands) {
        if ($Script -match $restrictedCmd) {
            Write-Log "Обнаружена потенциально опасная команда: $restrictedCmd" -Level 'WARNING'
            return $false
        }
    }
    
    return $true
}

#endregion

#region Core Functions

function Invoke-PowerShellScript {
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
    
    $executionId = [guid]::NewGuid().ToString('N')[0..7] -join ''
    Write-Log "[$executionId] Начало выполнения скрипта. Таймаут: $TimeoutSeconds сек" -Level 'INFO'
    
    $powerShell = $null
    $asyncResult = $null
    
    try {
        if (-not (Test-ScriptSafety -Script $Script)) {
            return @{
                success = $false
                output = ''
                errors = @('Скрипт содержит потенциально опасные команды и был заблокирован')
                warnings = @()
                executionTime = 0
            }
        }
        
        $powerShell = [powershell]::Create()
        
        if ($WorkingDirectory -ne $PWD.Path -and (Test-Path $WorkingDirectory)) {
            $powerShell.AddScript("Set-Location -Path '$WorkingDirectory' -ErrorAction SilentlyContinue") | Out-Null
        }
        
        $powerShell.AddScript($Script) | Out-Null
        
        foreach ($param in $Parameters.GetEnumerator()) {
            $powerShell.AddParameter($param.Key, $param.Value) | Out-Null
        }
        
        $startTime = Get-Date
        $asyncResult = $powerShell.BeginInvoke()
        
        $completed = $asyncResult.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)
        $executionTime = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
        
        if ($completed) {
            $result = $powerShell.EndInvoke($asyncResult)
            $errors = $powerShell.Streams.Error
            $warnings = $powerShell.Streams.Warning
            
            $outputText = if ($result) {
                ($result | Out-String -Width 120).Trim()
            } else {
                ''
            }
            
            $maxSize = $script:ServerConfig.Security.MaxOutputSize
            if ($outputText.Length -gt $maxSize) {
                $outputText = $outputText.Substring(0, $maxSize) + "`n... [вывод обрезан, показаны первые $maxSize символов]"
            }
            
            $output = @{
                success = $errors.Count -eq 0
                output = $outputText
                errors = @($errors | ForEach-Object { $_.ToString() })
                warnings = @($warnings | ForEach-Object { $_.ToString() })
                executionTime = $executionTime
            }
            
            $status = if ($output.success) { 'SUCCESS' } else { 'ERROR' }
            Write-Log "[$executionId] Выполнение завершено: $status за $executionTime сек" -Level 'INFO'
            
            return $output
        } else {
            Write-Log "[$executionId] Таймаут выполнения ($TimeoutSeconds сек)" -Level 'ERROR'
            $powerShell.Stop()
            
            return @{
                success = $false
                output = ''
                errors = @("Превышено время выполнения скрипта ($TimeoutSeconds секунд)")
                warnings = @()
                executionTime = $executionTime
            }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "[$executionId] Критическая ошибка выполнения: $errorMessage" -Level 'ERROR'
        
        return @{
            success = $false
            output = ''
            errors = @("Критическая ошибка выполнения: $errorMessage")
            warnings = @()
            executionTime = if ($startTime) { [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2) } else { 0 }
        }
    }
    finally {
        if ($asyncResult) {
            try { $asyncResult.AsyncWaitHandle.Close() } catch { }
        }
        if ($powerShell) {
            try { $powerShell.Dispose() } catch { }
        }
    }
}

function Invoke-MCPMethod {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Method,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Params = @{},
        
        [Parameter(Mandatory = $false)]
        [object]$Id = $null
    )
    
    Write-Log "Обработка MCP метода: $Method с ID: $Id" -Level 'DEBUG'
    
    switch ($Method) {
        'initialize' {
            Write-Log 'Инициализация MCP сервера' -Level 'INFO'
            return New-MCPResponse -Id $Id -Result @{
                protocolVersion = '2024-11-05'
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
        
        'tools/list' {
            Write-Log 'Запрос списка доступных инструментов' -Level 'DEBUG'
            return New-MCPResponse -Id $Id -Result @{
                tools = @(
                    @{
                        name = 'run-script'
                        description = 'Выполняет PowerShell скрипт с заданными параметрами и возвращает результат'
                        inputSchema = @{
                            type = 'object'
                            properties = @{
                                script = @{
                                    type = 'string'
                                    description = 'PowerShell код для выполнения'
                                }
                                parameters = @{
                                    type = 'object'
                                    description = 'Параметры для передачи в скрипт (опционально)'
                                    additionalProperties = $true
                                }
                                workingDirectory = @{
                                    type = 'string'
                                    description = 'Рабочая директория для выполнения скрипта (опционально)'
                                    default = $PWD.Path
                                }
                                timeoutSeconds = @{
                                    type = 'integer'
                                    description = 'Таймаут выполнения в секундах (опционально)'
                                    default = $script:ServerConfig.MaxExecutionTime
                                    minimum = 1
                                    maximum = 3600
                                }
                            }
                            required = @('script')
                        }
                    }
                )
            }
        }
        
        'tools/call' {
            if (-not $Params.ContainsKey('name')) {
                return New-MCPResponse -Id $Id -Error @{
                    code = -32602
                    message = "Отсутствует обязательный параметр 'name'"
                }
            }
            
            $toolName = $Params.name
            $arguments = if ($Params.ContainsKey('arguments')) { $Params.arguments } else { @{} }
            
            Write-Log "Вызов инструмента: $toolName" -Level 'INFO'
            
            switch ($toolName) {
                'run-script' {
                    if (-not $arguments.ContainsKey('script')) {
                        return New-MCPResponse -Id $Id -Error @{
                            code = -32602
                            message = "Отсутствует обязательный параметр 'script'"
                        }
                    }
                    
                    $script = $arguments.script
                    $parameters = if ($arguments.ContainsKey('parameters')) { $arguments.parameters } else { @{} }
                    $workingDirectory = if ($arguments.ContainsKey('workingDirectory')) { 
                        $arguments.workingDirectory 
                    } else { 
                        $PWD.Path 
                    }
                    $timeoutSeconds = if ($arguments.ContainsKey('timeoutSeconds')) { 
                        [math]::Max(1, [math]::Min(3600, [int]$arguments.timeoutSeconds))
                    } else { 
                        $script:ServerConfig.MaxExecutionTime
                    }
                    
                    $result = Invoke-PowerShellScript -Script $script -Parameters $parameters -WorkingDirectory $workingDirectory -TimeoutSeconds $timeoutSeconds
                    
                    $content = @()
                    
                    if ($result.output) {
                        $content += @{
                            type = 'text'
                            text = "Результат выполнения PowerShell скрипта:`n`n``````powershell`n$($result.output)`n``````"
                        }
                    }
                    
                    if ($result.errors.Count -gt 0) {
                        $errorText = $result.errors -join "`n"
                        $content += @{
                            type = 'text'
                            text = "Ошибки выполнения:`n`n``````text`n$errorText`n``````"
                        }
                    }
                    
                    if ($result.warnings.Count -gt 0) {
                        $warningText = $result.warnings -join "`n"
                        $content += @{
                            type = 'text'
                            text = "Предупреждения:`n`n``````text`n$warningText`n``````"
                        }
                    }
                    
                    if ($content.Count -eq 0) {
                        $content += @{
                            type = 'text'
                            text = 'Скрипт выполнен успешно. Результат выполнения отсутствует.'
                        }
                    }
                    
                    return New-MCPResponse -Id $Id -Result @{
                        content = $content
                        isError = -not $result.success
                        _meta = @{
                            executionTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
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
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Response
    )
    
    try {
        $json = $Response | ConvertTo-Json -Depth 20 -Compress -ErrorAction Stop
        
        Write-Host $json
        
        $logJson = if ($json.Length -gt 300) { 
            $json.Substring(0, 300) + '...' 
        } else { 
            $json 
        }
        Write-Log "Ответ отправлен: $logJson" -Level 'DEBUG'
    }
    catch {
        Write-Log "Критическая ошибка сериализации ответа: $($_.Exception.Message)" -Level 'ERROR'
        
        $errorResponse = @{
            jsonrpc = '2.0'
            error = @{
                code = -32603
                message = 'Внутренняя ошибка сериализации ответа'
            }
            id = if ($Response.ContainsKey('id')) { $Response.id } else { $null }
        }
        
        try {
            $errorJson = $errorResponse | ConvertTo-Json -Depth 5 -Compress
            Write-Host $errorJson
        }
        catch {
            Write-Host '{"jsonrpc":"2.0","error":{"code":-32603,"message":"Critical serialization error"},"id":null}'
        }
    }
}

#endregion

#region Main Server Loop

function Start-MCPServer {
    Write-Log "=== Запуск MCP PowerShell Server v$($script:ServerConfig.Version) ===" -Level 'INFO'
    Write-Log 'Режим работы: STDIO (JSON-RPC через стандартные потоки)' -Level 'INFO'
    Write-Log 'Протокол: MCP 2024-11-05' -Level 'INFO'
    Write-Log "Лог файл: $script:LogFile" -Level 'INFO'
    Write-Log "Рабочая директория: $($PWD.Path)" -Level 'INFO'
    
    $requestCount = 0
    
    try {
        while ($true) {
            $line = [Console]::ReadLine()
            
            if ($null -eq $line) {
                Write-Log 'Получен EOF, завершение работы сервера' -Level 'INFO'
                break
            }
            
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            
            $requestCount++
            Write-Log "Запрос #$requestCount получен (длина: $($line.Length) символов)" -Level 'DEBUG'
            
            try {
                $request = ConvertFrom-JsonToHashtable -Json $line
                
                if (-not (Test-MCPRequest -Request $request)) {
                    $errorResponse = @{
                        jsonrpc = '2.0'
                        error = @{
                            code = -32600
                            message = 'Неверный формат MCP запроса'
                        }
                        id = if ($request -and $request.ContainsKey('id')) { $request.id } else { $null }
                    }
                    Send-MCPResponse -Response $errorResponse
                    continue
                }
                
                $mcpResponse = Invoke-MCPMethod -Method $request.method -Params $request.params -Id $request.id
                Send-MCPResponse -Response $mcpResponse
                
            }
            catch {
                Write-Log "Ошибка обработки запроса #$requestCount : $($_.Exception.Message)" -Level 'ERROR'
                
                $parseErrorResponse = @{
                    jsonrpc = '2.0'
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
        Write-Log "Критическая ошибка главного цикла: $($_.Exception.Message)" -Level 'ERROR'
        throw
    }
    finally {
        Write-Log "=== MCP PowerShell Server завершен. Обработано запросов: $requestCount ===" -Level 'INFO'
    }
}

#endregion

#region Main Entry Point - ИСПРАВЛЕННЫЙ И ДОПОЛНЕННЫЙ БЛОК

try {
    if (Test-Path $script:LogFile) {
        try {
            Remove-Item $script:LogFile -Force -ErrorAction SilentlyContinue
        } catch {
            # Игнорирование ошибок удаления лога
        }
    }
    
    $logDir = Split-Path $script:LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    Write-Log "Инициализация MCP PowerShell Server v$($script:ServerConfig.Version)" -Level 'INFO'
    Write-Log "PowerShell версия: $($PSVersionTable.PSVersion)" -Level 'INFO'
    
    Start-MCPServer
}
catch {
    Write-Log "КРИТИЧЕСКАЯ ОШИБКА: $($_.Exception.Message)" -Level 'ERROR'
    exit 1
}

#endregion