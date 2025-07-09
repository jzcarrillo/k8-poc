Write-Host "STEP 7: Trigger Autoscaling via Load Generator (load-tester Pod)"

try {
    Write-Host "Deleting existing load-tester pod (if any)..."
    kubectl delete pod load-tester -n $namespace --ignore-not-found | Out-Null
    Start-Sleep -Seconds 2

    Write-Host "Deploying load-tester pod..."
    kubectl apply -f "$PSScriptRoot\load-test\load-tester.yaml" | Out-Null

    Write-Host "Waiting for load-tester pod to enter 'Running' state..."
    Invoke-Expression "kubectl wait --for=condition=Ready pod/load-tester -n $namespace --timeout=60s"

    Write-Host "Opening log stream from load-tester in a new terminal..."
    $logCmd = "kubectl logs load-tester -n $namespace --follow --timestamps"
    Start-Process powershell -ArgumentList "-NoProfile", "-NoExit", "-Command", "`"$logCmd`""

    Write-Host "Watching HPA scaling behavior in another new terminal..."
    $watchCmd = "kubectl get hpa -n $namespace --watch"
    Start-Process powershell -ArgumentList "-NoProfile", "-NoExit", "-Command", "`"$watchCmd`""
}
catch {
    Write-Warning ('Failed to deploy load-tester pod or monitor HPA: {0}' -f $_.Exception.Message)
}
