## \file mcp-powershell-server/mcp-powershell-wpcli.ps1
# -*- coding: utf-8 -*-
#! .pyenv/bin/powershell

<#
.SYNOPSIS
    MCP WordPress CLI Server (STDIO версия)

.DESCRIPTION
    Сервер MCP для выполнения команд WP-CLI через протокол JSON-RPC 
    с использованием стандартных потоков ввода-вывода.

.NOTES
    Version: 1.2.1
    Author: hypo69
    Protocol: MCP 2024-11-05
#>

#Requires -Version 7.0

# Настройка кодировки для корректной работы с UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

#region Global Configuration

$ConfigFileName = '../config/mcp-powershell-wordpress.config.json'

function Load-ServerConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    $ScriptDir = Split-Path -Parent $PSCommandPath
    $FullPath = Join-Path -Path $ScriptDir -ChildPath $Path
    
    $DefaultConfig = @{
        Name = 'WordPress CLI MCP Server'
        Version = '1.2.1'
        Description = 'Выполняет команды WP-CLI через MCP протокол'
        MaxExecutionTime = 300
        LogLevel = 'INFO'
    }
    
    if (-not (Test-Path $FullPath)) {
        Write-Error "Файл конфигурации не найден: $FullPath. Используется конфигурация по умолчанию."
        return $DefaultConfig
    }
    
    try {
        $ConfigJson = Get-Content -Path $FullPath -Raw | ConvertFrom-Json -ErrorAction Stop
        
        if ($ConfigJson.PSObject.Properties.Name -contains 'ServerConfig') {
            return $ConfigJson.ServerConfig
        }
        else {
            Write-Error "В файле конфигурации отсутствует ключ 'ServerConfig'. Используется конфигурация по умолчанию."
            return $DefaultConfig
        }
    }
    catch {
        Write-Error "Ошибка чтения конфигурации: $($_.Exception.Message). Используется конфигурация по умолчанию."
        return $DefaultConfig
    }
}

$script:ServerConfig = Load-ServerConfig -Path $ConfigFileName
$script:LogFile = Join-Path $env:TEMP 'mcp-wordpress-server.log'

#endregion

#region Utility Functions

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
    catch {
        # Игнорирование ошибок логирования
    }
}

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
        Write-Log 'Отправка результата' -Level 'DEBUG'
    }
    
    return $response
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
        Write-Log "Ошибка сериализации ответа: $($_.Exception.Message)" -Level 'ERROR'
        
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

#region Core Functions

