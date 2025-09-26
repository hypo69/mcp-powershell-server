<#
.SYNOPSIS
    Запускает PowerShell MCP HTTP/STDIO серверы и Gemini CLI в интерактивном режиме.
.DESCRIPTION
    Этот скрипт представляет собой комплексный лаунчер, написанный на чистом PowerShell,
    для развертывания локальной среды MCP.

    При запуске выполняются следующие действия:
    1.  Проверка зависимостей: Скрипт использует 'Get-Command' для проверки наличия
        исполняемых файлов 'pwsh.exe' (PowerShell 7+) и 'gemini.exe' в системной
        переменной PATH. Если что-либо отсутствует, выводится сообщение об ошибке,
        и скрипт завершает работу.

    2.  Интерактивная настройка: Для взаимодействия с пользователем используется
        кастомная функция 'Invoke-ChoiceWithTimeout', которая ожидает ввода (Y/N)
        в течение заданного времени, не блокируя при этом поток. Это позволяет
        реализовать меню с выбором по умолчанию по тайм-ауту.

    3.  Запуск серверов: Серверы HTTP и STDIO запускаются в отдельных, независимых
        окнах PowerShell с помощью команды 'Start-Process pwsh'. Параметр '-NoExit'
        гарантирует, что окна не закроются после запуска скриптов. Для каждого
        окна устанавливается информативный заголовок, а пути к серверным скриптам
        определяются динамически через переменную '$PSScriptRoot', что делает
        лаунчер переносимым.

    4.  Автоматическая конфигурация Gemini: Если пользователь соглашается, скрипт
        автоматически создает или перезаписывает конфигурационный файл 'mcp_servers.json'
        в стандартной директории Gemini ('%USERPROFILE%\.config\gemini'). Путь к
        STDIO-серверу корректно форматируется с экранированием обратных слэшей
        для соответствия стандарту JSON.

    5.  Запуск Gemini CLI: После создания конфигурации Gemini запускается в новом
        окне PowerShell с передачей всех необходимых аргументов: пути к файлу
        конфигурации, API-ключа (введенного пользователем) и флага интерактивного
        режима '-i'.
