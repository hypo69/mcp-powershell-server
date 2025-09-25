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
    
    try {
        $json = $Response | ConvertTo-Json -Depth 10 -Compress
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
        $memory = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop
        $totalMemoryGB = [math]::Round(($memory | Measure-Object Capacity -Sum).Sum / 1GB, 2)
        
        $info = @"
Операционная система: $($os.Caption) $($os.Version)
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
    
    try {
        $processes = Get-Process | Where-Object { $_.CPU -gt 0 } | 
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
            # Парсинг JSON запроса
            $request = $line | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            
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
                
                "tools/call" {
                    $toolName = $request.params.name
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
                        
                        "get-processes" {
                            $count = if ($arguments.ContainsKey("count")) { 
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
                            } else {
                                $calcResult = Invoke-Calculator -Expression $arguments.expression
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
                            message = "Неизвестный метод: $($request.method)"
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
    
    try {
        $request = $line | ConvertFrom-Json -AsHashtable
        
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
                        message = "Неизвестный метод: $($request.method)"
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