## \file launcher-mcp-gemini.ps1

<#
.SYNOPSIS
    Launcher для MCP PowerShell серверов с поддержкой Gemini CLI
    
.DESCRIPTION
    Launcher автоматически запускает все MCP серверы в фоновых процессах
    и настраивает интеграцию с gemini-cli.
    
.PARAMETER ApiKey
    Gemini API ключ для настройки CLI
    
.PARAMETER ServersOnly
    Запустить только серверы без настройки gemini-cli
    
.PARAMETER StopServers
    Остановить все запущенные MCP серверы
    
.PARAMETER ConfigPath
    Путь к директории с конфигурациями (по умолчанию: src/config)
    
.EXAMPLE
    .\launcher-mcp-gemini.ps1 -ApiKey "your-api-key"
    
.EXAMPLE
    .\launcher-mcp-gemini.ps1 -ServersOnly
    
.EXAMPLE
    .\launcher-mcp-gemini.ps1 -StopServers

.NOTES
    Author: hypo69
    License: MIT (https://opensource.org/licenses/MIT)
    Copyright: @hypo69 - 2025
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ApiKey,
    
    [Parameter(Mandatory = $false)]
    [switch]$ServersOnly,
    
    [Parameter(Mandatory = $false)]
    [switch]$StopServers,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = 'src\config',
    
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

#region Global Variables

$script:LauncherVersion = '1.0.0'
$script:ServerProcesses = @{}
$script:LogFile = Join-Path $env:TEMP 'mcp-launcher.log'

#endregion

#region Utility Functions

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    Add-Content -Path $script:LogFile -Value $logMessage -Encoding UTF8 -ErrorAction SilentlyContinue
    
    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        'INFO' { 'Cyan' }
        'DEBUG' { 'Gray' }
        default { 'White' }
    }
    
    $prefix = switch ($Level) {
        'SUCCESS' { '[✓]' }
        'WARNING' { '[!]' }
        'ERROR' { '[✗]' }
        'INFO' { '[i]' }
        'DEBUG' { '[d]' }
        default { '[-]' }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Show-Help {
    $helpText = @"

MCP PowerShell Server Launcher v$script:LauncherVersion

ОПИСАНИЕ:
    Автоматический запуск всех MCP PowerShell серверов и настройка
    интеграции с gemini-cli.

ИСПОЛЬЗОВАНИЕ:
    .\launcher-mcp-gemini.ps1 [параметры]

ПАРАМЕТРЫ:
    -ApiKey <ключ>          Gemini API ключ для настройки gemini-cli
    -ServersOnly            Запустить только серверы без настройки gemini-cli
    -StopServers            Остановить все запущенные MCP серверы
    -ConfigPath <путь>      Путь к директории с конфигурациями
    -Help                   Показать эту справку

ПРИМЕРЫ:
    # Запуск всех серверов с настройкой gemini-cli
    .\launcher-mcp-gemini.ps1 -ApiKey "your-gemini-api-key"
    
    # Запуск только серверов
    .\launcher-mcp-gemini.ps1 -ServersOnly
    
    # Остановка всех серверов
    .\launcher-mcp-gemini.ps1 -StopServers

ЗАПУСКАЕМЫЕ СЕРВЕРЫ:
    - powershell-stdio    : STDIO сервер для выполнения PowerShell скриптов
    - powershell-https    : HTTPS сервер для REST API
    - wordpress-cli       : WordPress CLI сервер для управления WordPress

АВТОР:
    hypo69

ЛИЦЕНЗИЯ:
    MIT (https://opensource.org/licenses/MIT)
    Copyright @hypo69 - 2025

"@
    Write-Host $helpText -ForegroundColor Cyan
}

function Find-ServerScript {
    param([string]$ServerName)
    
    $possiblePaths = @(
        "src\servers\$ServerName",
        "servers\$ServerName",
        $ServerName
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return (Resolve-Path $path).Path
        }
    }
    
    return $null
}

function Test-ServerRunning {
    param([string]$ServerName)
    
    if ($script:ServerProcesses.ContainsKey($ServerName)) {
        $process = $script:ServerProcesses[$ServerName]
        if ($process -and -not $process.HasExited) {
            return $true
        }
    }
    
    return $false
}

function Start-MCPServer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Environment = @{}
    )
    
    Write-Log "Запуск сервера: $ServerName" -Level 'INFO'
    
    if (Test-ServerRunning -ServerName $ServerName) {
        Write-Log "Сервер $ServerName уже запущен" -Level 'WARNING'
        return $true
    }
    
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = 'pwsh'
        $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.CreateNoWindow = $true
        $startInfo.WorkingDirectory = (Get-Location).Path
        
        foreach ($key in $Environment.Keys) {
            $startInfo.EnvironmentVariables[$key] = $Environment[$key]
        }
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        $process.Start() | Out-Null
        
        Start-Sleep -Milliseconds 500
        
        if ($process.HasExited) {
            $errorOutput = $process.StandardError.ReadToEnd()
            Write-Log "Сервер $ServerName завершился с ошибкой: $errorOutput" -Level 'ERROR'
            return $false
        }
        
        $script:ServerProcesses[$ServerName] = $process
        Write-Log "Сервер $ServerName запущен (PID: $($process.Id))" -Level 'SUCCESS'
        
        return $true
    }
    catch {
        Write-Log "Ошибка запуска сервера ${ServerName}: $($_.Exception.Message)" -Level 'ERROR'
        return $false
    }
}

