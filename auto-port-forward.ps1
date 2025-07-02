# auto-port-forward.ps1

# Helper function to port-forward a service in background
function Start-PortForward {
    param (
        [string]$svc,
        [int]$localPort,
        [int]$remotePort,
        [string]$namespace = "lra-poc"
    )

    Start-Process powershell -WindowStyle Hidden -ArgumentList @"
kubectl port-forward svc/${svc} ${localPort}:${remotePort} -n ${namespace}
"@
}

# 🟢 Start all port-forwards in background
Start-PortForward -svc "frontend-service"         -localPort 8080  -remotePort 80
Start-PortForward -svc "backend-service"          -localPort 3000  -remotePort 3000
Start-PortForward -svc "lambda-producer-service"  -localPort 4000  -remotePort 4000
Start-PortForward -svc "lambda-consumer-service"  -localPort 4001  -remotePort 4001
Start-PortForward -svc "rabbitmq"                 -localPort 15672 -remotePort 15672
Start-PortForward -svc "redis"                    -localPort 6379  -remotePort 6379
