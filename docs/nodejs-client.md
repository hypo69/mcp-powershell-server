

## 🟢 Node.js клиент для MCP PowerShell Server (HTTPS + Token)

```javascript
import fetch from "node-fetch";
import https from "https";

// Создаём агент, который отключает проверку сертификатов (для self-signed)
const httpsAgent = new https.Agent({
  rejectUnauthorized: false
});

// Настройки сервера
const url = "https://localhost:8443/execute";
const headers = {
  "Authorization": "Bearer SuperSecretToken123",
  "Content-Type": "application/json"
};

// PowerShell команда
const payload = {
  command: "Get-Service | Select-Object -First 5 | ConvertTo-Json -Depth 3"
};

// Отправка запроса
(async () => {
  try {
    const response = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
      agent: httpsAgent
    });

    if (!response.ok) {
      console.error(`Ошибка ${response.status}: ${await response.text()}`);
      return;
    }

    const data = await response.json();
    console.log("Ответ от MCP PowerShell Server:");
    console.log(JSON.stringify(data, null, 2));
  } catch (err) {
    console.error("Ошибка при запросе:", err);
  }
})();
```

---

## ⚡ Пример вывода

```json
[
  {
    "Name": "Spooler",
    "Status": "Running",
    "DisplayName": "Print Spooler"
  },
  {
    "Name": "W32Time",
    "Status": "Stopped",
    "DisplayName": "Windows Time"
  }
]
```