function Stop-MCPServers {
    Write-Log 'Остановка всех MCP серверов...' -Level 'INFO'
    
    $stoppedCount = 0
    
    foreach ($serverName in $script:ServerProcesses.Keys) {
        $process = $script:ServerProcesses[$serverName]
        
        if ($process -and -not $process.HasExited) {
            try {
                $process.Kill()
                $process.WaitForExit(5000)
                Write-Log "Сервер $serverName остановлен" -Level 'SUCCESS'
                $stoppedCount++
            }
            catch {
                Write-Log "Ошибка остановки сервера ${serverName}: $($_.Exception.Message)" -Level 'ERROR'
            }
        }
    }
    
    $script:ServerProcesses.Clear()
    
    Write-Log "Остановлено серверов: $stoppedCount" -Level 'INFO'
}

function Setup-GeminiConfig {
    param([hashtable]$Servers)
    
    Write-Log 'Настройка конфигурации MCP для gemini-cli...' -Level 'INFO'
    
    $configDir = Join-Path $env:USERPROFILE '.config\gemini'
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }
    
    $mcpServers = @{}
    
    foreach ($serverName in $Servers.Keys) {
        $serverPath = $Servers[$serverName]
        $mcpServers[$serverName] = @{
            command = 'pwsh'
            args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $serverPath)
            env = @{
                POWERSHELL_EXECUTION_POLICY = 'RemoteSigned'
            }
        }
    }
    
    $mcpConfig = @{
        mcpServers = $mcpServers
    } | ConvertTo-Json -Depth 10
    
    $configFile = Join-Path $configDir 'mcp_servers.json'
    $mcpConfig | Set-Content -Path $configFile -Encoding UTF8
    
    Write-Log "Конфигурация сохранена: $configFile" -Level 'SUCCESS'
    return $configFile
}

function Show-ServerStatus {
    Write-Host ''
    Write-Host '=== СТАТУС MCP СЕРВЕРОВ ===' -ForegroundColor Cyan
    Write-Host ''
    
    $runningCount = 0
    
    foreach ($serverName in $script:ServerProcesses.Keys) {
        $process = $script:ServerProcesses[$serverName]
        
        if ($process -and -not $process.HasExited) {
            Write-Host "  ✓ $serverName" -ForegroundColor Green -NoNewline
            Write-Host " (PID: $($process.Id))" -ForegroundColor Gray
            $runningCount++
        } else {
            Write-Host "  ✗ $serverName" -ForegroundColor Red -NoNewline
            Write-Host ' (остановлен)' -ForegroundColor Gray
        }
    }
    
    Write-Host ''
    Write-Host "Запущено серверов: $runningCount / $($script:ServerProcesses.Count)" -ForegroundColor $(if ($runningCount -eq $script:ServerProcesses.Count) { 'Green' } else { 'Yellow' })
    Write-Host ''
}

#endregion

#region Main Logic

