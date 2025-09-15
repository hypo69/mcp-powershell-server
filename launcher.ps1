## \file launcher.ps1
# -*- coding: utf-8 -*-

<#
.SYNOPSIS
    Главный скрипт для запуска MCP сервера и настройки работы с Gemini CLI

.DESCRIPTION
    Автоматически запускает MCP PowerShell сервер в отдельном окне и настраивает
    gemini-cli для работы с ним. Обеспечивает правильную последовательность запуска.

.PARAMETER ApiKey
    Gemini API ключ

.PARAMETER LaunchGemini
    Запустить gemini-cli в интерактивном режиме после настройки MCP

.PARAMETER Model
    Модель Gemini для использования (по умолчанию gemini-2.5-flash)

.EXAMPLE
    .\start-mcp-gemini.ps1 -ApiKey "your-api-key"

.EXAMPLE
    .\start-mcp-gemini.ps1 -ApiKey "your-api-key" -LaunchGemini -Model "gemini-2.5-pro"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ApiKey,

    [Parameter(Mandatory = $false)]
    [switch]$LaunchGemini,

    [Parameter(Mandatory = $false)]
    [ValidateSet('gemini-2.5-pro', 'gemini-2.5-flash')]
    [string]$Model = 'gemini-2.5-flash',

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

# === Вспомогательные функции ===
function Write-Launch {
    param(
        [string]$Message,
        [string]$Type = 'Info'
    )
    $color = switch ($Type) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Info' { 'Cyan' }
        'Title' { 'Magenta' }
        default { 'White' }
    }

    if ($Type -eq 'Title') {
        Write-Host "`n$('=' * 60)" -ForegroundColor $color
        Write-Host " $Message" -ForegroundColor $color
        Write-Host "$('=' * 60)`n" -ForegroundColor $color
    } else {
        $prefix = switch ($Type) {
            'Success' { '[✓]' }
            'Warning' { '[!]' }
            'Error' { '[✗]' }
            'Info' { '[i]' }
            default { '[-]' }
        }
        Write-Host "$prefix $Message" -ForegroundColor $color
    }
}

function Show-Help {
    $helpText = @"
MCP PowerShell Server + Gemini CLI Launcher

ОПИСАНИЕ:
    Главный скрипт для интеграции MCP PowerShell сервера с gemini-cli.
    Автоматически запускает сервер в отдельном окне и настраивает CLI.

ИСПОЛЬЗОВАНИЕ:
    .\start-mcp-gemini.ps1 [параметры]

ПАРАМЕТРЫ:
    -ApiKey <ключ>      Gemini API ключ (обязательный)
    -LaunchGemini       Запустить gemini-cli после настройки
    -Model <модель>     Модель Gemini (gemini-2.5-pro | gemini-2.5-flash)
    -Help               Показать эту справку

ПРИМЕРЫ:
    .\start-mcp-gemini.ps1 -ApiKey "your-api-key"
    .\start-mcp-gemini.ps1 -ApiKey "your-key" -LaunchGemini
    .\start-mcp-gemini.ps1 -ApiKey "your-key" -LaunchGemini -Model "gemini-2.5-pro"
"@
    Write-Host $helpText -ForegroundColor Cyan
}

if ($Help) {
    Show-Help
    return
}

# === Проверка и запрос API-ключа ===
function Request-ApiKey {
    param (
        [string]$EnvVar = "GEMINI_API_KEY"
    )

    $apiKey = ${env:$EnvVar}  # корректное обращение к переменной окружения
    if (-not $apiKey) {
        Write-Launch "API-ключ не найден в переменной окружения `$EnvVar." -Type 'Warning'
        while ($true) {
            $apiKey = Read-Host "Введите Gemini API ключ"
            if ($apiKey) {
                ${env:$EnvVar} = $apiKey
                break
            }
            Write-Launch "API-ключ не может быть пустым. Повторите ввод." -Type 'Error'
        }
    }
    return $apiKey
}

