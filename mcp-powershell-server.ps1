# MCP PowerShell Server
# -*- coding: utf-8 -*-

param(
    [Parameter(Mandatory=$false)]
    [int]$Port = 8090,
    
    [Parameter(Mandatory=$false)]
    [string]$ServerHost = "localhost"
)

# Server Configuration
$ServerConfig = @{
    Port = $Port
    Host = $ServerHost
    MaxConcurrentRequests = 10
    TimeoutSeconds = 300
}

# Logging
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(
        switch($Level) {
            "INFO" { "Green" }
            "WARNING" { "Yellow" }
            "ERROR" { "Red" }
            "DEBUG" { "Cyan" }
            default { "White" }
        }
    )
}

# MCP Request validation function
function Test-MCPRequest {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Request
    )
    
    # Check for mandatory MCP fields
    if (-not $Request.ContainsKey("jsonrpc") -or $Request.jsonrpc -ne "2.0") {
        return $false
    }
    
    if (-not $Request.ContainsKey("method")) {
        return $false
    }
    
    return $true
}

# MCP Response creation function
function New-MCPResponse {
    param(
        [Parameter(Mandatory=$false)]
        [object]$Id = $null,
        
        [Parameter(Mandatory=$false)]
        [object]$Result = $null,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$Error = $null
    )
    
    $response = @{
        jsonrpc = "2.0"
        id = $Id
    }
    
    if ($Error) {
        $response.error = $Error
    } else {
        $response.result = $Result
    }
    
    return $response
}

# PowerShell script execution function
function Invoke-PowerShellScript {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Script,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$Parameters = @{},
        
        [Parameter(Mandatory=$false)]
        [int]$TimeoutSeconds = 300,
        
        [Parameter(Mandatory=$false)]
        [string]$WorkingDirectory = $PWD
    )
    
    try {
        Write-Log "Executing PowerShell script" -Level "DEBUG"
        Write-Log "Script: $($Script.Substring(0, [Math]::Min(100, $Script.Length)))" -Level "DEBUG"
        
        # Create a new PowerShell process for isolation
        $powerShell = [powershell]::Create()
        
        # Set the working directory
        if ($WorkingDirectory -ne $PWD) {
            $powerShell.AddScript("Set-Location -Path '$WorkingDirectory'")
        }
        
        # Add the main script
        $powerShell.AddScript($Script)
        
        # Add parameters
        foreach ($param in $Parameters.GetEnumerator()) {
            $powerShell.AddParameter($param.Key, $param.Value)
        }
        
        # Execute with a timeout
        $asyncResult = $powerShell.BeginInvoke()
        
        if ($asyncResult.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
            $result = $powerShell.EndInvoke($asyncResult)
            $errors = $powerShell.Streams.Error
            
            # Format the response
            $output = @{
                success = $true
                output = $result | Out-String
                errors = @()
                warnings = @()
            }
            
            # Add errors if any exist
            if ($errors.Count -gt 0) {
                $output.errors = @($errors | ForEach-Object { $_.ToString() })
                $output.success = $false
            }
            
            # Add warnings
            if ($powerShell.Streams.Warning.Count -gt 0) {
                $output.warnings = @($powerShell.Streams.Warning | ForEach-Object { $_.ToString() })
            }
            
            return $output
        } else {
            # Timeout
            $powerShell.Stop()
            throw "Script execution timed out after ($TimeoutSeconds seconds)"
        }
    }
    catch {
        Write-Log "Error executing script: $($_.Exception.Message)" -Level "ERROR"
        return @{
            success = $false
            output = ""
            errors = @($_.Exception.Message)
            warnings = @()
        }
    }
    finally {
        if ($powerShell) {
            $powerShell.Dispose()
        }
    }
}

