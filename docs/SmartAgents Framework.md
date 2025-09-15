# SmartAgents Framework: Создание специализированных AI-агентов на PowerShell

## Введение

SmartAgents Framework — это модульная система для создания специализированных AI-агентов на PowerShell, использующая Google Gemini API. Фреймворк позволяет быстро создавать интерактивных помощников с сохранением истории диалогов и настраиваемой логикой обработки команд.

## Архитектура фреймворка

### Основные компоненты

1. **Ядро фреймворка** (`SmartAgents.psm1`) - центральный модуль с общими функциями
2. **Библиотеки агентов** (папка `Agents/`) - специализированные модули для конкретных задач
3. **Конфигурация модуля** (`SmartAgents.psd1`) - манифест PowerShell модуля
4. **Системы управления** - скрипты для установки и управления

### Структура проекта

```
SmartAgents/
├── SmartAgents.psm1           # Ядро фреймворка
├── SmartAgents.psd1           # Манифест модуля
├── install.ps1                # Скрипт установки
├── Manage-Agents.ps1          # Управление агентами
├── Agents/                    # Библиотеки агентов
│   ├── Find-Spec.ps1          # Агент поиска спецификаций
│   └── Flight-Plan.ps1        # Агент планирования перелетов
├── FindSpec/                  # Конфигурация агента поиска
│   └── .gemini/
│       ├── GEMINI.md          # Системные инструкции
│       └── ShowHelp.md        # Справка пользователя
└── FlightPlan/                # Конфигурация агента перелетов
    └── .gemini/
        ├── GEMINI.md          # Системные инструкции
        └── ShowHelp.md        # Справка пользователя
```

## Основные принципы работы

### 1. Модульная архитектура

Каждый агент представляет собой отдельную функцию PowerShell с собственной конфигурацией и логикой:

```powershell
function Start-YourAgent {
    [CmdletBinding()]
    param(
        [ValidateSet('gemini-2.5-pro', 'gemini-2.5-flash')]
        [string]$Model = 'gemini-2.5-flash',
        [string]$ApiKey
    )
    
    $agentRoot = $PSScriptRoot 
    $Config = New-GeminiConfig -AppName 'Ваш агент' -Emoji '🤖' -SessionPrefix 'your_session' -AgentRoot $agentRoot
    
    # Логика агента...
}
```

### 2. Единая система конфигурации

Функция `New-GeminiConfig` создает стандартную конфигурацию для всех агентов:

- **AgentRoot** - корневая папка агента
- **HistoryDir** - папка для истории диалогов
- **ConfigDir** - папка конфигурационных файлов
- **SessionPrefix** - префикс для файлов сессий
- **AppName** - название приложения
- **Emoji** - эмодзи в приглашении
- **Color** - цветовая схема интерфейса

### 3. Система обработки команд

Каждый агент имеет собственный обработчик команд:

```powershell
function Command-Handler-YourAgent {
    param([string]$Command, [string]$HistoryFilePath)
    switch ($Command.Trim().ToLower()) {
        '?'         { Show-YourAgentHelp; return 'continue' }
        'history'   { Show-History -HistoryFilePath $HistoryFilePath; return 'continue' }
        'clear'     { Clear-History -HistoryFilePath $HistoryFilePath; return 'continue' }
        'exit'      { return 'break' }
        'quit'      { return 'break' }
        default     { return $null }
    }
}
```

### 4. Интеграция с Gemini API

Фреймворк включает централизованную функцию `Invoke-GeminiAPI` с обработкой ошибок:

- Автоматическое определение ошибок квоты (429)
- Очистка служебных сообщений
- Единообразная обработка ответов

### 5. JSON-обработка и интерактивность

Ответы Gemini автоматически проверяются на JSON-формат и при обнаружении отображаются в интерактивной таблице `Out-ConsoleGridView`, позволяя пользователю выбирать данные для последующих запросов.

## Создание собственного агента

### Шаг 1: Создание функции агента

Создайте файл в папке `Agents/`:

```powershell
# Agents/My-Agent.ps1
function Start-MyAgent {
    [CmdletBinding()]
    param(
        [ValidateSet('gemini-2.5-pro', 'gemini-2.5-flash')]
        [string]$Model = 'gemini-2.5-flash',
        [string]$ApiKey
    )
    
    $agentRoot = $PSScriptRoot 
    $Config = New-GeminiConfig -AppName 'Мой агент' -Emoji '🎯' -SessionPrefix 'my_session' -AgentRoot $agentRoot

    # Специализированные функции агента
    function Show-MyAgentHelp {
        $helpFilePath = Join-Path $Config.ConfigDir "ShowHelp.md"
        if (Test-Path $helpFilePath) {
            Get-Content -Path $helpFilePath -Raw | Write-Host
        } else {
            Write-Warning "Файл справки не найден: $helpFilePath"
        }
    }

    function Command-Handler-MyAgent {
        param([string]$Command, [string]$HistoryFilePath)
        switch ($Command.Trim().ToLower()) {
            '?'         { Show-MyAgentHelp; return 'continue' }
            'history'   { Show-History -HistoryFilePath $HistoryFilePath; return 'continue' }
            'clear'     { Clear-History -HistoryFilePath $HistoryFilePath; return 'continue' }
            'exit'      { return 'break' }
            'quit'      { return 'break' }
            default     { return $null }
        }
    }

    # Инициализация сессии
    try {
        $historyFilePath = Initialize-GeminiSession -Config $Config -ApiKey $ApiKey
    } catch {
        Write-ColoredMessage "Ошибка инициализации: $($_.Exception.Message)" -Color $Config.Color.Error
        return
    }

    Write-Host "`nДобро пожаловать в $($Config.AppName)! Модель: '$Model'. Введите '?' для помощи, 'exit' для выхода.`n"
    $selectionContextJson = $null 
    
    # Основной цикл взаимодействия
    while ($true) {
        $promptText = if ($selectionContextJson) { "$($Config.Emoji)AI [Выборка активна] :) > " } else { "$($Config.Emoji)AI :) > " }
        Write-ColoredMessage -Message $promptText -Color $Config.Color.Prompt -NoNewline
        $UserPrompt = Read-Host
        
        $commandResult = Command-Handler-MyAgent -Command $UserPrompt -HistoryFilePath $historyFilePath
        if ($commandResult -eq 'break') { break }
        if ($commandResult -eq 'continue') { continue }
        if ([string]::IsNullOrWhiteSpace($UserPrompt)) { continue }

        Write-ColoredMessage "Обработка запроса..." -Color $Config.Color.Processing
        
        # Формирование полного промпта с историей и контекстом
        $historyContent = if (Test-Path $historyFilePath) { Get-Content -Path $historyFilePath -Raw } else { "" }
        $fullPrompt = "### ИСТОРИЯ`n$historyContent`n"
        if ($selectionContextJson) {
            $fullPrompt += "### ВЫБОРКА`n$selectionContextJson`n"
            $selectionContextJson = $null
        }
        $fullPrompt += "### НОВЫЙ ЗАПРОС`n$UserPrompt"
        
        # Запрос к Gemini
        $ModelResponse = Invoke-GeminiAPI -Prompt $fullPrompt -Model $Model -Config $Config
        
        if ($ModelResponse) {
            $jsonObject = ConvertTo-JsonData -GeminiResponse $ModelResponse
            if ($jsonObject) {
                Write-ColoredMessage "`n--- Результат (JSON) ---`n" -Color $Config.Color.Success
                $gridSelection = $jsonObject | Out-ConsoleGridView -Title "Выберите данные для следующего запроса" -OutputMode Multiple
                if ($gridSelection) {
                    $selectionContextJson = $gridSelection | ConvertTo-Json -Compress -Depth 10
                    Write-ColoredMessage "Выборка сохранена. Добавьте ваш следующий запрос." -Color $Config.Color.Selection
                }
            } else {
                Write-ColoredMessage $ModelResponse -Color 'White'
            }
            Add-ChatHistory -HistoryFilePath $historyFilePath -UserPrompt $UserPrompt -ModelResponse $ModelResponse
        }
    }
    Write-ColoredMessage "Завершение работы." -Color $Config.Color.Success
}
```

### Шаг 2: Создание конфигурационных файлов

Создайте папку для конфигурации агента:

```
MyAgent/
└── .gemini/
    ├── GEMINI.md      # Системные инструкции для AI
    └── ShowHelp.md    # Справка для пользователя