if (-not $ApiKey) {
    $ApiKey = Request-ApiKey
}

# === Проверка системных требований ===
function Test-Prerequisites {
    Write-Launch "Проверка системных требований..." -Type 'Info'
    $issues = @()

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        $issues += "Требуется PowerShell 7+. Текущая: $($PSVersionTable.PSVersion)"
    } else {
        Write-Launch "PowerShell $($PSVersionTable.PSVersion) - OK" -Type 'Success'
    }

    try {
        $null = & gemini --version 2>&1
        Write-Launch "gemini-cli найден" -Type 'Success'
    } catch {
        $issues += "gemini-cli не найден в PATH"
    }

    $mcpScript = Join-Path $PSScriptRoot 'mcp-powershell-server/mcp-powershell-stdio.ps1'
    if (-not (Test-Path $mcpScript)) {
        $issues += "MCP сервер не найден: $mcpScript"
    } else {
        Write-Launch "MCP сервер найден" -Type 'Success'
    }

    return $issues
}

# === Запуск MCP сервера ===
function Start-MCPServer {
    Write-Launch "Запуск MCP PowerShell сервера..." -Type 'Info'
    $launcherScript = Join-Path $PSScriptRoot 'src/server/launch-mcp-stdio.ps1'

    try {
        $processArgs = @{
            FilePath     = 'pwsh'
            ArgumentList = @('-NoProfile', '-File', $launcherScript)
            WindowStyle  = 'Normal'
            PassThru     = $true
        }
        $serverProcess = Start-Process @processArgs
        Write-Launch "MCP сервер запущен (PID: $($serverProcess.Id))" -Type 'Success'
        Start-Sleep -Seconds 3
        return $serverProcess
    } catch {
        Write-Launch "Ошибка запуска MCP сервера: $($_.Exception.Message)" -Type 'Error'
        return $null
    }
}

# === Создание конфигурации MCP ===
function New-MCPConfiguration {
    Write-Launch "Создание конфигурации MCP..." -Type 'Info'
    $mcpServerPath = Join-Path $PSScriptRoot 'mcp-powershell-server/mcp-powershell-stdio.ps1'
    $mcpServerPath = Resolve-Path $mcpServerPath

    $mcpConfig = @{
        mcpServers = @{
            powershell = @{
                command = "pwsh"
                args    = @("-File", $mcpServerPath.ToString())
                env     = @{ POWERSHELL_EXECUTION_POLICY = "RemoteSigned" }
            }
        }
    }

    $configDir = Join-Path $PSScriptRoot 'config'
    if (-not (Test-Path $configDir)) { New-Item -Path $configDir -ItemType Directory -Force | Out-Null }

    $configFile = Join-Path $configDir 'mcp_servers.json'
    $mcpConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $configFile -Encoding UTF8

    Write-Launch "Конфигурация MCP сохранена: $configFile" -Type 'Success'
    return $configFile
}

# === Запуск gemini-cli ===
function Start-GeminiWithMCP {
    param([string]$ConfigFile)

    Write-Launch "Запуск gemini-cli с поддержкой MCP..." -Type 'Info'

    try {
        & gemini --mcp-config $ConfigFile -m $Model -i
    } catch {
        Write-Launch "Ошибка запуска gemini-cli: $($_.Exception.Message)" -Type 'Error'
    }
}

# === Основной рабочий процесс ===
$issues = Test-Prerequisites
if ($issues.Count -gt 0) {
    foreach ($i in $issues) { Write-Launch $i -Type 'Error' }
    return
}

$serverProcess = Start-MCPServer
if (-not $serverProcess) { return }

$configFile = New-MCPConfiguration

if ($LaunchGemini) {
    Start-GeminiWithMCP -ConfigFile $configFile
} else {
    Write-Launch "MCP сервер запущен и готов к работе. Для запуска gemini-cli используйте -LaunchGemini" -Type 'Success'
}