# MCP methods handler
function Invoke-MCPMethod {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Method,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$Params = @{},
        
        [Parameter(Mandatory=$false)]
        [object]$Id = $null
    )
    
    Write-Log "Processing MCP method: $Method" -Level "DEBUG"
    
    switch ($Method) {
        "initialize" {
            return New-MCPResponse -Id $Id -Result @{
                protocolVersion = "2024-11-05"
                capabilities = @{
                    tools = @{
                        listChanged = $true
                    }
                }
                serverInfo = @{
                    name = "PowerShell Script Runner"
                    version = "1.0.0"
                }
            }
        }
        
        "tools/list" {
            return New-MCPResponse -Id $Id -Result @{
                tools = @(
                    @{
                        name = "run-script"
                        description = "Executes a PowerShell script"
                        inputSchema = @{
                            type = "object"
                            properties = @{
                                script = @{
                                    type = "string"
                                    description = "The PowerShell script to execute"
                                }
                                parameters = @{
                                    type = "object"
                                    description = "Parameters for the script"
                                    additionalProperties = $true
                                }
                                workingDirectory = @{
                                    type = "string"
                                    description = "The working directory for execution"
                                    default = $PWD
                                }
                                timeoutSeconds = @{
                                    type = "integer"
                                    description = "Execution timeout in seconds"
                                    default = 300
                                    minimum = 1
                                    maximum = 3600
                                }
                            }
                            required = @("script")
                        }
                    }
                )
            }
        }
        
        "tools/call" {
            if (-not $Params.ContainsKey("name")) {
                return New-MCPResponse -Id $Id -Error @{
                    code = -32602
                    message = "Missing mandatory parameter 'name'"
                }
            }
            
            $toolName = $Params.name
            $arguments = if ($Params.ContainsKey("arguments")) { $Params.arguments } else { @{} }
            
            switch ($toolName) {
                "run-script" {
                    if (-not $arguments.ContainsKey("script")) {
                        return New-MCPResponse -Id $Id -Error @{
                            code = -32602
                            message = "Missing mandatory parameter 'script'"
                        }
                    }
                    
                    $script = $arguments.script
                    $parameters = if ($arguments.ContainsKey("parameters")) { $arguments.parameters } else { @{} }
                    $workingDirectory = if ($arguments.ContainsKey("workingDirectory")) { $arguments.workingDirectory } else { $PWD }
                    $timeoutSeconds = if ($arguments.ContainsKey("timeoutSeconds")) { $arguments.timeoutSeconds } else { 300 }
                    
                    # Execute the script
                    $result = Invoke-PowerShellScript -Script $script -Parameters $parameters -WorkingDirectory $workingDirectory -TimeoutSeconds $timeoutSeconds
                    
                    return New-MCPResponse -Id $Id -Result @{
                        content = @(
                            @{
                                type = "text"
                                text = "PowerShell script execution result:`n`n$($result.output)"
                            }
                        )
                        isError = -not $result.success
                        _meta = $result
                    }
                }
                
                default {
                    return New-MCPResponse -Id $Id -Error @{
                        code = -32601
                        message = "Unknown tool: $toolName"
                    }
                }
            }
        }
        
        default {
            return New-MCPResponse -Id $Id -Error @{
                code = -32601
                message = "Unknown method: $Method"
            }
        }
    }
}

