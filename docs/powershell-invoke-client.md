
## 🔹 PowerShell клиент (Invoke-RestMethod)

```powershell
# Настройки сервера
$Url = "https://localhost:8443/execute"
$Token = "SuperSecretToken123"

# Заголовки авторизации
$Headers = @{
    "Authorization" = "Bearer $Token"
    "Content-Type"  = "application/json"
}

# Команда PowerShell для выполнения на сервере
$Payload = @{
    command = "Get-Process | Select-Object -First 5 | ConvertTo-Json -Depth 3"
} | ConvertTo-Json -Depth 3

# Игнорируем self-signed сертификат (для теста)
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

# Отправляем запрос
try {
    $Response = Invoke-RestMethod -Uri $Url -Method Post -Headers $Headers -Body $Payload
    Write-Host "Ответ от MCP PowerShell Server:" -ForegroundColor Green
    $Response | ConvertTo-Json -Depth 5 | Out-String
} catch {
    Write-Host "Ошибка запроса: $($_.Exception.Message)" -ForegroundColor Red
}
```

---

## ⚡ Пример вывода

```json
[
  {
    "Name": "pwsh",
    "Id": 12345,
    "CPU": 0.03
  },
  {
    "Name": "explorer",
    "Id": 6789,
    "CPU": 0.12
  }
]
```
