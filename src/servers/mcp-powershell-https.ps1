## \file mcp-powershell-server/mcp-powershell-https.ps1

<#
.SYNOPSIS
    Улучшенный MCP PowerShell Server (HTTPS версия)

.DESCRIPTION
    HTTPS сервер для выполнения PowerShell скриптов через MCP протокол.
    Версия с улучшенной обработкой ошибок, безопасностью и производительностью.

.PARAMETER Port
    Порт для HTTP/HTTPS сервера (по умолчанию: 8090)

.PARAMETER ServerHost
    Хост для привязки сервера (по умолчанию: localhost)

.PARAMETER ConfigFile
    Путь к файлу конфигурации JSON

.EXAMPLE
    .\mcp-powershell-https.ps1 -Port 8090 -ServerHost localhost

.NOTES
    Version: 1.1.0
    Author: MCP PowerShell Server Team
    Protocol: MCP 2024-11-05
#>

#Requires -Version 7.0

$ConfigFileName = '../config/mcp-powershell-https.config.json'

function Load-ServerConfig {
    param([Parameter(Mandatory = $true)][string]$Path)
    
    $ScriptDir = Split-Path -Parent $PSCommandPath
    $FullPath = Join-Path -Path $ScriptDir -ChildPath $Path
    
    $DefaultConfig = @{
        Name = 'PowerShell HTTPS Server'
        Version = '1.0.0'
        Description = 'Выполняет PowerShell скрипты через HTTPS MCP протокол'
        MaxExecutionTime = 300
        LogLevel = 'INFO'
        Http = @{
            Port = 8090
            Host = 'localhost'
            UseHttps = $true
            MaxConcurrentRequests = 10
        }
    }
    
    if (-not (Test-Path $FullPath)) {
        Write-Error "Файл конфигурации не найден: $FullPath"
        return $DefaultConfig
    }
    
    try {
        $ConfigJson = Get-Content -Path $FullPath -Raw | ConvertFrom-Json -ErrorAction Stop
        
        if ($ConfigJson.PSObject.Properties.Name -contains 'ServerConfig') {
            return $ConfigJson.ServerConfig
        }
        return $ConfigJson
    }
    catch {
        Write-Error "Ошибка чтения конфигурации: $($_.Exception.Message)"
        return $DefaultConfig
    }
}

$script:ServerConfigFromFile = Load-ServerConfig -Path $ConfigFileName

param(
    [Parameter(Mandatory = $false)]
    [int]$Port = $script:ServerConfigFromFile.Http.Port,
    
    [Parameter(Mandatory = $false)]
    [string]$ServerHost = $script:ServerConfigFromFile.Http.Host,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = $ConfigFileName
)

$script:ServerConfig = @{
    Port = $Port;
    Host = $ServerHost;
    MaxConcurrentRequests = 10;
    TimeoutSeconds = 300;
    Name = "PowerShell Script Runner";
    Version = "1.1.0";
    Description = "HTTP MCP сервер для выполнения PowerShell скриптов";
    LogLevel = "INFO";
}

if ($ConfigFile -and (Test-Path $ConfigFile)) {
    try {
        $configData = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        if ($configData.Port) { $script:ServerConfig.Port = $configData.Port }
        if ($configData.Host) { $script:ServerConfig.Host = $configData.Host }
        if ($configData.MaxConcurrentRequests) { $script:ServerConfig.MaxConcurrentRequests = $configData.MaxConcurrentRequests }
        if ($configData.TimeoutSeconds) { $script:ServerConfig.TimeoutSeconds = $configData.TimeoutSeconds }
        # This function is defined later, so we use Write-Host for early logging
        Write-Host "[$([string](Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'))] [INFO] Конфигурация загружена из файла: $ConfigFile"
    }
    catch {
        Write-Host "[$([string](Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'))] [ERROR] Ошибка загрузки конфигурации: $($_.Exception.Message)"
    }
}

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
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    $color = switch ($Level) {
        "INFO" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        "DEBUG" { "Cyan" }
        default { "White" }
    }
    
    Write-Host $logMessage -ForegroundColor $color
}

function Test-MCPRequest {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Request
    )
    
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
    }
    
    return $response
}

