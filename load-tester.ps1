param (
    [string]$namespace = "lra-poc"
)

Write-Host "STEP 7: Trigger Autoscaling via Load Generator (load-tester pod)"

try {
    Write-Host "Deleting existing load-tester pod (if any)..."
    kubectl delete pod load-tester -n $namespace --ignore-not-found | Out-Null

    Write-Host "Deploying load-tester pod..."
    kubectl apply -f "$PSScriptRoot\load-test\load-tester.yaml" | Out-Null

    Write-Host "Waiting for load-tester pod to enter 'Running' state..."
    kubectl wait --for=condition=Ready pod/load-tester -n $namespace --timeout=60s

    Write-Host "Streaming logs from load-tester (new terminal)..."
    Start-Process powershell -ArgumentList @(
        "-NoProfile",
        "-NoExit",
        "-Command",
        "kubectl logs load-tester -n $namespace --follow"
    )

    Write-Host "Watching HPA behavior in real-time (new terminal)..."
    Start-Process powershell -ArgumentList @(
        "-NoProfile",
        "-NoExit",
        "-Command",
        "kubectl get hpa -n $namespace --watch"
    )
}
catch {
    Write-Warning ('Failed to deploy load-tester or monitor HPA: {0}' -f $_.Exception.Message)
}
