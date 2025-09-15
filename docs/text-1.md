3. Установка для http/https

Если вы используете кастомный MCP клиент, поддерживающий HTTP/HTTPS, укажите путь к модулю в конфиге клиента:

{
  "mcpServers": {
    "powershell": {
      "command": "pwsh",
      "args": [
        "-NoProfile",
        "-Command",
        "Import-Module 'C:/path/to/mcp-powershell-server.psd1'; Start-McpServer -Protocol Http -Port 8080"
      ]
    }
  }
}

⚙️ Использование
1. Запуск сервера
Import-Module mcp-powershell-server
Start-McpServer

2. Запуск с протоколом stdio
pwsh -NoProfile -Command "Import-Module mcp-powershell-server; Start-McpServer -Protocol Stdio"

3. Запуск с протоколом http
pwsh -NoProfile -Command "Import-Module mcp-powershell-server; Start-McpServer -Protocol Http -Port 8080"

🖥️ Примеры
Получение списка процессов
Get-Process | Select-Object -First 5

Проверка сетевых подключений
Test-NetConnection google.com -Port 443

Получение списка файлов
Get-ChildItem -Path C:\ -Recurse -ErrorAction SilentlyContinue | Select-Object -First 10







🛠 Конфигурация для Claude Desktop

Отлично 🚀
Вот полный пример **конфига для Claude Desktop с HTTP** — так ты сможешь подключать `mcp-powershell-server` через `localhost:8080` вместо `stdio`.

Файл `claude_desktop_config.json` (расположен в `%APPDATA%\Claude\claude_desktop_config.json` на Windows или `~/.config/Claude/claude_desktop_config.json` на Linux/macOS):

```json
{
  "mcpServers": {
    "powershell-http": {
      "command": "pwsh",
      "args": [
        "-NoProfile",
        "-Command",
        "Import-Module 'C:/Users/USERNAME/Documents/WindowsPowerShell/Modules/mcp-powershell-server/mcp-powershell-server.psd1'; Start-McpServer -Protocol Http -Port 8080"
      ]
    }
  }
}
```

👉 Замени `USERNAME` на своё имя пользователя.

---

⚠️ Особенности:

* `-Protocol Http` — сервер запускается как HTTP API.
* `-Port 8080` — порт можно заменить, если он занят.
* Подключение будет доступно только на `localhost`, т.е. безопасно для локального использования.



👉 Замени USERNAME на своё имя пользователя и путь до установленного модуля.



Супер ⚡ Тогда давай сделаем вариант с **HTTPS + токен-авторизацией**.

---

## 🔐 Конфиг Claude Desktop (HTTPS + Token)

Файл `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "powershell-https": {
      "command": "pwsh",
      "args": [
        "-NoProfile",
        "-Command",
        "Import-Module 'C:/Users/USERNAME/Documents/WindowsPowerShell/Modules/mcp-powershell-server/mcp-powershell-server.psd1'; Start-McpServer -Protocol Https -Port 8443 -CertPath 'C:/certs/mcp-cert.pfx' -CertPassword (ConvertTo-SecureString 'your-cert-password' -AsPlainText -Force) -AuthToken 'SuperSecretToken123'"
      ]
    }
  }
}
```

---

## ⚙️ Что здесь важно

1. **Сертификат**

   * Используется файл `mcp-cert.pfx`.
   * Его можно сгенерировать, например, через:

     ```powershell
     New-SelfSignedCertificate -DnsName "localhost" -CertStoreLocation "Cert:\CurrentUser\My"
     ```
   * Потом экспортировать в `.pfx` вместе с паролем.

2. **Параметры запуска**

   * `-Protocol Https` — сервер стартует в HTTPS-режиме.
   * `-Port 8443` — порт (можно менять).
   * `-CertPath` — путь к сертификату (`.pfx`).
   * `-CertPassword` — пароль от PFX.
   * `-AuthToken` — обязательный токен для авторизации клиентов.

3. **Авторизация**

   * Теперь любой запрос к серверу должен содержать HTTP-заголовок:

     ```
     Authorization: Bearer SuperSecretToken123
     ```

---

## 🔒 Пример запуска вручную

```powershell
Import-Module mcp-powershell-server
Start-McpServer -Protocol Https -Port 8443 `
  -CertPath "C:/certs/mcp-cert.pfx" `
  -CertPassword (ConvertTo-SecureString "your-cert-password" -AsPlainText -Force) `
  -AuthToken "SuperSecretToken123"
```

---

👉 Таким образом у тебя будет:

* `stdio` режим (по умолчанию, локальный, безопасный).
* `http` режим (удобно для разработки, только localhost).
* `https + token` режим (подходит для работы в сети, с защитой).







📦 Репозиторий

https://github.com/hypo69/mcp-powershell-server