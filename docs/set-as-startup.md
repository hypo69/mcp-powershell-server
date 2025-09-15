

## Общие подготовительные шаги (для всех ОС)

Прежде чем создавать службу, выполните эти действия:

1.  **Разместите скрипт в постоянном месте.** Не оставляйте его на Рабочем столе или в папке "Загрузки". Создайте для него стабильную директорию.
    *   **Windows:** `C:\Scripts\mcp-server\`
    *   **Linux/macOS:** `/opt/mcp-server/`

2.  **Используйте абсолютные пути.** Внутри скриптов служб всегда используйте полные пути к файлам и исполняемым файлам, так как у них может не быть привычного окружения пользователя.

3.  **Определитесь со скриптом.** Для службы почти всегда используется **`mcp-powershell-http.ps1`**, так как он предназначен для постоянной работы и прослушивания сетевых запросов.

---

## 윈도우

В Windows самый надежный способ превратить скрипт в службу — использовать утилиту **NSSM (Non-Sucking Service Manager)**, так как она лучше справляется с обработкой скриптов, чем встроенные средства.

### Шаг 1: Скачайте и настройте NSSM

1.  Скачайте последнюю версию [NSSM](https://nssm.cc/download).
2.  Распакуйте архив. Внутри будет папка `win64` (или `win32`). Скопируйте `nssm.exe` в папку, которая есть в системной переменной `PATH`, например, в `C:\Windows\System32`.

### Шаг 2: Установите службу

1.  Откройте **PowerShell** или **CMD** **от имени администратора**.

2.  Выполните команду для установки новой службы:
    ```powershell
    nssm install MCP-PowerShell-Server
    ```

3.  Откроется графический интерфейс NSSM. Настройте его на вкладке **Application**:
    *   **Path**: Укажите путь к исполняемому файлу PowerShell 7. Обычно это: `C:\Program Files\PowerShell\7\pwsh.exe`
    *   **Startup directory**: Укажите папку, где лежит ваш скрипт, например: `C:\Scripts\mcp-server`
    *   **Arguments**: Укажите аргументы для запуска вашего HTTP-сервера. **Обязательно используйте полные пути!**
        ```
        -NoProfile -File "C:\Scripts\mcp-server\mcp-powershell-http.ps1" -Port 8443 -AuthToken "MySecretTokenOnBoot"
        ```

    

4.  Нажмите кнопку **Install service**.

### Шаг 3: Управление службой

```powershell
# Запустить службу
nssm start MCP-PowerShell-Server
# Или
Start-Service MCP-PowerShell-Server

# Проверить статус
nssm status MCP-PowerShell-Server
# Или
Get-Service MCP-PowerShell-Server

# Остановить службу
nssm stop MCP-PowerShell-Server
# Или
Stop-Service MCP-PowerShell-Server

# Настроить автоматический запуск
Set-Service -Name MCP-PowerShell-Server -StartupType Automatic
```

---

## Linux (systemd)

На большинстве современных дистрибутивов Linux (Ubuntu, Debian, CentOS, Fedora) используется `systemd` для управления службами.

### Шаг 1: Подготовка

1.  Убедитесь, что PowerShell 7 установлен (`pwsh --version`).
2.  Скопируйте скрипт `mcp-powershell-http.ps1` в `/opt/mcp-server/`.

### Шаг 2: Создание файла службы (`.service`)

1.  Создайте файл юнита systemd с помощью текстового редактора:
    ```bash
    sudo nano /etc/systemd/system/mcp-server.service
    ```

2.  Вставьте в него следующую конфигурацию. **Обязательно проверьте путь к `pwsh`** (обычно `/usr/bin/pwsh` или `/opt/microsoft/powershell/7/pwsh`).

    ```ini
    [Unit]
    Description=MCP PowerShell HTTP Server
    After=network.target

    [Service]
    ExecStart=/usr/bin/pwsh -NoProfile -File /opt/mcp-server/mcp-powershell-http.ps1 -Port 8443 -AuthToken "MySecretTokenOnBoot"
    WorkingDirectory=/opt/mcp-server
    User=www-data  # Рекомендуется запускать от имени непривилегированного пользователя
    Restart=always
    RestartSec=10

    [Install]
    WantedBy=multi-user.target
    ```

    *   `Description`: Описание службы.
    *   `After=network.target`: Запускаться только после того, как поднимется сеть.
    *   `ExecStart`: Команда для запуска.
    *   `User`: Имя пользователя, от которого будет работать служба (более безопасно).
    *   `Restart=always`: Автоматически перезапускать службу, если она упадет.

### Шаг 3: Управление службой

```bash
# Перечитать конфигурацию systemd
sudo systemctl daemon-reload

# Включить автозапуск службы при старте системы
sudo systemctl enable mcp-server.service

# Запустить службу сейчас
sudo systemctl start mcp-server.service

# Проверить статус службы и посмотреть последние логи
sudo systemctl status mcp-server.service

# Посмотреть все логи службы
sudo journalctl -u mcp-server.service -f
```

---

## macOS (launchd)

В macOS для управления фоновыми процессами используется `launchd`. Конфигурация описывается в `.plist` файлах.

### Шаг 1: Подготовка

1.  Убедитесь, что PowerShell 7 установлен (обычно через Homebrew). Путь будет примерно `/usr/local/bin/pwsh`.
2.  Скопируйте скрипт `mcp-powershell-http.ps1` в `/opt/mcp-server/`.

### Шаг 2: Создание файла конфигурации (`.plist`)

1.  Создайте `.plist` файл в `/Library/LaunchDaemons/`. Имя файла должно быть уникальным, обычно используется формат обратного доменного имени.
    ```bash
    sudo nano /Library/LaunchDaemons/com.example.mcpserver.plist
    ```

2.  Вставьте в него следующую XML-конфигурацию:

    ```xml
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.example.mcpserver</string>
        <key>ProgramArguments</key>
        <array>
            <string>/usr/local/bin/pwsh</string>
            <string>-NoProfile</string>
            <string>-File</string>
            <string>/opt/mcp-server/mcp-powershell-http.ps1</string>
            <string>-Port</string>
            <string>8443</string>
            <string>-AuthToken</string>
            <string>MySecretTokenOnBoot</string>
        </array>
        <key>WorkingDirectory</key>
        <string>/opt/mcp-server</string>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
        <key>StandardOutPath</key>
        <string>/var/log/mcp-server.log</string>
        <key>StandardErrorPath</key>
        <string>/var/log/mcp-server-error.log</string>
    </dict>
    </plist>
    ```

    *   `Label`: Уникальное имя демона.
    *   `ProgramArguments`: Массив, где каждый элемент — это часть команды (путь, флаг, значение).
    *   `RunAtLoad`: Запускать при загрузке системы.
    *   `KeepAlive`: Перезапускать, если процесс завершится.
    *   `StandardOutPath`/`StandardErrorPath`: Пути к лог-файлам.

### Шаг 3: Управление службой

```bash
# Загрузить и запустить демона (служба начнет работать)
sudo launchctl load /Library/LaunchDaemons/com.example.mcpserver.plist

# Остановить и выгрузить демона
sudo launchctl unload /Library/LaunchDaemons/com.example.mcpserver.plist

# Проверить, что лог-файлы создаются
tail -f /var/log/mcp-server.log
```
После загрузки (`load`) демон будет автоматически запускаться при каждом старте macOS.