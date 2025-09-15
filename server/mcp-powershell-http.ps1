# MCP PowerShell HTTPS Server with Token Auth
# \file mcp-powershell-https.ps1

param(
    [Parameter(Mandatory=$false)]
    [int]$Port = 8091,
    
    [Parameter(Mandatory=$false)]
    [string]$ServerHost = "localhost",
    
    [Parameter(Mandatory=$false)]
    [string]$CertThumbprint = "",   # Thumbprint of SSL certificate from LocalMachine\My store
     
    [Parameter(Mandatory=$false)]
    [string]$AuthToken = ""         # Bearer token for request authentication
)

# Ensure console uses UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

# Server Configuration
$ServerConfig = @{
    Port = $Port
    Host = $ServerHost
    MaxConcurrentRequests = 10
    TimeoutSeconds = 300
    CertThumbprint = $CertThumbprint
    AuthToken = $AuthToken
}

# --- Logging function ---
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO","WARNING","ERROR","DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(switch($Level) {
        "INFO" {"Green"}
        "WARNING" {"Yellow"}
        "ERROR" {"Red"}
        "DEBUG" {"Cyan"}
        default {"White"}
    })
}

# --- Token validation ---
function Test-AuthToken {
    param(
        [Parameter(Mandatory=$true)]
        [string]$HeaderValue
    )
    
    if (-not $ServerConfig.AuthToken) { return $true } # No token required
    if (-not $HeaderValue) { return $false }
    
    if ($HeaderValue -match "^Bearer\s+(.+)$") {
        return $Matches[1] -eq $ServerConfig.AuthToken
    }
    return $false
}

# --- HTTP request handler with token check ---
function Invoke-RequestHandler {
    param(
        [Parameter(Mandatory=$true)]
        [System.Net.HttpListenerContext]$Context
    )
    
    $request = $Context.Request
    $response = $Context.Response
    
    try {
        $response.Headers.Add("Access-Control-Allow-Origin","*")
        $response.Headers.Add("Access-Control-Allow-Methods","GET, POST, OPTIONS")
        $response.Headers.Add("Access-Control-Allow-Headers","Content-Type, Authorization")
        
        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Close()
            return
        }
        
        # --- Bearer token validation ---
        $authHeader = $request.Headers["Authorization"]
        if (-not (Test-AuthToken -HeaderValue $authHeader)) {
            $response.StatusCode = 401
            $response.StatusDescription = "Unauthorized"
            $response.Close()
            Write-Log "Unauthorized request from $($request.RemoteEndPoint)" -Level "WARNING"
            return
        }
        
        # --- POST only ---
        if ($request.HttpMethod -ne "POST") {
            $response.StatusCode = 405
            $errorResponse = @{
                jsonrpc="2.0"
                error=@{ code=-32600; message="Only POST method is supported" }
                id=$null
            }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(($errorResponse|ConvertTo-Json -Depth 10))
            $response.OutputStream.Write($bytes,0,$bytes.Length)
            $response.Close()
            return
        }

        $reader = New-Object System.IO.StreamReader($request.InputStream)
        $body = $reader.ReadToEnd()
        $reader.Close()
        Write-Log "Received request: $body" -Level "DEBUG"
        
        try { $mcpRequest = $body | ConvertFrom-Json -AsHashtable }
        catch {
            $response.StatusCode = 400
            $errorResponse = @{ jsonrpc="2.0"; error=@{code=-32700; message="JSON parse error"}; id=$null }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(($errorResponse|ConvertTo-Json -Depth 10))
            $response.OutputStream.Write($bytes,0,$bytes.Length)
            $response.Close()
            return
        }
        
        if (-not (Test-MCPRequest -Request $mcpRequest)) {
            $response.StatusCode = 400
            $errorResponse = @{ jsonrpc="2.0"; error=@{code=-32600; message="Invalid MCP request"}; id=$mcpRequest.id }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(($errorResponse|ConvertTo-Json -Depth 10))
            $response.OutputStream.Write($bytes,0,$bytes.Length)
            $response.Close()
            return
        }
        
        $mcpResponse = Invoke-MCPMethod -Method $mcpRequest.method -Params $mcpRequest.params -Id $mcpRequest.id
        
        $response.StatusCode = 200
        $response.ContentType = "application/json; charset=utf-8"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($mcpResponse|ConvertTo-Json -Depth 10))
        $response.ContentLength64 = $bytes.Length
        $response.OutputStream.Write($bytes,0,$bytes.Length)
        Write-Log "Sent response: $($bytes.Length) bytes" -Level "DEBUG"
    }
    catch {
        Write-Log "Error processing request: $($_.Exception.Message)" -Level "ERROR"
        try {
            $response.StatusCode=500
            $errorResponse=@{jsonrpc="2.0"; error=@{code=-32603; message="Internal server error"}; id=$null}
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(($errorResponse|ConvertTo-Json -Depth 10))
            $response.OutputStream.Write($bytes,0,$bytes.Length)
        } catch { Write-Log "Critical error sending response: $($_.Exception.Message)" -Level "ERROR" }
    }
    finally { if ($response) { $response.Close() } }
}

# --- Server start ---
function Start-MCPServer {
    param([Parameter(Mandatory=$false)][hashtable]$Config=$ServerConfig)
    
    $listener = New-Object System.Net.HttpListener
    $url = "https://$($Config.Host):$($Config.Port)/"
    $listener.Prefixes.Add($url)
    
    if (-not $Config.CertThumbprint) { throw "SSL certificate thumbprint is required for HTTPS" }
    # Bind certificate
    $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object Thumbprint -eq $Config.CertThumbprint
    if (-not $cert) { throw "Certificate not found" }
    # Requires netsh binding: netsh http add sslcert ipport=0.0.0.0:$Port certhash=$($Config.CertThumbprint) appid='{00000000-0000-0000-0000-000000000000}'
    
    Write-Log "Starting MCP HTTPS server on $url" -Level "INFO"
    $listener.Start()
    Write-Log "Server started" -Level "INFO"
    
    while ($listener.IsListening) {
        try { Invoke-RequestHandler -Context $listener.GetContext() }
        catch [System.Net.HttpListenerException] { break }
        catch { Write-Log "Error in request loop: $($_.Exception.Message)" -Level "ERROR" }
    }
    
    if ($listener.IsListening) { $listener.Stop(); $listener.Close() }
}

# --- Ctrl+C / exit ---
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Write-Log "Exiting..." -Level "INFO" }

try {
    [Console]::TreatControlCAsInput=$false
    [Console]::add_CancelKeyPress({
        param($s,$e)
        $e.Cancel=$true
        Write-Log "Ctrl+C pressed, shutting down..." -Level "INFO"
        [Environment]::Exit(0)
    })
} catch { Write-Log "Cannot attach Ctrl+C handler" -Level "WARNING" }

# --- Start ---
try { Start-MCPServer -Config $ServerConfig } catch { Write-Log "Fatal: $($_.Exception.Message)" -Level "ERROR"; exit 1 }