function Invoke-WPCLI {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Arguments,
        
        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = $PWD.Path
    )
    
    $executionId = [guid]::NewGuid().ToString('N')[0..7] -join ''
    Write-Log "[$executionId] Начало выполнения WP-CLI: $Arguments" -Level 'INFO'
    
    $result = @{
        success = $false
        output = ''
        errors = @()
        warnings = @()
        executionTime = 0.0
    }
    
    $startTime = Get-Date
    $originalLocation = $PWD.Path

    try {
        if ((Test-Path $WorkingDirectory) -and ([System.IO.Path]::IsPathRooted($WorkingDirectory))) {
            Set-Location -Path $WorkingDirectory -ErrorAction Stop
        }

        $fullCommand = "wp $Arguments --format=json"

        $commandOutput = & powershell -Command $fullCommand 2>&1
        
        $errors = @($commandOutput | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -or $_ -match 'Error:' })
        $output = @($commandOutput | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] -and $_ -notmatch 'Error:' }) -join "`n"

        $result.output = $output
        $result.errors = @($errors | ForEach-Object { $_.ToString() })
        $result.success = $errors.Count -eq 0
    }
    catch {
        $result.errors += "Критическая ошибка PowerShell: $($_.Exception.Message)"
        $result.success = $false
    }
    finally {
        if ($originalLocation -ne $null) {
            Set-Location -Path $originalLocation -ErrorAction SilentlyContinue
        }
    }
    
    $result.executionTime = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
    
    $status = if ($result.success) { 'SUCCESS' } else { 'ERROR' }
    Write-Log "[$executionId] WP-CLI завершено: $status за $($result.executionTime) сек." -Level 'INFO'
    
    return $result
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
            Write-Log 'Инициализация MCP сервера WordPress CLI' -Level 'INFO'
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
                        name = 'run-wp-cli'
                        description = 'Выполняет команду WP-CLI на установке WordPress. Всегда возвращает структурированный JSON-вывод.'
                        inputSchema = @{
                            type = 'object'
                            properties = @{
                                commandArguments = @{
                                    type = 'string'
                                    description = 'Аргументы WP-CLI, например: ''post list'' или ''post create --post_title="Hello" --post_status=draft'''
                                }
                                workingDirectory = @{
                                    type = 'string'
                                    description = 'Рабочая директория WordPress (опционально)'
                                    default = $PWD.Path
                                }
                            }
                            required = @('commandArguments')
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
                'run-wp-cli' {
                    if (-not $arguments.ContainsKey('commandArguments')) {
                        return New-MCPResponse -Id $Id -Error @{
                            code = -32602
                            message = "Отсутствует обязательный параметр 'commandArguments'"
                        }
                    }
                    
                    $cmdArgs = $arguments.commandArguments
                    $workDir = if ($arguments.ContainsKey('workingDirectory')) { 
                        $arguments.workingDirectory 
                    } else { 
                        $PWD.Path 
                    }
                    
                    Write-Log "Параметры выполнения - Директория: $workDir" -Level 'DEBUG'
                    
                    $result = Invoke-WPCLI -Arguments $cmdArgs -WorkingDirectory $workDir
                    
                    $content = @()
                    
                    if ($result.output) {
                        $content += @{
                            type = 'text'
                            text = "Результат выполнения WP-CLI (JSON):`n`n``````json`n$($result.output)`n``````"
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
                            text = 'Команда WP-CLI выполнена успешно. Результат выполнения отсутствует.'
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

#endregion

#region Main Server Loop

function Start-MCPServer {
    Write-Log "=== Запуск MCP WordPress CLI Server v$($script:ServerConfig.Version) ===" -Level 'INFO'
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
                
                if (-not $request.ContainsKey('jsonrpc') -or $request.jsonrpc -ne '2.0') {
                    $errorResponse = @{
                        jsonrpc = '2.0'
                        error = @{
                            code = -32600
                            message = 'Неверная версия JSON-RPC'
                        }
                        id = if ($request -and $request.ContainsKey('id')) { $request.id } else { $null }
                    }
                    Send-MCPResponse -Response $errorResponse
                    continue
                }
                
                if (-not $request.ContainsKey('method') -or [string]::IsNullOrEmpty($request.method)) {
                    $errorResponse = @{
                        jsonrpc = '2.0'
                        error = @{
                            code = -32600
                            message = 'Отсутствует или пустой метод'
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
        Write-Log "=== MCP WordPress CLI Server завершен. Обработано запросов: $requestCount ===" -Level 'INFO'
    }
}

#endregion

#region Main Entry Point

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
    
    Write-Log "Инициализация MCP WordPress CLI Server v$($script:ServerConfig.Version)" -Level 'INFO'
    Write-Log "PowerShell версия: $($PSVersionTable.PSVersion)" -Level 'INFO'
    Write-Log "Операционная система: $($PSVersionTable.OS)" -Level 'INFO'
    
    Start-MCPServer
}
catch {
    $errorMessage = "КРИТИЧЕСКАЯ ОШИБКА: $($_.Exception.Message)"
    Write-Log $errorMessage -Level 'ERROR'
    
    try {
        $fatalError = @{
            jsonrpc = '2.0'
            error = @{
                code = -32603
                message = $errorMessage
            }
            id = $null
        } | ConvertTo-Json -Compress
        Write-Host $fatalError
    } catch {
        # Завершение при критической ошибке
    }
    
    exit 1
}

#endregion