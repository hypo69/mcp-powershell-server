# test-mcp.ps1 - Простой тестовый MCP сервер
# -*- coding: utf-8 -*-

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

function Send-Response {
    param([hashtable]$Response)
    $json = $Response | ConvertTo-Json -Depth 10 -Compress
    Write-Host $json
}

# Основной цикл
while ($true) {
    $line = [Console]::ReadLine()
    
    if ($null -eq $line) { break }
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    
    try {
        $request = $line | ConvertFrom-Json -AsHashtable
        
        switch ($request.method) {
            "initialize" {
                Send-Response @{
                    jsonrpc = "2.0"
                    id = $request.id
                    result = @{
                        protocolVersion = "2024-11-05"
                        capabilities = @{ tools = @{} }
                        serverInfo = @{
                            name = "Test PowerShell Server"
                            version = "1.0.0"
                        }
                    }
                }
            }
            "tools/list" {
                Send-Response @{
                    jsonrpc = "2.0"
                    id = $request.id
                    result = @{
                        tools = @(
                            @{
                                name = "get-date"
                                description = "Получить текущую дату"
                                inputSchema = @{
                                    type = "object"
                                    properties = @{}
                                }
                            }
                        )
                    }
                }
            }
            "tools/call" {
                if ($request.params.name -eq "get-date") {
                    $currentDate = Get-Date
                    Send-Response @{
                        jsonrpc = "2.0"
                        id = $request.id
                        result = @{
                            content = @(
                                @{
                                    type = "text"
                                    text = "Текущая дата и время: $currentDate"
                                }
                            )
                        }
                    }
                } else {
                    Send-Response @{
                        jsonrpc = "2.0"
                        id = $request.id
                        error = @{
                            code = -32601
                            message = "Неизвестный инструмент"
                        }
                    }
                }
            }
            default {
                Send-Response @{
                    jsonrpc = "2.0"
                    id = $request.id
                    error = @{
                        code = -32601
                        message = "Неизвестный метод: $($request.method)"
                    }
                }
            }
        }
    }
    catch {
        Send-Response @{
            jsonrpc = "2.0"
            id = $null
            error = @{
                code = -32700
                message = "Ошибка парсинга JSON"
            }
        }
    }
}