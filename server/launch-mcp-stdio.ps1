## \file mcp-powershell-server/launch-mcp-stdio.ps1
# -*- coding: utf-8 -*-
#! .pyenv/bin/powershell

<#
.SYNOPSIS
    Launcher для MCP PowerShell сервера в STDIO режиме
    
.DESCRIPTION
    Простой launcher который запускает MCP сервер в STDIO режиме 
    и показывает статус в отдельном окне.
    
.EXAMPLE
    .\launch-mcp-stdio.ps1
#>

[CmdletBinding()]
param()

# Настройка вывода
$Host.UI.RawUI.WindowTitle = "MCP PowerShell Server (STDIO)"
Clear-Host

# Функция статуса
function Write-ServerStatus {
    param(
        [string]$Message,
        [string]$Type = 'Info'
    )
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Type) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Info' { 'Cyan' }
        default { 'White' }
    }
    Write-Host "[$timestamp] $Message" -ForegroundColor $color
}

# Заголовок
Write-Host @"
╔══════════════════════════════════════════════════════════╗
║              MCP PowerShell Server (STDIO)               ║
║                     Статус сервера                      ║
╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Host ""
Write-ServerStatus "Инициализация MCP PowerShell сервера..." -Type 'Info'
Write-ServerStatus "Режим работы: STDIO (стандартный ввод/вывод)" -Type 'Info'
Write-ServerStatus "Протокол: MCP 2024-11-05" -Type 'Info'
Write-Host ""

# Информация о сервере
$serverScript = Join-Path $PSScriptRoot 'mcp-powershell-stdio.ps1'
if (-not (Test-Path $serverScript)) {
    Write-ServerStatus "ОШИБКА: Файл сервера не найден: $serverScript" -Type 'Error'
    Write-Host ""
    Write-Host "Нажмите любую клавишу для выхода..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-ServerStatus "Файл сервера найден: $serverScript" -Type 'Success'
Write-Host ""

# Показ статуса в течение работы
$statusJob = Start-Job -ScriptBlock {
    param($ServerScript)
    
    while ($true) {
        Start-Sleep -Seconds 5
        
        # Проверка активности через количество процессов PowerShell
        $psProcesses = Get-Process -Name 'pwsh*' -ErrorAction SilentlyContinue
        $timestamp = Get-Date -Format "HH:mm:ss"
        
        Write-Host "[$timestamp] Сервер работает | PowerShell процессов: $($psProcesses.Count)" -ForegroundColor Green
    }
} -ArgumentList $serverScript

Write-ServerStatus "Запуск MCP сервера в STDIO режиме..." -Type 'Success'
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║  ВНИМАНИЕ: Это окно должно оставаться открытым!          ║" -ForegroundColor Yellow  
Write-Host "║  Сервер работает через стандартные потоки ввода-вывода   ║" -ForegroundColor Yellow
Write-Host "║  Для остановки используйте Ctrl+C                       ║" -ForegroundColor Yellow
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""

try {
    # Запуск основного сервера
    & $serverScript
} catch {
    Write-ServerStatus "Критическая ошибка сервера: $($_.Exception.Message)" -Type 'Error'
} finally {
    # Очистка фоновых задач
    if ($statusJob) {
        Stop-Job -Job $statusJob -ErrorAction SilentlyContinue
        Remove-Job -Job $statusJob -ErrorAction SilentlyContinue
    }
    
    Write-Host ""
    Write-ServerStatus "MCP сервер завершён" -Type 'Warning'
    Write-Host ""
    Write-Host "Нажмите любую клавишу для закрытия окна..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}