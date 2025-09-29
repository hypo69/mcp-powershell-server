# mcp-powershell-wordpress.ps1 - Специализированный MCP-сервер для WP-CLI

#region Global Configuration

# Имя файла конфигурации
$ConfigFileName = "mcp-powershell-wordpress.config.json"

function Load-ServerConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    # Определяем полный путь к файлу конфигурации (относительно местоположения скрипта)
    $FullPath = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) -ChildPath $Path
    
    # Конфигурация по умолчанию на случай критической ошибки
    $DefaultConfig = @{
        Name             = "Default Config Server"
        Version          = "0.0.0"
        Description      = "Ошибка загрузки конфигурации"
        MaxExecutionTime = 60
        LogLevel         = "ERROR"
    }
    
    if (-not (Test-Path $FullPath)) {
        Write-Error "Критическая ошибка: Файл конфигурации не найден по пути: $FullPath. Используется конфигурация по умолчанию."
        return $DefaultConfig
    }
    
    try {
        # Загрузка и преобразование JSON
        $ConfigJson = Get-Content -Path $FullPath -Raw | ConvertFrom-Json -ErrorAction Stop
        
        # Проверяем наличие корневого ключа
        if ($ConfigJson.ContainsKey("ServerConfig")) {
            return $ConfigJson.ServerConfig
        }
        else {
            Write-Error "Критическая ошибка: В файле конфигурации отсутствует ключ 'ServerConfig'. Используется конфигурация по умолчанию."
            return $DefaultConfig
        }
    }
    catch {
        Write-Error "Критическая ошибка: Не удалось прочитать или разобрать JSON конфигурации: $($_.Exception.Message). Используется конфигурация по умолчанию."
        return $DefaultConfig
    }
}

# Глобальная переменная для хранения загруженной конфигурации
$script:ServerConfig = Load-ServerConfig -Path $ConfigFileName

#endregion

-- -

#region Utility Functions

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "DEBUG", "ERROR")]
        [string]$Level = "INFO"
    )
    
    # Проверка уровня логирования
    $logLevels = @{ "ERROR" = 3; "INFO" = 2; "DEBUG" = 1 }
    if ($logLevels.$Level -ge $logLevels.$($script:ServerConfig.LogLevel)) {
        $timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        $output = "[$timestamp] [$Level] $Message"
        # Логирование в STDERR
        Write-Error $output -ErrorAction SilentlyContinue
    }
}

function New-MCPResponse {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,
        
        [Parameter(Mandatory = $false)]
        $Result,
        
        [Parameter(Mandatory = $false)]
        $Error
    )
    
    $response = @{
        jsonrpc = "2.0"
        id      = $Id
    }
    
    if ($Result -ne $null) {
        $response.result = $Result
    }
    elseif ($Error -ne $null) {
        $response.error = $Error
    }
    
    return $response | ConvertTo-Json -Compress -Depth 10
}

