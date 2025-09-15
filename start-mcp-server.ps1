# start-mcp-server.ps1
# Скрипт для запуска MCP PowerShell сервера
# -*- coding: utf-8 -*-

param(
    [Parameter(Mandatory=$false)]
    [int]$Port = 8090,
    
    [Parameter(Mandatory=$false)]
    [string]$ServerHost = "localhost",
    
    [Parameter(Mandatory=$false)]
    [switch]$Help,
    
    [Parameter(Mandatory=$false)]
    [switch]$Version,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = $null
)

# Версия сервера
$ServerVersion = "1.0.0"

# Функция показа справки
function Show-Help {
    Write-Host "MCP PowerShell Server v$ServerVersion" -ForegroundColor Green
    Write-Host ""
    Write-Host "Использование:" -ForegroundColor Yellow
    Write-Host "  .\start-mcp-server.ps1 [параметры]"
    Write-Host ""
    Write-Host "Параметры:" -ForegroundColor Yellow
    Write-Host "  -Port <число>           Порт для сервера (по умолчанию: 8090)"
    Write-Host "  -ServerHost <адрес>     Хост для сервера (по умолчанию: localhost)"
    Write-Host "  -ConfigFile <путь>      Путь к файлу конфигурации"
    Write-Host "  -Help                   Показать эту справку"
    Write-Host "  -Version                Показать версию"
    Write-Host ""
    Write-Host "Примеры:" -ForegroundColor Yellow
    Write-Host "  .\start-mcp-server.ps1                          # Запуск с настройками по умолчанию"
    Write-Host "  .\start-mcp-server.ps1 -Port 9090               # Запуск на порту 9090"
    Write-Host "  .\start-mcp-server.ps1 -ServerHost 0.0.0.0 -Port 8080 # Запуск на всех интерфейсах"
    Write-Host ""
}

# Функция показа версии
function Show-Version {
    Write-Host "MCP PowerShell Server v$ServerVersion" -ForegroundColor Green
}

# Обработка параметров командной строки
if ($Help) {
    Show-Help
    exit 0
}

if ($Version) {
    Show-Version
    exit 0
}

# Загрузка конфигурации из файла
if ($ConfigFile -and (Test-Path $ConfigFile)) {
    try {
        $config = Get-Content $ConfigFile | ConvertFrom-Json
        if ($config.Port) { $Port = $config.Port }
        if ($config.ServerHost) { $ServerHost = $config.ServerHost }
        Write-Host "Конфигурация загружена из файла: $ConfigFile" -ForegroundColor Green
    }
    catch {
        Write-Host "Ошибка загрузки конфигурации: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Проверка прав администратора для привилегированных портов
if ($Port -lt 1024 -and -not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Внимание: Для использования порта $Port может потребоваться запуск с правами администратора" -ForegroundColor Yellow
}

# Проверка доступности порта
try {
    $ipAddress = if ($ServerHost -eq "localhost") { 
        [System.Net.IPAddress]::Loopback 
    } else { 
        [System.Net.IPAddress]::Parse($ServerHost) 
    }
    
    $tcpListener = New-Object System.Net.Sockets.TcpListener($ipAddress, $Port)
    $tcpListener.Start()
    $tcpListener.Stop()
    Write-Host "Порт $Port на хосте $ServerHost доступен" -ForegroundColor Green
}
catch {
    Write-Host "Ошибка: Порт $Port на хосте $ServerHost уже используется или недоступен" -ForegroundColor Red
    Write-Host "Детали ошибки: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Получение пути к основному серверному скрипту
$serverScriptPath = Join-Path $PSScriptRoot "mcp-powershell-server.ps1"

if (-not (Test-Path $serverScriptPath)) {
    Write-Host "Ошибка: Файл сервера не найден: $serverScriptPath" -ForegroundColor Red
    exit 1
}

# Информация о запуске
Write-Host "Запуск MCP PowerShell Server v$ServerVersion" -ForegroundColor Green
Write-Host "Host: $ServerHost" -ForegroundColor Cyan
Write-Host "Port: $Port" -ForegroundColor Cyan
Write-Host "URL: http://$ServerHost`:$Port/" -ForegroundColor Cyan
Write-Host ""
Write-Host "Для остановки сервера нажмите Ctrl+C" -ForegroundColor Yellow
Write-Host ""

# Запуск сервера
try {
    & $serverScriptPath -Port $Port -ServerHost $ServerHost
}
catch {
    Write-Host "Ошибка запуска сервера: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}