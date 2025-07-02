# auto-port-forward.ps1

# ✅ Check if kubectl is available
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error "❌ kubectl is not installed or not in PATH."
    exit 1
}

# ✅ Default namespace
$namespace = "lra-poc"

# ✅ Helper function to port-forward a service in the background
function Start-PortForward {
    param (
        [string]$svc,
        [int]$localPort,
        [int]$remotePort
    )

    Write-Host ">> Forwarding $svc on localhost:${localPort}:${remotePort}"
    
    Start-Process powershell -WindowStyle Hidden -ArgumentList @"
kubectl port-forward svc/$svc ${localPort}:${remotePort} -n $namespace
"@
    Start-Sleep -Milliseconds 300
}

# 🟢 Launch all required port-forwards
Start-PortForward -svc "api-gateway-service"      -localPort 8081  -remotePort 8081
Start-PortForward -svc "frontend-service"         -localPort 8080  -remotePort 80
Start-PortForward -svc "lambda-producer-service"  -localPort 4000  -remotePort 4000
Start-PortForward -svc "lambda-consumer-service"  -localPort 4001  -remotePort 4001
Start-PortForward -svc "backend-service"          -localPort 3000  -remotePort 3000
Start-PortForward -svc "rabbitmq"                 -localPort 15672 -remotePort 15672
Start-PortForward -svc "redis"                    -localPort 6379  -remotePort 6379
Start-PortForward -svc "postgres-service"