function Read-MCPRequest {
    # Чтение одной строки из STDIN
    try {
        $jsonString = Read-Host
        if ([string]::IsNullOrWhiteSpace($jsonString)) {
            return $null
        }
        $request = $jsonString | ConvertFrom-Json -ErrorAction Stop
        return $request
    }
    catch {
        Write-Log "Ошибка при чтении или разборе JSON: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

#endregion

-- -

#region Core Functions

function Invoke-WPCLI {
    <#
    .SYNOPSIS
        Выполняет команду WP-CLI в изолированном окружении
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Arguments,
        
        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = $PWD.Path
    )
    
    $executionId = [guid]::NewGuid().ToString("N")[0..7] -join ""
    Write-Log "[$executionId] Начало выполнения WP-CLI: $Arguments" -Level "INFO"
    
    $result = @{ success = $false; output = ""; errors = @(); warnings = @(); executionTime = 0.0 }
    $startTime = Get-Date
    $originalLocation = $PWD.Path

    try {
        # 1. Установка рабочей директории
        if ((Test-Path $WorkingDirectory) -and ([System.IO.Path]::IsPathRooted($WorkingDirectory))) {
            Set-Location -Path $WorkingDirectory -ErrorAction Stop
        }

        # 2. Формируем полную команду WP-CLI с принудительным JSON-форматом для AI
        $fullCommand = "wp $Arguments --format=json"

        # 3. Запуск команды через powershell -Command для корректной обработки потоков
        # Используем 'wp', предполагая, что вы добавили wp.bat в PATH (как мы обсуждали для Windows)
        $commandOutput = & powershell -Command $fullCommand 2>&1
        
        # Разделение потоков: ошибки/варнинги и стандартный вывод
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
        # Возвращаемся в исходную директорию
        if ($originalLocation -ne $null) {
            Set-Location -Path $originalLocation -ErrorAction SilentlyContinue
        }
    }
    
    $result.executionTime = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
    
    $status = if ($result.success) { "SUCCESS" } else { "ERROR" }
    Write-Log "[$executionId] WP-CLI завершено: $status за $($result.executionTime) сек." -Level "INFO"
    
    return $result
}

function Invoke-MCPMethod {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Request
    )
    
    $Id = $Request.id
    $Method = $Request.method
    $Params = if ($Request.params -ne $null) { $Request.params } else { @{} }
    
    Write-Log "Получен запрос: Method=$Method, Id=$Id" -Level "DEBUG"
    
    try {
        switch ($Method) {
            "server/info" {
                return New-MCPResponse -Id $Id -Result $script:ServerConfig
            }
            
            "tools/list" {
                return New-MCPResponse -Id $Id -Result @{
                    tools = @(
                        @{
                            name        = "run-wp-cli"
                            description = "Выполняет команду WP-CLI на установке WordPress. Всегда возвращает структурированный JSON-вывод."
                            inputSchema = @{
                                type       = "object"
                                properties = @{
                                    commandArguments = @{
                                        type        = "string"
                                        description = "Аргументы WP-CLI, например: 'post create --post_title=\"Hello AI\" --post_status=draft'"
                                    }
                                    workingDirectory = @{
                                        type        = "string"
                                        description = "Рабочая директория, содержащая установку WordPress (опционально, по умолчанию - текущая)"
                                        default     = $PWD.Path
                                    }
                                }
                                required = @("commandArguments")
                            }
                        }
                    )
                }
            }
            
            "tools/call" {
                if (-not $Params.ContainsKey("name")) {
                    return New-MCPResponse -Id $Id -Error @{
                        code    = -32602
                        message = "Отсутствует обязательный параметр 'name' для tools/call"
                    }
                }
                
                $toolName = $Params.name
                $arguments = if ($Params.ContainsKey("arguments")) { $Params.arguments } else { @{} }
                
                switch ($toolName) {
                    "run-wp-cli" {
                        if (-not $arguments.ContainsKey("commandArguments")) {
                            return New-MCPResponse -Id $Id -Error @{
                                code    = -32602
                                message = "Отсутствует обязательный параметр 'commandArguments'"
                            }
                        }
                        
                        $result = Invoke-WPCLI -Arguments $arguments.commandArguments -WorkingDirectory $arguments.workingDirectory
                        
                        $content = @()
                        if ($result.output) {
                            $content += @{ type = "text"; text = "Результат WP-CLI (JSON):`n`n``````json`n$($result.output)`n``````" }
                        }
                        if ($result.errors.Count -gt 0) {
                            $errorText = $result.errors -join "`n"
                            $content += @{ type = "text"; text = "Ошибки WP-CLI:`n`n``````text`n$errorText`n``````" }
                        }
                        if ($content.Count -eq 0) {
                            $content += @{ type = "text"; text = "Команда WP-CLI выполнена. Результат отсутствует." }
                        }
                        
                        return New-MCPResponse -Id $Id -Result @{
                            content = $content
                            isError = -not $result.success
                            _meta   = @{
                                executionTime     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                                success           = $result.success
                                errorCount        = $result.errors.Count
                                executionDuration = $result.executionTime
                            }
                        }
                    }
                    
                    default {
                        return New-MCPResponse -Id $Id -Error @{
                            code    = -32601
                            message = "Неизвестный метод/инструмент: $toolName"
                        }
                    }
                }
            }
            
            default {
                return New-MCPResponse -Id $Id -Error @{
                    code    = -32601
                    message = "Неизвестный метод: $Method"
                }
            }
        }
    }
    catch {
        Write-Log "Непредвиденная ошибка при обработке $Method: $($_.Exception.Message)" -Level "ERROR"
        return New-MCPResponse -Id $Id -Error @{
            code    = -32603
            message = "Внутренняя ошибка сервера: $($_.Exception.Message)"
        }
    }
}

#endregion

-- -

#region Main Loop

function Main-MCPLoop {
    Write-Log "Запуск MCP-сервера WP-CLI (v$($script:ServerConfig.Version))" -Level "INFO"
    Write-Log "Ожидание запросов на STDIN..." -Level "INFO"

    # Основной цикл обработки запросов
    while ($true) {
        $requestJson = Read-Host
        
        if ([string]::IsNullOrWhiteSpace($requestJson)) {
            Write-Log "Получена пустая строка или закрыт STDIN. Завершение работы." -Level "INFO"
            break
        }
        
        try {
            $request = $requestJson | ConvertFrom-Json -ErrorAction Stop
            $responseJson = Invoke-MCPMethod -Request $request
            
            # Отправка ответа в STDOUT
            Write-Output $responseJson
            
        }
        catch {
            $errorId = if ($request -ne $null -and $request.ContainsKey('id')) { $request.id } else { $null }
            $errorMessage = "Критическая ошибка обработки запроса: $($_.Exception.Message)"
            Write-Log $errorMessage -Level "ERROR"
            
            # Попытка отправить сообщение об ошибке
            if ($errorId) {
                $errorResponse = New-MCPResponse -Id $errorId -Error @{
                    code    = -32700
                    message = "Ошибка синтаксического анализа JSON или обработки: $($_.Exception.Message)"
                }
                Write-Output $errorResponse
            }
        }
    }
}

# Запуск основного цикла
Main-MCPLoop
#endregion