# HTTP request handler
function Invoke-RequestHandler {
    param(
        [Parameter(Mandatory=$true)]
        [System.Net.HttpListenerContext]$Context
    )
    
    $request = $Context.Request
    $response = $Context.Response
    
    try {
        # Set CORS headers
        $response.Headers.Add("Access-Control-Allow-Origin", "*")
        $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
        
        # Handle OPTIONS request
        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Close()
            return
        }
        
        # Handle only POST requests for MCP
        if ($request.HttpMethod -ne "POST") {
            $response.StatusCode = 405
            $errorResponse = @{
                jsonrpc = "2.0"
                error = @{
                    code = -32600
                    message = "Only POST method is supported"
                }
                id = $null
            }
            $responseJson = $errorResponse | ConvertTo-Json -Depth 10
            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            $response.Close()
            return
        }
        
        # Read request body
        $reader = New-Object System.IO.StreamReader($request.InputStream)
        $requestBody = $reader.ReadToEnd()
        $reader.Close()
        
        Write-Log "Received request: $requestBody" -Level "DEBUG"
        
        # Parse JSON
        try {
            $mcpRequest = $requestBody | ConvertFrom-Json -AsHashtable
        }
        catch {
            $response.StatusCode = 400
            $errorResponse = @{
                jsonrpc = "2.0"
                error = @{
                    code = -32700
                    message = "JSON parse error"
                }
                id = $null
            }
            $responseJson = $errorResponse | ConvertTo-Json -Depth 10
            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            $response.Close()
            return
        }
        
        # Validate MCP request
        if (-not (Test-MCPRequest -Request $mcpRequest)) {
            $response.StatusCode = 400
            $errorResponse = @{
                jsonrpc = "2.0"
                error = @{
                    code = -32600
                    message = "Invalid MCP request"
                }
                id = if ($mcpRequest.ContainsKey("id")) { $mcpRequest.id } else { $null }
            }
            $responseJson = $errorResponse | ConvertTo-Json -Depth 10
            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            $response.Close()
            return
        }
        
        # Process MCP method
        $mcpResponse = Invoke-MCPMethod -Method $mcpRequest.method -Params $mcpRequest.params -Id $mcpRequest.id
        
        # Send response
        $response.StatusCode = 200
        $response.ContentType = "application/json; charset=utf-8"
        
        $responseJson = $mcpResponse | ConvertTo-Json -Depth 10
        $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
        
        $response.ContentLength64 = $responseBytes.Length
        $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
        
        Write-Log "Sent response: $($responseJson.Substring(0, [Math]::Min(200, $responseJson.Length)))" -Level "DEBUG"
    }
    catch {
        Write-Log "Error processing request: $($_.Exception.Message)" -Level "ERROR"
        
        try {
            $response.StatusCode = 500
            $errorResponse = @{
                jsonrpc = "2.0"
                error = @{
                    code = -32603
                    message = "Internal server error"
                }
                id = $null
            }
            $responseJson = $errorResponse | ConvertTo-Json -Depth 10
            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
        }
        catch {
            Write-Log "Critical error sending response: $($_.Exception.Message)" -Level "ERROR"
        }
    }
    finally {
        if ($response) {
            try {
                $response.Close()
            }
            catch {
                Write-Log "Error closing response: $($_.Exception.Message)" -Level "ERROR"
            }
        }
    }
}

# Main server function
function Start-MCPServer {
    param(
        [Parameter(Mandatory=$false)]
        [hashtable]$Config = $ServerConfig
    )
    
    $listener = $null
    
    try {
        # Create HTTP listener
        $listener = New-Object System.Net.HttpListener
        $url = "http://$($Config.Host):$($Config.Port)/"
        $listener.Prefixes.Add($url)
        
        Write-Log "Starting MCP PowerShell server on $url" -Level "INFO"
        
        # Start the listener
        $listener.Start()
        Write-Log "Server started and listening for connections..." -Level "INFO"
        
        # Main request processing loop
        while ($listener.IsListening) {
            try {
                # Wait for an incoming request
                $context = $listener.GetContext()
                
                Write-Log "Received request from $($context.Request.RemoteEndPoint)" -Level "INFO"
                
                # Process the request
                Invoke-RequestHandler -Context $context
                
            }
            catch [System.Net.HttpListenerException] {
                if ($_.Exception.ErrorCode -ne 995) { # ERROR_OPERATION_ABORTED
                    Write-Log "HTTP listener error: $($_.Exception.Message)" -Level "ERROR"
                }
                break
            }
            catch {
                Write-Log "Error processing request loop: $($_.Exception.Message)" -Level "ERROR"
            }
        }
    }
    catch {
        Write-Log "Critical server error: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
    finally {
        if ($listener -and $listener.IsListening) {
            Write-Log "Stopping server..." -Level "INFO"
            $listener.Stop()
            $listener.Close()
        }
    }
}

# Signal handler for graceful shutdown
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Write-Log "Received exit signal" -Level "INFO"
}

# Ctrl+C handler (alternative method)
try {
    [Console]::TreatControlCAsInput = $false
    if ([Console].GetMethod("add_CancelKeyPress")) {
        [Console]::add_CancelKeyPress({
            param($sender, $e)
            $e.Cancel = $true
            Write-Log "Received interrupt signal (Ctrl+C)" -Level "INFO"
            [Environment]::Exit(0)
        })
    }
}
catch {
    Write-Log "Warning: Could not set Ctrl+C handler" -Level "WARNING"
}

# Start the server
try {
    Write-Log "Initializing MCP PowerShell server..." -Level "INFO"
    Write-Log "Configuration: Host=$($ServerConfig.Host), Port=$($ServerConfig.Port)" -Level "INFO"
    
    Start-MCPServer -Config $ServerConfig
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}