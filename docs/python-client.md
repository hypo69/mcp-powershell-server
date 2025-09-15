

## 🐍 Python клиент для MCP PowerShell Server (HTTPS + Token)

```python
import requests
import json
import urllib3

# Отключаем предупреждения о self-signed сертификатах
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Настройки сервера
url = "https://localhost:8443/execute"
headers = {
    "Authorization": "Bearer SuperSecretToken123",
    "Content-Type": "application/json"
}

# Команда PowerShell для выполнения
payload = {
    "command": "Get-Process | Select-Object -First 3 | ConvertTo-Json -Depth 3"
}

# Отправка POST-запроса
response = requests.post(url, headers=headers, data=json.dumps(payload), verify=False)

# Проверка результата
if response.status_code == 200:
    try:
        result = response.json()
        print(json.dumps(result, indent=2, ensure_ascii=False))
    except Exception:
        print("Ответ не JSON:")
        print(response.text)
else:
    print(f"Ошибка {response.status_code}: {response.text}")
```

---

## ⚡ Что важно

* `verify=False` отключает проверку сертификата (для самоподписанного).
  Если используешь нормальный сертификат — убери.
* `Authorization: Bearer SuperSecretToken123` — токен авторизации.
* Ответ возвращается в JSON, удобно парсить прямо в Python.

---

## 🧪 Пример вывода

```json
[
  {
    "Name": "pwsh",
    "Id": 12345,
    "CPU": 0.05,
    "WorkingSet": 543210
  },
  {
    "Name": "explorer",
    "Id": 6789,
    "CPU": 0.10,
    "WorkingSet": 987654
  }
]
```

