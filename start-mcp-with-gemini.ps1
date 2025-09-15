## \file mcp-powershell-server/start-mcp-with-gemini.ps1
# -*- coding: utf-8 -*-
#! .pyenv/bin/powershell

<#
.SYNOPSIS
    Запускает MCP PowerShell сервер в отдельном окне и настраивает gemini-cli для работы с ним
    
.DESCRIPTION
    Скрипт автоматически запускает MCP сервер в новом окне PowerShell и ожидает его готовности,
    затем настраивает переменные окружения для gemini-cli для работы с MCP сервером.
    
.PARAMETER ApiKey
    Gemini API ключ для настройки CLI
    
.PARAMETER ServerPort
    Порт для MCP сервера (по умолчанию 8090)
    
.PARAMETER Wait
    Время ожидания запуска сервера в секундах (по умолчанию 10)
    
.EXAMPLE
    .\start-mcp-with-gemini.ps1 -ApiKey "your-api-key"
    
.EXAMPLE 
    .\start-mcp-with-gemini.ps1 -ApiKey "your-api-key" -ServerPort 9090
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ApiKey,
    
    [Parameter(Mandatory = $false)]
    [int]$ServerPort = 8090,
    
    [Parameter(Mandatory = $false)]
    [int]$Wait = 10,
    
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

# Функция показа справки
function Show-Help {
    $helpText = @"

MCP PowerShell Server + Gemini CLI Integration

ОПИСАНИЕ:
    Запускает MCP PowerShell сервер в отдельном окне и настраивает 
    gemini-cli для работы с ним через STDIO протокол.

ИСПОЛЬЗОВАНИЕ:
    .\start-mcp-with-gemini.ps1 [параметры]

ПАРАМЕТРЫ:
    -ApiKey <ключ>      Gemini API ключ (обязательный)
    -ServerPort <порт>  Порт MCP сервера (по умолчанию: 8090)  
    -Wait <секунды>     Время ожидания запуска сервера (по умолчанию: 10)
    -Help               Показать эту справку

ПРИМЕРЫ:
    # Базовое использование
    .\start-mcp-with-gemini.ps1 -ApiKey "your-gemini-api-key"
    
    # С настраиваемым портом
    .\start-mcp-with-gemini.ps1 -ApiKey "your-key" -ServerPort 9090
    
    # С увеличенным временем ожидания
    .\start-mcp-with-gemini.ps1 -ApiKey "your-key" -Wait 15

СИСТЕМНЫЕ ТРЕБОВАНИЯ:
    - PowerShell 7+
    - gemini-cli установлен и доступен в PATH
    - Microsoft.PowerShell.ConsoleGuiTools модуль

ПРИМЕЧАНИЯ:
    - MCP сервер запускается в отдельном окне и работает в фоне
    - Для остановки сервера закройте его окно или используйте Ctrl+C
    - API ключ можно также установить через переменную GEMINI_API_KEY

"@
    Write-Host $helpText -ForegroundColor Cyan
}

if ($Help) {
    Show-Help
    return
}

# Проверка наличия API ключа
if (-not $ApiKey -and -not $env:GEMINI_API_KEY) {
    Write-Host "ОШИБКА: Необходимо указать Gemini API ключ" -ForegroundColor Red
    Write-Host "Используйте параметр -ApiKey или установите переменную GEMINI_API_KEY" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Пример: .\start-mcp-with-gemini.ps1 -ApiKey 'your-api-key'" -ForegroundColor Gray
    return
}

# Функции утилиты
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

function Test-ServerAvailability {
    param([int]$Port)
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ReceiveTimeout = 1000
        $tcpClient.SendTimeout = 1000
        $tcpClient.Connect('localhost', $Port)
        $tcpClient.Close()
        return $true
    } catch {
        return $false
    }
}

function Test-Prerequisites {
    $issues = @()
    
    # Проверка PowerShell версии
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        $issues += "Требуется PowerShell 7+. Текущая версия: $($PSVersionTable.PSVersion)"
    }
    
    # Проверка gemini-cli
    try {
        $geminiVersion = & gemini --version 2>$null
        Write-Status "Gemini CLI найден: $($geminiVersion -replace '\r?\n', ' ')" -Type 'Success'
    } catch {
        $issues += "gemini-cli не найден в PATH. Установите его и добавьте в PATH."
    }
    
    # Проверка MCP сервера
    $serverScript = Join-Path $PSScriptRoot 'mcp-powershell-stdio.ps1'
    if (-not (Test-Path $serverScript)) {
        $issues += "MCP сервер не найден: $serverScript"
    } else {
        Write-Status "MCP сервер найден" -Type 'Success'
    }
    
    return $issues
}