```

**GEMINI.md** - инструкции для AI модели:

```markdown
# СИСТЕМНАЯ ИНСТРУКЦИЯ ДЛЯ My-Agent AI

## 1. Твоя Роль и Главная Задача

Ты — специализированный помощник для [описание функций агента].

## 2. Основные Директивы

### 2.1. Форматирование ответов
- Всегда возвращай структурированные данные в JSON формате
- Используй формат массива объектов: [{"Параметр": "значение"}]

### 2.2. Специализированная логика
[Описание специфической логики вашего агента]

## 3. Примеры ответов

```json
[
  {"Параметр": "Пример", "Значение": "Значение параметра"}
]
```
```

**ShowHelp.md** - справка для пользователя:

```markdown
Справка по My-Agent

Основное использование:
[Описание основного функционала]

Интерактивная таблица:
- Данные отображаются в интерактивном окне
- Выберите нужные строки и нажмите OK

Доступные команды:
?        - Показать справку
history  - История сессии
clear    - Очистить историю
exit     - Выход
```

### Шаг 3: Регистрация в модуле

Добавьте вашу функцию в `SmartAgents.psd1`:

```powershell
FunctionsToExport = @(
    'Start-FindSpecAgent',
    'Start-FlightPlanAgent',
    'Start-MyAgent'  # Добавьте вашу функцию
)

AliasesToExport = @(
    'find-spec',
    'flight-plan',
    'my-agent'       # Добавьте псевдоним
)
```

И в `SmartAgents.psm1`:

```powershell
Export-ModuleMember -Function 'Start-FindSpecAgent', 'Start-FlightPlanAgent', 'Start-MyAgent' -Alias 'find-spec', 'flight-plan', 'my-agent'
```

## Расширенные возможности

### Кастомизация обработки команд

Добавьте специализированные команды для вашего агента:

```powershell
function Command-Handler-MyAgent {
    param([string]$Command, [string]$HistoryFilePath)
    switch ($Command.Trim().ToLower()) {
        'export'    { Export-MyAgentData; return 'continue' }
        'import'    { Import-MyAgentData; return 'continue' }
        'settings'  { Show-MyAgentSettings; return 'continue' }
        # ... стандартные команды
        default     { return $null }
    }
}
```

### Интеграция с внешними API

Добавьте функции для работы с внешними сервисами:

```powershell
function Get-ExternalData {
    param([string]$Query)
    
    try {
        $response = Invoke-RestMethod -Uri "https://api.example.com/search" -Method GET -Body @{q = $Query}
        return $response
    } catch {
        Write-ColoredMessage "Ошибка получения данных: $($_.Exception.Message)" -Color $Config.Color.Error
        return $null
    }
}
```

### Сохранение результатов

Добавьте функции экспорта данных:

```powershell
function Export-Results {
    param([object]$Data, [string]$FilePath)
    
    try {
        $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $FilePath -Encoding UTF8
        Write-ColoredMessage "Результаты сохранены: $FilePath" -Color $Config.Color.Success
    } catch {
        Write-ColoredMessage "Ошибка сохранения: $($_.Exception.Message)" -Color $Config.Color.Error
    }
}
```

## Лучшие практики

1. **Следуйте единой структуре**: Используйте стандартные функции фреймворка для консистентности
2. **Обрабатывайте ошибки**: Всегда проверяйте результаты API-вызовов
3. **Используйте цветовую схему**: Применяйте `$Config.Color` для единообразия интерфейса
4. **Документируйте функционал**: Создавайте подробные GEMINI.md и ShowHelp.md файлы
5. **Тестируйте взаимодействие**: Проверяйте работу с JSON-данными и интерактивными таблицами

## Заключение

SmartAgents Framework предоставляет мощную основу для создания специализированных AI-агентов. Модульная архитектура позволяет легко добавлять новый функционал, а единообразная система конфигурации обеспечивает консистентный пользовательский опыт. Следуя приведенным рекомендациям, вы можете создать эффективного AI-помощника для любой предметной области. 