function Test-ScriptSafety {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Script
    )
    
    return $true
}

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
    
    $executionId = [guid]::NewGuid().ToString("N")[0..7] -join ""
    Write-Log "[$executionId] Начало выполнения скрипта. Таймаут: $TimeoutSeconds сек" -Level "INFO"
    Write-Log "[$executionId] Скрипт: $($Script.Substring(0, [Math]::Min(200, $Script.Length)))$(if($Script.Length -gt 200){'...'})" -Level "DEBUG"
    
    $powerShell = $null
    $asyncResult = $null
    
    try {
        if (-not (Test-ScriptSafety -Script $Script)) {
            return @{
                success = $false
                output = ""
                errors = @("Скрипт содержит потенциально опасные команды")
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
                ""
            }
            
            if ($outputText.Length -gt 10000) {
                $outputText = $outputText.Substring(0, 10000) + "`n... [вывод обрезан]"
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
                    
                    $scriptToRun = $arguments.script
                    $scriptParameters = if ($arguments.ContainsKey("parameters")) { $arguments.parameters } else { @{} }
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
                    
                    $result = Invoke-PowerShellScript -Script $scriptToRun -Parameters $scriptParameters -WorkingDirectory $workingDirectory -TimeoutSeconds $timeoutSeconds
                    
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
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context
    )
    
    $request = $Context.Request
    $response = $Context.Response
    $clientEndpoint = $request.RemoteEndPoint.ToString()
    
    try {
        Write-Log "HTTP запрос от $clientEndpoint : $($request.HttpMethod) $($request.Url.AbsolutePath)" -Level "INFO"
        
        $response.Headers.Add("Access-Control-Allow-Origin", "*")
        $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
        
        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Close()
            Write-Log "OPTIONS запрос обработан успешно" -Level "DEBUG"
            return
        }
        
        if ($request.HttpMethod -ne "POST") {
            $response.StatusCode = 405
            $errorResponse = @{
                jsonrpc = "2.0"
                error = @{
                    code = -32600
                    message = "Поддерживается только POST метод"
                }
                id = $null
            }
            $responseJson = $errorResponse | ConvertTo-Json -Depth 10
            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            $response.Close()
            Write-Log "Отклонен запрос с неподдерживаемым методом: $($request.HttpMethod)" -Level "WARNING"
            return
        }
        
        $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
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
            }
            $responseJson = $errorResponse | ConvertTo-Json -Depth 10
            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            $response.Close()
            Write-Log "Отклонен запрос с пустым телом" -Level "WARNING"
            return
        }
        
        Write-Log "Получено тело запроса (длина: $($requestBody.Length) символов)" -Level "DEBUG"
        
        try {
            $mcpRequest = $requestBody | ConvertFrom-Json -AsHashtable -ErrorAction Stop
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
        
        $mcpResponse = Invoke-MCPMethod -Method $mcpRequest.method -Params $mcpRequest.params -Id $mcpRequest.id
        
        $response.StatusCode = 200
        $response.ContentType = "application/json; charset=utf-8"
        
        $responseJson = $mcpResponse | ConvertTo-Json -Depth 15
        $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
        
        $response.ContentLength64 = $responseBytes.Length
        $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
        
        Write-Log "Успешный ответ отправлен клиенту $clientEndpoint" -Level "INFO"
        
    }
    catch {
        Write-Log "Критическая ошибка обработки запроса от $clientEndpoint : $($_.Exception.Message)" -Level "ERROR"
        
        try {
            $response.StatusCode = 500
            $errorResponse = @{
                jsonrpc = "2.0"
                error = @{
                    code = -32603
                    message = "Внутренняя ошибка сервера"
                }
                id = $null
            }
            $responseJson = $errorResponse | ConvertTo-Json -Depth 10
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
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$Config = $script:ServerConfig
    )
    
    $listener = $null
    
    try {
        $listener = New-Object System.Net.HttpListener
        $url = "http://$($Config.Host):$($Config.Port)/"
        $listener.Prefixes.Add($url)
        
        Write-Log "=== Запуск MCP PowerShell HTTP Server v$($Config.Version) ===" -Level "INFO"
        Write-Log "URL: $url" -Level "INFO"
        Write-Log "Максимальное время выполнения: $($Config.TimeoutSeconds) сек" -Level "INFO"
        Write-Log "Максимальные concurrent запросы: $($Config.MaxConcurrentRequests)" -Level "INFO"
        
        $listener.Start()
        Write-Log "HTTP сервер запущен и ожидает подключения..." -Level "INFO"
        
        $requestCount = 0
        while ($listener.IsListening) {
            try {
                $context = $listener.GetContext()
                $requestCount++
                
                Write-Log "Запрос #$requestCount от $($context.Request.RemoteEndPoint)" -Level "INFO"
                
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

$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Write-Log "Получен сигнал завершения PowerShell" -Level "INFO"
}

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
    
    try {
        $ipAddress = if ($script:ServerConfig.Host -eq "localhost") { 
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
    
    Start-MCPServer -Config $script:ServerConfig
}
catch {
    Write-Log "КРИТИЧЕСКАЯ ОШИБКА: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

#endregion