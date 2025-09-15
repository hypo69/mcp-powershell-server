
# MCP PowerShell HTTP(S) – быстрый старт

## 1️⃣ Запуск HTTP(S) сервера

```powershell
# Запуск HTTP сервера на порту 8091 с токеном авторизации
powershell.exe -File .\mcp-powershell-http.ps1 `
    -Port 8091 `
    -ServerHost "localhost" `
    -AuthToken "supersecrettoken"
```

* Для HTTPS добавьте параметр `-CertThumbprint "<Thumbprint>"`.
* Сервер принимает JSON-RPC 2.0 запросы через POST.

---

## 2️⃣ Тестирование с помощью PowerShell

### Пример: инициализация соединения

```powershell
$Url = "http://localhost:8091/"
$Token = "supersecrettoken"

$Body = @{
    jsonrpc = "2.0"
    id = 1
    method = "initialize"
    params = @{
        protocolVersion = "2024-11-05"
        capabilities = @{}
        clientInfo = @{
            name = "PowerShellClient"
            version = "1.0"
        }
    }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri $Url -Method Post -Body $Body -Headers @{ Authorization = "Bearer $Token" } -ContentType "application/json"
```

---

### Пример: выполнение скрипта

```powershell
$ScriptRequest = @{
    jsonrpc = "2.0"
    id = 2
    method = "tools/call"
    params = @{
        name = "run-script"
        arguments = @{
            script = "Get-Date"
            timeoutSeconds = 10
        }
    }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri $Url -Method Post -Body $ScriptRequest -Headers @{ Authorization = "Bearer $Token" } -ContentType "application/json"
```

**Результат:**

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "content": [
      { "type": "text", "text": "Sunday, September 15, 2025 7:00:00 PM" }
    ]
  }
}
```

---

## 3️⃣ Тестирование с помощью curl

### Инициализация соединения

```bash
curl -X POST "http://localhost:8091/" \
  -H "Authorization: Bearer supersecrettoken" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
```

### Выполнение скрипта

```bash
curl -X POST "http://localhost:8091/" \
  -H "Authorization: Bearer supersecrettoken" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"run-script","arguments":{"script":"Get-Date","timeoutSeconds":10}}}'
```

---

## 4️⃣ Переключение с STDIO на HTTP

1. **Вместо передачи запроса через конвейер**:

```powershell
echo '{"jsonrpc":"2.0","id":1,"method":"initialize"}' | .\mcp-powershell-stdio.ps1
```

используем:

```powershell
Invoke-RestMethod -Uri $Url -Method Post -Body $Body -Headers @{ Authorization = "Bearer $Token" } -ContentType "application/json"
```

2. **Все методы MCP** остаются идентичными (`tools/list`, `tools/call`), меняется только транспорт: **STDIO → HTTP(S)**.

3. **Bearer-токен** обеспечивает безопасный доступ для удалённых клиентов.

---

## 5️⃣ Практические советы

* Для HTTPS используйте **самоподписанный сертификат** на локальной машине или корпоративный.
* Настройте firewall и разрешите только необходимые порты (8091 по умолчанию).
* Для автоматизации тестов используйте скрипты PowerShell с `Invoke-RestMethod` или `curl` в CI/CD пайплайнах.
* Логирование и таймауты работают аналогично STDIO серверу.

---

Если хочешь, я могу сделать **готовый PowerShell шаблон для пакетной отправки нескольких MCP-запросов через HTTP(S)** с логированием и обработкой ошибок, полностью заменяющий STDIO pipeline.

Хочешь, чтобы я его сделал?
