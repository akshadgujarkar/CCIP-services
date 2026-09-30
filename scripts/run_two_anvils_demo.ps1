# PowerShell Script to run two local Anvil blockchains and execute CCIP Token Transfers

$env:PATH += ";$HOME\.foundry\bin"

Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host " Starting Two Local Anvil Blockchains for CCIP Testing     " -ForegroundColor Cyan
Write-Host "===========================================================" -ForegroundColor Cyan

# 1. Start Source Chain Anvil (Port 8545, ChainID 11155111 - Sepolia)
Write-Host "`n[1/3] Starting Chain A (Source Anvil on port 8545, chainId 11155111)..." -ForegroundColor Yellow
$anvilSource = Start-Process -FilePath "$HOME\.foundry\bin\anvil.exe" -ArgumentList "-p 8545 --chain-id 11155111 --silent" -PassThru

# 2. Start Destination Chain Anvil (Port 8546, ChainID 421614 - Arbitrum Sepolia)
Write-Host "[2/3] Starting Chain B (Destination Anvil on port 8546, chainId 421614)..." -ForegroundColor Yellow
$anvilDest = Start-Process -FilePath "$HOME\.foundry\bin\anvil.exe" -ArgumentList "-p 8546 --chain-id 421614 --silent" -PassThru

Start-Sleep -Seconds 3

try {
    Write-Host "`n[3/3] Running CCIP Tests and Scripts..." -ForegroundColor Green

    Write-Host "`n--- Running CCIP Local Tests (No Fork) ---" -ForegroundColor Magenta
    forge test --match-contract CCIPLocalNoForkTest -vvv

    Write-Host "`n--- Running CCIP Fork / Register Tests ---" -ForegroundColor Magenta
    forge test --match-contract CCIPLocalForkTest -vvv

    Write-Host "`n--- Executing Deploy & Transfer Script on Chain A (Port 8545) ---" -ForegroundColor Magenta
    forge script script/DeployNoFork.s.sol --rpc-url http://127.0.0.1:8545 --broadcast -vvv

    Write-Host "`n===========================================================" -ForegroundColor Green
    Write-Host " CCIP Cross-Chain Token Transfer Demonstration Completed! " -ForegroundColor Green
    Write-Host "===========================================================" -ForegroundColor Green
}
finally {
    Write-Host "`nStopping background Anvil processes..." -ForegroundColor Gray
    if ($anvilSource -and !$anvilSource.HasExited) {
        Stop-Process -Id $anvilSource.Id -Force -ErrorAction SilentlyContinue
    }
    if ($anvilDest -and !$anvilDest.HasExited) {
        Stop-Process -Id $anvilDest.Id -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Cleaned up Anvil instances." -ForegroundColor Gray
}
