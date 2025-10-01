## \file launcher.ps1

<#
.SYNOPSIS
    Launcher для MCP PowerShell серверов
    
.DESCRIPTION
    Launcher автоматически запускает все MCP серверы в фоновых процессах.
    
.PARAMETER StopServers
    Остановить все запущенные MCP серверы
    
.PARAMETER ConfigPath
    Путь к директории с конфигурациями (по умолчанию: src/config)
    
.EXAMPLE
    .\launcher.ps1
    
.EXAMPLE
    .\launcher.ps1 -StopServers

.NOTES
    Version: 1.0.1
    Author: hypo69
    License: MIT (https://opensource.org/licenses/MIT)
    Copyright: @hypo69 - 2025
#>
#Requires -Version 7.0


[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$StopServers,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = 'src\config',
    
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

#region Global Variables

$script:LauncherVersion = '1.0.1'
$script:ServerProcesses = @{}
$script:LogFile = Join-Path $env:TEMP 'mcp-launcher.log'

# Определяем корень проекта — папку, где лежит этот скрипт
$script:ProjectRoot = $PSScriptRoot

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
        'ERROR'   { 'Red' }
        'INFO'    { 'Cyan' }
        'DEBUG'   { 'Gray' }
        default   { 'White' }
    }
    
    $prefix = switch ($Level) {
        'SUCCESS' { '[✓]' }
        'WARNING' { '[!]' }
        'ERROR'   { '[✗]' }
        'INFO'    { '[i]' }
        'DEBUG'   { '[d]' }
        default   { '[-]' }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Show-Help {
    $helpText = @"

MCP PowerShell Server Launcher v$script:LauncherVersion

ОПИСАНИЕ:
    Автоматический запуск всех MCP PowerShell серверов.

ИСПОЛЬЗОВАНИЕ:
    .\launcher.ps1 [параметры]

ПАРАМЕТРЫ:
    -StopServers            Остановить все запущенные MCP серверы
    -ConfigPath <путь>      Путь к директории с конфигурациями
    -Help                   Показать эту справку

ПРИМЕРЫ:
    # Запуск всех серверов
    .\launcher.ps1
    
    # Остановка всех серверов
    .\launcher.ps1 -StopServers

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
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName
    )

    $base = $script:ProjectRoot

    # Явно строим каждый путь через последовательные Join-Path
    $path1 = Join-Path -Path $base -ChildPath 'src'
    $path1 = Join-Path -Path $path1 -ChildPath 'servers'
    $path1 = Join-Path -Path $path1 -ChildPath $ServerName

    $path2 = Join-Path -Path $base -ChildPath 'servers'
    $path2 = Join-Path -Path $path2 -ChildPath $ServerName

    $path3 = Join-Path -Path $base -ChildPath $ServerName

    foreach ($path in @($path1, $path2, $path3)) {
        if (Test-Path -LiteralPath $path) {
            return (Resolve-Path -LiteralPath $path).Path
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
        $startInfo.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`""
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.CreateNoWindow = $true
        
        # 🔑 Ключевое изменение: рабочая директория — корень проекта
        $startInfo.WorkingDirectory = $script:ProjectRoot
        
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

function Show-ServerStatus {
    Write-Host ''
    Write-Host '=== СТАТУС MCP СЕРВЕРОВ ===' -ForegroundColor Cyan
    Write-Host ''
    
    $runningCount = 0
    
    $serverNames = $script:ServerProcesses.Keys | Sort-Object
    
    foreach ($serverName in $serverNames) {
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
            Script = 'Start-McpStdioServer.ps1'
            Description = 'STDIO сервер для выполнения PowerShell скриптов'
        }
        'powershell-https' = @{
            Script = 'Start-McpHTTPSServer.ps1'
            Description = 'HTTPS сервер для REST API'
        }
        'wordpress-cli' = @{
            Script = 'Start-McpWPCLIServer.ps1'
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
    
    return $true
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
    
    if (-not (Start-AllServers)) {
        exit 1
    }
    
    Write-Host '=== СЕРВЕРЫ УСПЕШНО ЗАПУЩЕНЫ ===' -ForegroundColor Green
    Write-Host ''
    
    Write-Host 'Для остановки всех серверов используйте:' -ForegroundColor Yellow
    Write-Host '  .\launcher.ps1 -StopServers' -ForegroundColor Gray
    Write-Host ''
    Write-Host 'Для просмотра логов:' -ForegroundColor Yellow
    Write-Host "  Get-Content `"$script:LogFile`" -Tail 50 -Wait" -ForegroundColor Gray
    Write-Host ''
    Write-Host 'Логи сервера STDIO:' -ForegroundColor Yellow
    Write-Host "  Get-Content `"$env:TEMP\mcp-server.log`" -Tail 50 -Wait" -ForegroundColor Gray
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