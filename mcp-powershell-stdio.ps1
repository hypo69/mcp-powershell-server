## \file mcp-powershell-stdio.ps1


<#
.SYNOPSIS
    MCP PowerShell Server (STDIO версия)

.DESCRIPTION
    Сервер MCP для выполнения PowerShell скриптов через STDIO.
    Обрабатывает JSON-RPC 2.0 запросы, выполняет команды и возвращает результат.
    Логирование идет в файл $env:TEMP\mcp-powershell-server.log.
    
.PARAMETER None
    Параметры запуска через STDIO не требуются.
    
.EXAMPLE
    pwsh -File mcp-powershell-stdio.ps1
#>

[CmdletBinding()]
param()

# Настройка кодировки UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# Лог-файл
$LogFile = Join-Path $env:TEMP "mcp-powershell-server.log"

# Функция логирования
function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][ValidateSet("INFO","WARNING","ERROR","DEBUG")][string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logMessage -Encoding UTF8
}

# Конвертация JSON в хеш-таблицу
function ConvertFrom-JsonToHashtable {
    param([string]$Json)

    $obj = ConvertFrom-Json $Json

    function ConvertTo-Hashtable($obj) {
        $hash = @{}
        $obj.PSObject.Properties | ForEach-Object {
            $value = $_.Value
            if ($value -is [PSCustomObject]) {
                $value = ConvertTo-Hashtable $value
            } elseif ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                $value = @($value | ForEach-Object { if ($_ -is [PSCustomObject]) { ConvertTo-Hashtable $_ } else { $_ } })
            }
            $hash[$_.Name] = $value
        }
        return $hash
    }

    return ConvertTo-Hashtable $obj
}

# Проверка корректности MCP запроса
function Test-MCPRequest {
    param([hashtable]$Request)
    if (-not $Request.ContainsKey("jsonrpc") -or $Request.jsonrpc -ne "2.0") { return $false }
    if (-not $Request.ContainsKey("method")) { return $false }
    return $true
}

# Формирование MCP ответа
function New-MCPResponse {
    param(
        [object]$Id = $null,
        [object]$Result = $null,
        [hashtable]$Error = $null
    )
    $response = @{ jsonrpc = "2.0"; id = $Id }
    if ($Error) { $response.error = $Error } else { $response.result = $Result }
    return $response
}

# Выполнение PowerShell скрипта
function Invoke-PowerShellScript {
    param(
        [string]$Script,
        [hashtable]$Parameters = @{},
        [int]$TimeoutSeconds = 300,
        [string]$WorkingDirectory = $PWD.Path
    )
    try {
        Write-Log "Выполнение скрипта: $($Script.Substring(0,[Math]::Min(100,$Script.Length)))" -Level "DEBUG"
        $ps = [powershell]::Create()
        $ps.AddScript("Set-Location -Path '$WorkingDirectory'")
        $ps.AddScript($Script)
        foreach ($param in $Parameters.GetEnumerator()) { $ps.AddParameter($param.Key,$param.Value) }

        $asyncResult = $ps.BeginInvoke()
        if ($asyncResult.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
            $result = $ps.EndInvoke($asyncResult)
            $errors = $ps.Streams.Error
            $warnings = $ps.Streams.Warning

            $output = @{
                success = $errors.Count -eq 0
                output = ($result | Out-String -Width 120).Trim()
                errors = @($errors | ForEach-Object { $_.ToString() })
                warnings = @($warnings | ForEach-Object { $_.ToString() })
            }
            return $output
        } else {
            $ps.Stop()
            throw "Таймаут выполнения скрипта ($TimeoutSeconds секунд)"
        }
    } catch {
        Write-Log "Ошибка выполнения скрипта: $($_.Exception.Message)" -Level "ERROR"
        return @{ success = $false; output = ""; errors = @($_.Exception.Message); warnings = @() }
    } finally { if ($ps) { $ps.Dispose() } }
}