function Start-AllServers {
    Write-Host ''
    Write-Host "=== MCP PowerShell Server Launcher v$script:LauncherVersion ===" -ForegroundColor Cyan
    Write-Host ''
    
    $servers = @{
        'powershell-stdio' = @{
            Script = 'mcp-powershell-stdio.ps1'
            Description = 'STDIO сервер для выполнения PowerShell скриптов'
        }
        'powershell-https' = @{
            Script = 'mcp-powershell-https.ps1'
            Description = 'HTTPS сервер для REST API'
        }
        'wordpress-cli' = @{
            Script = 'mcp-powershell-wpcli.ps1'
            Description = 'WordPress CLI сервер'
        }
    }
    
    $foundServers = @{}
    $successCount = 0
    
    Write-Log 'Поиск серверных скриптов...' -Level 'INFO'
    
    foreach ($serverName in $servers.Keys) {
        $scriptName = $servers[$serverName].Script
        $scriptPath = Find-ServerScript -ServerName $scriptName
        
        if ($scriptPath) {
            Write-Log "Найден: $scriptName" -Level 'SUCCESS'
            $foundServers[$serverName] = $scriptPath
        } else {
            Write-Log "Не найден: $scriptName" -Level 'WARNING'
        }
    }
    
    if ($foundServers.Count -eq 0) {
        Write-Log 'ОШИБКА: Не найдено ни одного серверного скрипта' -Level 'ERROR'
        Write-Log 'Убедитесь, что вы находитесь в корневой директории проекта' -Level 'WARNING'
        return $false
    }
    
    Write-Host ''
    Write-Log 'Запуск серверов...' -Level 'INFO'
    Write-Host ''
    
    foreach ($serverName in $foundServers.Keys) {
        $scriptPath = $foundServers[$serverName]
        $description = $servers[$serverName].Description
        
        Write-Host "  → $description" -ForegroundColor Gray
        
        $env = @{
            POWERSHELL_EXECUTION_POLICY = 'RemoteSigned'
        }
        
        if (Start-MCPServer -ServerName $serverName -ScriptPath $scriptPath -Environment $env) {
            $successCount++
        }
        
        Start-Sleep -Milliseconds 300
    }
    
    Write-Host ''
    
    if ($successCount -eq 0) {
        Write-Log 'ОШИБКА: Не удалось запустить ни один сервер' -Level 'ERROR'
        return $false
    }
    
    Show-ServerStatus
    
    return $foundServers
}

#endregion

#region Entry Point

try {
    if ($Help) {
        Show-Help
        exit 0
    }
    
    if ($StopServers) {
        Stop-MCPServers
        exit 0
    }
    
    $foundServers = Start-AllServers
    
    if (-not $foundServers) {
        exit 1
    }
    
    if (-not $ServersOnly) {
        if ($ApiKey) {
            $env:GEMINI_API_KEY = $ApiKey
            Write-Log 'Gemini API ключ установлен' -Level 'SUCCESS'
            
            $configFile = Setup-GeminiConfig -Servers $foundServers
            
            Write-Host '=== ГОТОВО К РАБОТЕ ===' -ForegroundColor Green
            Write-Host ''
            Write-Host 'Использование с gemini-cli:' -ForegroundColor Yellow
            Write-Host "  gemini --mcp-config `"$configFile`" -m gemini-2.5-pro -p `"your prompt`"" -ForegroundColor Gray
            Write-Host ''
            Write-Host 'Интерактивный режим:' -ForegroundColor Yellow
            Write-Host "  gemini --mcp-config `"$configFile`" -i" -ForegroundColor Gray
            Write-Host ''
        } else {
            Write-Log 'Серверы запущены. Для настройки gemini-cli укажите параметр -ApiKey' -Level 'WARNING'
        }
    }
    
    Write-Host 'Для остановки всех серверов используйте:' -ForegroundColor Yellow
    Write-Host '  .\launcher-mcp-gemini.ps1 -StopServers' -ForegroundColor Gray
    Write-Host ''
    Write-Host 'Для просмотра логов:' -ForegroundColor Yellow
    Write-Host "  Get-Content `"$script:LogFile`" -Tail 50 -Wait" -ForegroundColor Gray
    Write-Host ''
    
    Write-Log 'Нажмите Ctrl+C для завершения launcher (серверы продолжат работу в фоне)' -Level 'INFO'
    
    while ($true) {
        Start-Sleep -Seconds 5
        
        $runningCount = 0
        foreach ($serverName in $script:ServerProcesses.Keys) {
            $process = $script:ServerProcesses[$serverName]
            if ($process -and -not $process.HasExited) {
                $runningCount++
            }
        }
        
        if ($runningCount -eq 0) {
            Write-Log 'Все серверы остановлены' -Level 'WARNING'
            break
        }
    }
}
catch {
    Write-Log "Критическая ошибка: $($_.Exception.Message)" -Level 'ERROR'
    Stop-MCPServers
    exit 1
}
finally {
    Write-Log 'Launcher завершен' -Level 'INFO'
}

#endregion