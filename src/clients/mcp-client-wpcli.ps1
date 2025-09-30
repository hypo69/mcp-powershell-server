# mcp-client-wpcli.ps1 - Клиент для вызова WP-CLI MCP сервера через HTTP

#region Настройки сервера и авторизации

# ⚠️ ПРЕДУПРЕЖДЕНИЕ: Замените эти значения на актуальные для вашего HTTP-сервера
$Url = "https://localhost:8443/execute"
$Token = "SuperSecretToken123"

# Заголовки авторизации
$Headers = @{
    "Authorization" = "Bearer $Token"
    "Content-Type"  = "application/json"
}

#endregion

#region Подготовка MCP-запроса

# Директория, где установлена рабочая копия WordPress. 
# ⚠️ ОБЯЗАТЕЛЬНО замените на ваш путь!
$WordPressPath = "E:\xampp\htdocs\domains\davidka.net\public_html" 

# MCP-запрос: вызов инструмента "run-wp-cli"
# Аргументы WP-CLI: 'user list' для получения списка пользователей
$MCPRequest = @{
    jsonrpc = "2.0"
    id      = (New-Guid).ToString() # Уникальный ID для запроса
    method  = "tools/call"
    params  = @{
        name = "run-wp-cli"
        arguments = @{
            commandArguments = "user list" 
            workingDirectory = $WordPressPath
        }
    }
}

# Преобразование полезной нагрузки в JSON
$Payload = $MCPRequest | ConvertTo-Json -Depth 5

#endregion

#region Обработка самоподписанных сертификатов (для теста)

# Игнорируем self-signed сертификат, что часто необходимо при локальной разработке по HTTPS
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

#endregion

#region Отправка запроса и обработка ответа

Write-Host "Отправка MCP-запроса на $Url..." -ForegroundColor Cyan
Write-Host "Выполняемая команда: wp user list в директории $WordPressPath" -ForegroundColor DarkCyan

try {
    # Отправляем запрос
    # NOTE: В более современных версиях PowerShell (Core) можно использовать параметр -SkipCertificateCheck
    $Response = Invoke-RestMethod -Uri $Url -Method Post -Headers $Headers -Body $Payload -ContentType "application/json" -ErrorAction Stop
    
    Write-Host "`n--- Ответ от MCP сервера ---" -ForegroundColor Green
    
    # Вывод результата в красивом формате JSON
    $Response | ConvertTo-Json -Depth 5 | Write-Host
    
    # Проверка на наличие ошибки в ответе MCP
    if ($Response.error -ne $null) {
        Write-Host "`nОшибка сервера (Code $($Response.error.code)): $($Response.error.message)" -ForegroundColor Red
    }
    
    # Если результат содержит контент (инструмент tools/call)
    if ($Response.result -ne $null -and $Response.result.content -ne $null) {
        $wpCliResult = $Response.result.content | Where-Object { $_.type -eq 'text' }
        Write-Host "`n--- WP-CLI Вывод (из поля content) ---" -ForegroundColor Yellow
        $wpCliResult.text -join "`n" | Write-Host
    }

} catch {
    # Обработка ошибок сетевого уровня или ошибки 500
    Write-Host "`nКритическая ошибка запроса:" -ForegroundColor Red
    Write-Host "$($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response -ne $null) {
        Write-Host "Статус HTTP: $($_.Exception.Response.StatusCode.Value__) $($_.Exception.Response.StatusDescription)" -ForegroundColor Red
    }
}

#endregion
