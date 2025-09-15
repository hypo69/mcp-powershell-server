

## 📑 Таблица методов MCP

| Метод MCP         | Описание                        | Параметры             | Пример запроса                                                                                                                               |                                   |
| ----------------- | ------------------------------- | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `initialize`      | Инициализация сервера MCP       | `{}`                  | \`echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'                                                                          | pwsh .\mcp-powershell-stdio.ps1\` |
| `tools/call`      | Выполнение PowerShell скрипта   | `{ name, arguments }` | \`echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"run-script","arguments":{"script":"Get-Date","timeoutSeconds":10}}}' | pwsh .\mcp-powershell-stdio.ps1\` |
| `tools/list`      | Получение списка инструментов   | `{}`                  | \`echo '{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}'                                                                          | pwsh .\mcp-powershell-stdio.ps1\` |
| `tools/status`    | Получение статуса сервера       | `{}`                  | \`echo '{"jsonrpc":"2.0","id":4,"method":"tools/status","params":{}}'                                                                        | pwsh .\mcp-powershell-stdio.ps1\` |
| `tools/logs`      | Получение последних логов       | `{ count }`           | \`echo '{"jsonrpc":"2.0","id":5,"method":"tools/logs","params":{"count":10}}'                                                                | pwsh .\mcp-powershell-stdio.ps1\` |
| `tools/terminate` | Завершение выполнения скрипта   | `{ id }`              | \`echo '{"jsonrpc":"2.0","id":6,"method":"tools/terminate","params":{"id":123}}'                                                             | pwsh .\mcp-powershell-stdio.ps1\` |
| `tools/update`    | Обновление конфигурации сервера | `{ config }`          | \`echo '{"jsonrpc":"2.0","id":7,"method":"tools/update","params":{"config":{"LogLevel":"DEBUG"}}}'                                           | pwsh .\mcp-powershell-stdio.ps1\` |

---

## 🔄 Схема работы MCP PowerShell Server

```
           +-------------------+
           | MCP Клиент        |
           | (например IDE)    |
           +---------+---------+
                     |
           JSON-RPC через STDIO/HTTP(S)
                     |
           +---------v---------+
           | MCP Server        |
           | PowerShell Bridge |
           +---------+---------+
                     |
             Запуск скрипта
                     |
           +---------v---------+
           | PowerShell Engine |
           | (отдельный proc)  |
           +---------+---------+
                     |
                Результат/Логи
                     |
           +---------v---------+
           | MCP Клиент        |
           +-------------------+
```

---

## 📜 Лицензия

MIT © [hypo69](https://github.com/hypo69/mcp-powershell-server)

