#!/usr/bin/env bash
set -e

echo "==========================================================="
echo " Starting Two Local Anvil Blockchains for CCIP Testing     "
echo "==========================================================="

# 1. Start Source Chain Anvil (Port 8545, ChainID 11155111)
echo -e "\n[1/3] Starting Chain A (Source Anvil on port 8545, chainId 11155111)..."
anvil -p 8545 --chain-id 11155111 --silent &
ANVIL_SOURCE_PID=$!

# 2. Start Destination Chain Anvil (Port 8546, ChainID 421614)
echo -e "[2/3] Starting Chain B (Destination Anvil on port 8546, chainId 421614)..."
anvil -p 8546 --chain-id 421614 --silent &
ANVIL_DEST_PID=$!

cleanup() {
    echo -e "\nStopping background Anvil processes (PIDs: $ANVIL_SOURCE_PID, $ANVIL_DEST_PID)..."
    kill $ANVIL_SOURCE_PID $ANVIL_DEST_PID 2>/dev/null || true
}
trap cleanup EXIT

sleep 2

echo -e "\n[3/3] Running CCIP Tests and Scripts..."

echo -e "\n--- Running CCIP Local Tests (No Fork) ---"
forge test --match-contract CCIPLocalNoForkTest -vvv

echo -e "\n--- Running CCIP Fork / Register Tests ---"
forge test --match-contract CCIPLocalForkTest -vvv

echo -e "\n--- Executing Deploy & Transfer Script on Chain A (Port 8545) ---"
forge script script/DeployNoFork.s.sol --rpc-url http://127.0.0.1:8545 --broadcast -vvv

echo "==========================================================="
echo " CCIP Cross-Chain Token Transfer Demonstration Completed! "
echo "==========================================================="