# Основная функция запуска
function Start-MCPWithGemini {
    Write-Host "`n=== MCP PowerShell Server + Gemini CLI Integration ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Проверка предварительных условий
    Write-Status "Проверка системных требований..." -Type 'Info'
    $issues = Test-Prerequisites
    
    if ($issues.Count -gt 0) {
        Write-Status "Найдены проблемы:" -Type 'Error'
        $issues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        return
    }
    
    # Установка API ключа
    if ($ApiKey) {
        $env:GEMINI_API_KEY = $ApiKey
        Write-Status "API ключ установлен" -Type 'Success'
    }
    
    # Проверка доступности порта
    if (Test-ServerAvailability -Port $ServerPort) {
        Write-Status "Порт $ServerPort уже используется. Попытка подключения к существующему серверу..." -Type 'Warning'
    } else {
        Write-Status "Запуск MCP сервера на порту $ServerPort..." -Type 'Info'
        
        # Путь к серверному скрипту
        $serverScript = Join-Path $PSScriptRoot 'mcp-powershell-stdio.ps1'
        
        # Запуск сервера в новом окне
        try {
            $processArgs = @{
                FilePath = 'pwsh'
                ArgumentList = @('-NoExit', '-File', $serverScript)
                WindowStyle = 'Normal'
                PassThru = $true
            }
            
            $serverProcess = Start-Process @processArgs
            Write-Status "MCP сервер запущен в отдельном окне (PID: $($serverProcess.Id))" -Type 'Success'
            
            # Ожидание готовности сервера
            Write-Status "Ожидание готовности сервера (до $Wait секунд)..." -Type 'Info'
            
            for ($i = 0; $i -lt $Wait; $i++) {
                Start-Sleep -Seconds 1
                Write-Host "." -NoNewline -ForegroundColor Gray
            }
            Write-Host ""
            
            Write-Status "Сервер должен быть готов к работе" -Type 'Success'
            
        } catch {
            Write-Status "Ошибка запуска сервера: $($_.Exception.Message)" -Type 'Error'
            return
        }
    }
    
    # Создание конфигурации MCP для gemini-cli
    Write-Status "Настройка конфигурации MCP..." -Type 'Info'
    
    $mcpConfig = @{
        mcpServers = @{
            powershell = @{
                command = "pwsh"
                args = @(
                    "-File",
                    (Join-Path $PSScriptRoot 'mcp-powershell-stdio.ps1')
                )
                env = @{}
            }
        }
    } | ConvertTo-Json -Depth 5
    
    # Сохранение конфигурации MCP
    $configDir = Join-Path $env:USERPROFILE '.config\gemini'
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }
    
    $configFile = Join-Path $configDir 'mcp_servers.json'
    $mcpConfig | Set-Content -Path $configFile -Encoding UTF8
    Write-Status "Конфигурация MCP сохранена: $configFile" -Type 'Success'
    
    # Установка переменных окружения для MCP
    $env:MCP_SERVER_CONFIG = $configFile
    Write-Status "Переменная MCP_SERVER_CONFIG установлена" -Type 'Success'
    
    # Инструкции по использованию
    Write-Host ""
    Write-Host "=== ГОТОВО К РАБОТЕ ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "MCP сервер запущен и настроен для работы с gemini-cli" -ForegroundColor Green
    Write-Host ""
    Write-Host "Использование с gemini-cli:" -ForegroundColor Yellow
    Write-Host "  gemini --mcp-config `"$configFile`" -m gemini-2.5-pro -p `"your prompt`"" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Или для интерактивного режима:" -ForegroundColor Yellow  
    Write-Host "  gemini --mcp-config `"$configFile`" -i" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Доступные MCP инструменты:" -ForegroundColor Yellow
    Write-Host "  - run-script: Выполнение PowerShell скриптов" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Пример использования MCP:" -ForegroundColor Yellow
    Write-Host "  `"Выполни PowerShell команду Get-Process | Select-Object -First 5`"" -ForegroundColor Gray
    Write-Host ""
    Write-Status "Для остановки MCP сервера закройте его окно или нажмите Ctrl+C" -Type 'Info'
}

# Запуск
try {
    Start-MCPWithGemini
} catch {
    Write-Status "Критическая ошибка: $($_.Exception.Message)" -Type 'Error'
    exit 1
}