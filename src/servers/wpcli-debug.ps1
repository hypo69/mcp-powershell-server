# \file run-my-wordpress-tasks.ps1
#
# Простой скрипт для прямого выполнения команд WP-CLI

# --- НАСТРОЙКИ ---

# 1. Путь к корневой директории вашего сайта WordPress
$WordPressPath = "E:\xampp\htdocs\domains\davidka.net\public_html" # ⚠️ УКАЖИТЕ ВАШ ПУТЬ!

# 2. Список команд WP-CLI для выполнения
#    Просто пишите команды, как в командной строке, без "wp" в начале
$CommandsToRun = @(
    "core version",
    "plugin list --status=active",
    "theme list --status=active",
    "plugin update --all"
)

# --- КОНЕЦ НАСТРОЕК ---


# --- ОСНОВНОЙ КОД ---

Write-Host " [i] Начинаю выполнение задач для сайта в '$WordPressPath'..." -ForegroundColor Cyan
Write-Host ("-" * 60)

# Запоминаем текущую директорию, чтобы вернуться в нее потом
$OriginalLocation = Get-Location

try {
    # Переходим в директорию WordPress. Это обязательно для работы WP-CLI.
    Set-Location -Path $WordPressPath

    # Выполняем каждую команду из списка
    foreach ($command in $CommandsToRun) {
        Write-Host " [>] Выполняю команду: wp $command" -ForegroundColor Yellow
        
        try {
            # Напрямую запускаем WP-CLI
            wp --allow-root $command
            Write-Host " [✓] Команда выполнена успешно." -ForegroundColor Green
        }
        catch {
            # Если команда завершилась с ошибкой, выводим ее
            Write-Host " [✗] Произошла ошибка при выполнении команды:" -ForegroundColor Red
            # $_ - это сама ошибка
            Write-Output $_
        }
        
        Write-Host ("-" * 60)
    }
}
catch {
    Write-Host " [✗] Критическая ошибка: не удалось перейти в директорию '$WordPressPath'." -ForegroundColor Red
    Write-Host $_.Exception.Message
}
finally {
    # Возвращаемся в исходную директорию, где бы мы ни находились
    Set-Location -Path $OriginalLocation
}

Write-Host " [i] Все задачи выполнены." -ForegroundColor Cyan