.NOTES
    File:      run.ps1
    Author:    hypo69
    Version:   v1.0.0
    Licence:   CC BY-NC 4.0 (https://creativecommons.org/licenses/by-nc/4.0/)
    Copyright: 2025 @hypo69
    Requires:  PowerShell 7+, Gemini CLI
#>

#region =========================[ Helper Function ]=========================

function Invoke-ChoiceWithTimeout {
    param(
        [string]$Prompt = "Ваш выбор?",
        [int]$TimeoutSeconds = 5,
        [char]$DefaultChoice = 'y'
    )

    Write-Host -NoNewline $Prompt
    $startTime = Get-Date

    while ((Get-Date - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        if ($Host.UI.RawUI.KeyAvailable) {
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            $char = [char]::ToLower($key.Character)
            if ($char -eq 'y' -or $char -eq 'n') {
                Write-Host $key.Character # Отображаем нажатую клавишу
                return $char
            }
        }
        Start-Sleep -Milliseconds 100
    }

    Write-Host $DefaultChoice # Отображаем выбор по умолчанию
    return $DefaultChoice
}

#endregion

#region =========================[ Pre-flight Checks ]=========================

Clear-Host
$Host.UI.RawUI.WindowTitle = "MCP Server & Gemini Launcher"

Write-Host "--- Проверка необходимых компонентов ---" -ForegroundColor Yellow

$pwshExists = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $pwshExists) {
    Write-Host "ОШИБКА: PowerShell 7+ ('pwsh.exe') не найден в PATH." -ForegroundColor Red
    Write-Host "Пожалуйста, установите PowerShell 7 и убедитесь, что он доступен." -ForegroundColor Red
    Read-Host "Нажмите Enter для выхода..."
    exit
}

$geminiExists = Get-Command gemini -ErrorAction SilentlyContinue
if (-not $geminiExists) {
    Write-Host "ОШИБКА: Gemini CLI ('gemini') не найден в PATH." -ForegroundColor Red
    Write-Host "Пожалуйста, установите Gemini CLI и убедитесь, что он доступен." -ForegroundColor Red
    Read-Host "Нажмите Enter для выхода..."
    exit
}

Write-Host "Все компоненты на месте." -ForegroundColor Green
Start-Sleep -Seconds 1

#endregion

#region =========================[ Main Logic ]=========================

Clear-Host
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "==       MCP PowerShell Server & Gemini Launcher       ==" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host
Write-Host "Этот скрипт сначала запустит HTTP и STDIO серверы, а затем"
Write-Host "предложит запустить Gemini CLI для взаимодействия с ними."
Write-Host

$prompt = "--> Запустить серверы с дефолтными настройками? [Y/n] (автовыбор через 3 сек): "
$choice = Invoke-ChoiceWithTimeout -Prompt $prompt -TimeoutSeconds 3 -DefaultChoice 'y'
Write-Host

# --- Server Configuration ---
if ($choice -eq 'n') {
    Clear-Host
    Write-Host "--- Режим пользовательских настроек ---" -ForegroundColor Yellow
    $httpPortInput = Read-Host "Введите порт для HTTP сервера (по умолч. 8090)"
    $httpHostInput = Read-Host "Введите хост для HTTP сервера (по умолч. localhost)"
    
    $httpPort = if ([string]::IsNullOrWhiteSpace($httpPortInput)) { 8090 } else { $httpPortInput }
    $httpHost = if ([string]::IsNullOrWhiteSpace($httpHostInput)) { "localhost" } else { $httpHostInput }
}
else {
    Write-Host "Выбран запуск с настройками по умолчанию (HTTP: localhost:8090)..."
    $httpPort = 8090
    $httpHost = "localhost"
}

# --- Launch Servers ---
Clear-Host
Write-Host "Запускаем серверы..." -ForegroundColor Green

# Абсолютные пути для надежности
$httpScriptPath = Join-Path $PSScriptRoot "src\servers\mcp-powershell-http.ps1"
$stdioScriptPath = Join-Path $PSScriptRoot "src\servers\mcp-powershell-stdio.ps1"

# Запуск HTTP сервера в новом окне
$httpArgs = "-NoExit -Command `"`$Host.UI.RawUI.WindowTitle = 'MCP HTTP Server'; & '$httpScriptPath' -Port $httpPort -ServerHost $httpHost`""
Start-Process pwsh -ArgumentList $httpArgs

# Запуск STDIO сервера в новом окне
$stdioArgs = "-NoExit -Command `"`$Host.UI.RawUI.WindowTitle = 'MCP STDIO Server'; & '$stdioScriptPath'`""
Start-Process pwsh -ArgumentList $stdioArgs

Write-Host "Даем серверам пару секунд на инициализацию..."
Start-Sleep -Seconds 2

# --- Gemini Configuration and Launch ---
Clear-Host
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "==               Серверы успешно запущены             ==" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host
Write-Host "HTTP сервер работает на $httpHost`:$httpPort"
Write-Host "STDIO сервер ожидает подключения."
Write-Host

$prompt = "--> Запустить Gemini CLI для взаимодействия с сервером? [Y/n] (автовыбор через 5 сек): "
$choice = Invoke-ChoiceWithTimeout -Prompt $prompt -TimeoutSeconds 5 -DefaultChoice 'y'

if ($choice -eq 'n') {
    Write-Host "`nПропускаем запуск Gemini."
} else {
    Write-Host
    $geminiApiKey = Read-Host "--> Введите ваш Gemini API ключ и нажмите Enter"

    if ([string]::IsNullOrWhiteSpace($geminiApiKey)) {
        Write-Host "`nAPI ключ не был введен. Невозможно запустить Gemini." -ForegroundColor Yellow
    } else {
        # Создание конфигурации для Gemini
        $configDir = Join-Path $env:USERPROFILE ".config\gemini"
        $configFile = Join-Path $configDir "mcp_servers.json"
        if (-not (Test-Path $configDir)) {
            New-Item -Path $configDir -ItemType Directory | Out-Null
        }

        # JSON требует двойных обратных слэшей в путях
        $jsonPath = $stdioScriptPath.Replace('\', '\\')

        $jsonContent = @"
{
  "mcpServers": {
    "powershell": {
      "command": "pwsh",
      "args": [
        "-File",
        "$jsonPath"
      ],
      "env": {}
    }
  }
}
"@
        Write-Host "`nСоздаем конфигурационный файл для Gemini в: $configFile" -ForegroundColor Gray
        Set-Content -Path $configFile -Value $jsonContent -Encoding UTF8

        Write-Host "Запускаем Gemini CLI в интерактивном режиме..." -ForegroundColor Green
        $geminiArgs = "-NoExit -Command `"`$Host.UI.RawUI.WindowTitle = 'Gemini CLI'; gemini --mcp-config '$configFile' --api-key '$geminiApiKey' -i`""
        Start-Process pwsh -ArgumentList $geminiArgs
    }
}

#endregion

Write-Host "`nГотово. Все необходимые окна запущены." -ForegroundColor Cyan
Read-Host "Это окно лаунчера можно закрыть. Нажмите Enter для выхода..."