# Обработка MCP методов
function Invoke-MCPMethod {
    param(
        [string]$Method,
        [hashtable]$Params = @{},
        [object]$Id = $null
    )
    Write-Log "Обработка метода: $Method" -Level "DEBUG"
    switch ($Method) {
        "initialize" {
            return New-MCPResponse -Id $Id -Result @{
                protocolVersion = "2024-11-05"
                serverInfo = @{ name="PowerShell Script Runner"; version="1.0.0" }
            }
        }
        "tools/list" {
            return New-MCPResponse -Id $Id -Result @{
                tools=@(@{
                    name="run-script"
                    description="Выполняет PowerShell скрипт"
                    inputSchema=@{
                        type="object"
                        properties=@{ script=@{type="string"} }
                        required=@("script")
                    }
                })
            }
        }
        "tools/call" {
            if (-not $Params.ContainsKey("name")) {
                return New-MCPResponse -Id $Id -Error @{ code=-32602; message="Отсутствует параметр 'name'" }
            }
            switch ($Params.name) {
                "run-script" {
                    if (-not $Params.arguments.ContainsKey("script")) {
                        return New-MCPResponse -Id $Id -Error @{ code=-32602; message="Отсутствует параметр 'script'" }
                    }
                    $res = Invoke-PowerShellScript -Script $Params.arguments.script
                    return New-MCPResponse -Id $Id -Result @{
                        content=@(@{ type="text"; text=$res.output })
                        isError = -not $res.success
                        _meta=@{ success=$res.success; errorCount=$res.errors.Count; warningCount=$res.warnings.Count }
                    }
                }
                default {
                    return New-MCPResponse -Id $Id -Error @{ code=-32601; message="Неизвестный инструмент: $($Params.name)" }
                }
            }
        }
        default {
            return New-MCPResponse -Id $Id -Error @{ code=-32601; message="Неизвестный метод: $Method" }
        }
    }
}

# Отправка ответа
function Send-MCPResponse {
    param([hashtable]$Response)
    try {
        $json = $Response | ConvertTo-Json -Depth 20 -Compress
        Write-Host $json
        Write-Log "Отправлен ответ: $($json.Substring(0,[Math]::Min(200,$json.Length)))" -Level "DEBUG"
    } catch {
        Write-Log "Ошибка отправки ответа: $($_.Exception.Message)" -Level "ERROR"
        $err = @{ jsonrpc="2.0"; error=@{ code=-32603; message="Внутренняя ошибка сериализации" }; id=$null }
        Write-Host ($err | ConvertTo-Json -Depth 5 -Compress)
    }
}

# Основной цикл сервера
function Start-MCPServer {
    Write-Log "Запуск MCP PowerShell сервера (STDIO)" -Level "INFO"
    try {
        while ($true) {
            $line = [Console]::ReadLine()
            if ($null -eq $line -or [string]::IsNullOrWhiteSpace($line)) { continue }
            Write-Log "Получен запрос: $line" -Level "DEBUG"
            try {
                $request = ConvertFrom-JsonToHashtable -Json $line
                if (-not (Test-MCPRequest -Request $request)) {
                    Send-MCPResponse -Response @{ jsonrpc="2.0"; error=@{ code=-32600; message="Неверный MCP запрос" }; id=($request.id)} 
                    continue
                }
                $resp = Invoke-MCPMethod -Method $request.method -Params $request.params -Id $request.id
                Send-MCPResponse -Response $resp
            } catch {
                Write-Log "Ошибка обработки запроса: $($_.Exception.Message)" -Level "ERROR"
                Send-MCPResponse -Response @{ jsonrpc="2.0"; error=@{ code=-32700; message="Ошибка парсинга JSON: $($_.Exception.Message)" }; id=$null }
            }
        }
    } catch { Write-Log "Критическая ошибка: $($_.Exception.Message)" -Level "ERROR"; throw } finally { Write-Log "Сервер завершён" -Level "INFO" }
}

# Инициализация
try {
    if (Test-Path $LogFile) { Remove-Item $LogFile -Force }
    Write-Log "MCP PowerShell сервер инициализирован (v1.0.0)" -Level "INFO"
    Start-MCPServer
} catch { Write-Log "Фатальная ошибка: $($_.Exception.Message)" -Level "ERROR"; exit 1 }
