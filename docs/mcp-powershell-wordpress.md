# 🖥️ MCP PowerShell WordPress Server

Специализированный сервер **Model Context Protocol (MCP)**, написанный на PowerShell, предназначенный для выполнения команд **WP-CLI (WordPress Command Line Interface)** в среде **Windows**.

Этот сервер позволяет вашему AI-агенту безопасно и структурированно взаимодействовать с установками WordPress через протокол MCP.

## 🚀 Установка и Настройка

Для успешного запуска MCP-сервера WP-CLI необходимо выполнить три основных шага:

1.  Установить **PowerShell** и настроить политику выполнения.
2.  Установить **PHP** и **WP-CLI** и добавить их в системный путь **PATH**.
3.  Настроить файлы конфигурации MCP-сервера.

### Шаг 1: Установка PHP и WP-CLI (Предварительные требования)

Сервер `mcp-powershell-wordpress.ps1` зависит от наличия исполняемого файла `wp` (WP-CLI) в вашем системном PATH.

1.  **Установите PHP:** Убедитесь, что у вас установлен PHP (например, через XAMPP, Laragon или просто официальный дистрибутив) и путь к **`php.exe`** добавлен в вашу системную переменную **PATH**.

    *Проверка:* Откройте PowerShell и выполните `php -v`.

2.  **Установите WP-CLI:**

      * Создайте папку для WP-CLI, например: `C:\wp-cli`.
      * Загрузите исполняемый файл WP-CLI:
        ```powershell
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar" -OutFile "C:\wp-cli\wp-cli.phar"
        ```
      * Создайте пакетный файл **`C:\wp-cli\wp.bat`** со следующим содержимым:
        ```batch
        @ECHO OFF
        php "C:\wp-cli\wp-cli.phar" %*
        ```
      * **Добавьте `C:\wp-cli` в системную переменную PATH** Windows.
        *Проверка:* Откройте **новое** окно PowerShell и выполните `wp --info`.

-----

### Шаг 2: Настройка MCP-сервера (JSON & PowerShell)

Файлы MCP-сервера находятся в репозитории: `mcp-powershell-server/src/servers/`.

#### 2.1. Конфигурационный файл (`mcp-powershell-wordpress.config.json`)

Создайте файл **`mcp-powershell-wordpress.config.json`** в том же каталоге, что и скрипт `mcp-powershell-wordpress.ps1`, со следующим содержимым:

```json
{
  "ServerConfig": {
    "Name": "WordPress CLI MCP Server",
    "Version": "1.2.0",
    "Description": "Выполняет команды WP-CLI через MCP протокол",
    "MaxExecutionTime": 300,
    "LogLevel": "INFO"
  }
}
```

#### 2.2. Настройка файла MCP-клиента

Добавьте следующую запись в вашу общую конфигурацию MCP-клиента (например, `mcp.json` или другой конфигурационный файл, который использует ваша модель), чтобы зарегистрировать новый сервер.

Предполагается, что PowerShell-серверы установлены в `C:/powershell/modules/mcp-powershell-server/src/servers/`. **Обязательно проверьте и скорректируйте этот путь\!**

```json
{
  "mcpServers": {
    // ... другие серверы ...
    "wordpress-cli": {
      "command": "pwsh",
      "args": [
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "C:/powershell/modules/mcp-powershell-server/src/servers/mcp-powershell-wordpress.ps1"
      ],
      "env": {
        "POWERSHELL_EXECUTION_POLICY": "RemoteSigned"
      },
      "description": "Dedicated server for executing WP-CLI commands."
    }
  }
}
```

-----

### Шаг 3: Использование

После регистрации сервера в конфигурации клиента MCP, ваш AI-агент получит доступ к инструменту `run-wp-cli`.

#### Доступный инструмент

| Имя инструмента | Описание |
| :--- | :--- |
| **`run-wp-cli`** | Выполняет команду WP-CLI на установке WordPress. Всегда возвращает структурированный JSON-вывод. |

#### Пример вызова (в формате, который генерирует AI):

```json
{
  "id": "1",
  "method": "tools/call",
  "params": {
    "name": "run-wp-cli",
    "arguments": {
      "commandArguments": "post list --post_type=post --number=5",
      "workingDirectory": "C:\\www\\my-wordpress-site" 
      // Важно: эта директория должна содержать файл wp-config.php
    }
  }
}
```

Сервер выполнит команду `wp post list --post_type=post --number=5 --format=json` в указанной рабочей директории и вернет результат в виде структурированного ответа MCP.