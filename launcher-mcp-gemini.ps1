## \file launcher-mcp-gemini.ps1
# -*- coding: utf-8 -*-
#! .pyenv/bin/powershell

<#
.SYNOPSIS
    Launcher для MCP PowerShell сервера с поддержкой Gemini CLI
    
.DESCRIPTION
    Упрощенный launcher для запуска MCP сервера и интеграции с gemini-cli.
    Автоматически определяет пути к серверам в структуре проекта.
    
.PARAMETER ApiKey
    Gemini API ключ для настройки CLI
    
.PARAMETER Mode
    Режим запуска: 'stdio' (для gemini-cli) или 'http' (для REST API)
    
.PARAMETER Port
    Порт для HTTP сервера (только для режима 'http')
    
.PARAMETER Test
    Запустить тестовый сервер вместо основного
    
.EXAMPLE
    .\launcher-mcp-gemini.ps1 -ApiKey "your-api-key"
    
.EXAMPLE
    .\launcher-mcp-gemini.ps1 -Mode http -Port 8090
    
.EXAMPLE
    .\launcher-mcp-gemini.ps1 -Test
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ApiKey,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("stdio", "http")]
    [string]$Mode = "stdio",
    
    [Parameter(Mandatory = $false)]
    [int]$Port = 8090,
    
    [Parameter(Mandatory = $false)]
    [switch]$Test,
    
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

function Show-Help {
    $helpText = @"

MCP PowerShell Server Launcher

ОПИСАНИЕ:
    Launcher для запуска MCP PowerShell сервера с автоматическим
    определением путей и настройкой интеграции с gemini-cli.

ИСПОЛЬЗОВАНИЕ:
    .\launcher-mcp-gemini.ps1 [параметры]

ПАРАМЕТРЫ:
    -ApiKey <ключ>     Gemini API ключ (для интеграции с gemini-cli)
    -Mode <режим>      Режим запуска: 'stdio' или 'http' (по умолчанию: stdio)
    -Port <порт>       Порт для HTTP сервера (по умолчанию: 8090)
    -Test              Запустить тестовый сервер
    -Help              Показать эту справку

ПРИМЕРЫ:
    # Запуск STDIO сервера для gemini-cli
    .\launcher-mcp-gemini.ps1 -ApiKey "your-gemini-api-key"
    
    # Запуск HTTP сервера
    .\launcher-mcp-gemini.ps1 -Mode http -Port 8090
    
    # Запуск тестового сервера
    .\launcher-mcp-gemini.ps1 -Test

СТРУКТУРА ПРОЕКТА:
    Launcher автоматически определяет расположение серверов в:
    - src/servers/mcp-powershell-stdio.ps1
    - src/servers/mcp-powershell-http.ps1  
    - src/servers/test-mcp.ps1

"@
    Write-Host $helpText -ForegroundColor Cyan
}

function Write-Status {
    param(
        [string]$Message,
        [string]$Type = 'Info'
    )
    $color = switch ($Type) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Info' { 'Cyan' }
        default { 'White' }
    }
    $prefix = switch ($Type) {
        'Success' { '[✓]' }
        'Warning' { '[!]' }
        'Error' { '[✗]' }
        'Info' { '[i]' }
        default { '[-]' }
    }
    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Find-ServerPath {
    param([string]$ServerName)
    
    # Поиск в различных возможных путях
    $possiblePaths = @(
        "src\servers\$ServerName",
        "servers\$ServerName", 
        $ServerName
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    return $null
}

function Setup-GeminiConfig {
    param([string]$ServerPath)
    
    Write-Status "Настройка конфигурации MCP для gemini-cli..." -Type 'Info'
    
    $configDir = Join-Path $env:USERPROFILE '.config\gemini'
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }
    
    $fullServerPath = Resolve-Path $ServerPath
    $mcpConfig = @{
        mcpServers = @{
            powershell = @{
                command = "pwsh"
                args = @("-File", $fullServerPath.Path)
                env = @{}
            }
        }
    } | ConvertTo-Json -Depth 5
    
    $configFile = Join-Path $configDir 'mcp_servers.json'
    $mcpConfig | Set-Content -Path $configFile -Encoding UTF8
    
    Write-Status "Конфигурация сохранена: $configFile" -Type 'Success'
    return $configFile
}

if ($Help) {
    Show-Help
    return
}

Write-Host ""
Write-Host "=== MCP PowerShell Server Launcher ===" -ForegroundColor Cyan
Write-Host ""

# Определение пути к серверу
if ($Test) {
    $serverScript = Find-ServerPath "test-mcp.ps1"
    $serverName = "Test MCP Server"
} elseif ($Mode -eq "http") {
    $serverScript = Find-ServerPath "mcp-powershell-http.ps1"  
    $serverName = "HTTP MCP Server"
} else {
    $serverScript = Find-ServerPath "mcp-powershell-stdio.ps1"
    $serverName = "STDIO MCP Server"
}

if (-not $serverScript) {
    Write-Status "ОШИБКА: Не найден серверный скрипт для режима '$Mode'" -Type 'Error'
    Write-Status "Убедитесь, что вы находитесь в корневой папке проекта" -Type 'Warning'
    return
}

Write-Status "Найден сервер: $serverScript" -Type 'Success'

# Настройка API ключа для gemini-cli
if ($ApiKey) {
    $env:GEMINI_API_KEY = $ApiKey
    Write-Status "API ключ установлен" -Type 'Success'
}

# Специальная обработка для разных режимов
switch ($Mode) {
    "stdio" {
        Write-Status "Запуск $serverName в STDIO режиме..." -Type 'Info'
        
        # Настройка конфигурации MCP если есть API ключ
        if ($ApiKey) {
            $configFile = Setup-GeminiConfig -ServerPath $serverScript
            
            Write-Host ""
            Write-Host "=== ГОТОВО К РАБОТЕ ===" -ForegroundColor Green
            Write-Host ""
            Write-Host "Использование с gemini-cli:" -ForegroundColor Yellow
            Write-Host "  gemini --mcp-config `"$configFile`" -m gemini-2.5-pro -p `"your prompt`"" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Интерактивный режим:" -ForegroundColor Yellow  
            Write-Host "  gemini --mcp-config `"$configFile`" -i" -ForegroundColor Gray
            Write-Host ""
        }
        
        # Запуск STDIO сервера
        & $serverScript
    }
    
    "http" {
        Write-Status "Запуск $serverName на порту $Port..." -Type 'Info'
        
        # Проверка доступности порта
        try {
            $tcpListener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
            $tcpListener.Start()
            $tcpListener.Stop()
            Write-Status "Порт $Port доступен" -Type 'Success'
        }
        catch {
            Write-Status "ОШИБКА: Порт $Port недоступен" -Type 'Error'
            return
        }
        
        Write-Host ""
        Write-Host "=== HTTP СЕРВЕР ЗАПУЩЕН ===" -ForegroundColor Green
        Write-Host "URL: http://localhost:$Port/" -ForegroundColor Yellow
        Write-Host "Для остановки используйте Ctrl+C" -ForegroundColor Gray
        Write-Host ""
        
        # Запуск HTTP сервера
        & $serverScript -Port $Port
    }
    
    default {
        Write-Status "Неизвестный режим: $Mode" -Type 'Error'
        return
    }
}

Write-Status "Сервер завершен" -Type 'Warning'