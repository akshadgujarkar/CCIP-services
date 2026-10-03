# Chainlink CCIP Simulation Scripts Overview

This document provides a comprehensive overview of the scripts, workflows, and changes made to test and simulate cross-chain token transfers for [TokenTransferor.sol](file:///c:/Users/Akshad/Desktop/CCIP-services/src/TokenTransferor.sol) and [TokenReceiver.sol](file:///c:/Users/Akshad/Desktop/CCIP-services/src/TokenReceiver.sol) using Chainlink Local simulators.

---

## 1. Summary of Changes Made

| Component | Path | Description |
| :--- | :--- | :--- |
| **No-Fork Script** | [`script/CCIPNoForkTest.s.sol`](file:///c:/Users/Akshad/Desktop/CCIP-services/script/CCIPNoForkTest.s.sol) | Standalone single-chain simulation script using `CCIPLocalSimulator.sol`. |
| **Fork Script** | [`script/CCIPForkTest.s.sol`](file:///c:/Users/Akshad/Desktop/CCIP-services/script/CCIPForkTest.s.sol) | Multi-chain live fork simulation script using `CCIPLocalSimulatorFork.sol` & `Register.sol`. |
| **Source Fix** | [`src/TokenTransferor.sol`](file:///c:/Users/Akshad/Desktop/CCIP-services/src/TokenTransferor.sol) | Added `gasLimit: 200_000` to `extraArgs` so receiver contracts have gas for execution. |
| **Source Fix** | [`src/TokenReceiver.sol`](file:///c:/Users/Akshad/Desktop/CCIP-services/src/TokenReceiver.sol) | Added safe decoding for sender addresses supporting both 20-byte and 32-byte CCIP payloads. |
| **Library Code** | `lib/chainlink-local/src/ccip/*` | **Untouched / pristine**: All library contracts remained completely unmodified. |

---

## 2. Script 1: Without Fork (`CCIPNoForkTest.s.sol`)

### Overview
This script executes a fast, isolated single-chain mock simulation of Chainlink CCIP on a local Anvil environment without requiring internet connectivity or live RPCs.

### Architecture & Workflow
```
┌────────────────────────────────────────────────────────────────────────┐
│                        CCIPLocalSimulator (Local Mock)                 │
│                                                                        │
│  1. Initialize Simulator  ──► ccipLocalSimulator.configuration()       │
│                                (router, linkToken, ccipBnM, etc.)      │
│                                                                        │
│  2. Deploy Contracts      ──► TokenTransferor(router, linkToken)       │
│                               TokenReceiver(router)                    │
│                                                                        │
│  3. Fund Test User        ──► ccipBnM.drip(alice) & requestLinkFromFaucet
│                                                                        │
│  4. Pay Native Gas        ──► transferTokensPayNative{value: eth}()    │
│  5. Pay LINK Token Fee    ──► transferTokensPayLINK()                  │
│                                                                        │
│  6. Verify Receipt        ──► TokenReceiver.getLastReceivedMessage()   │
│  7. Owner Withdrawal      ──► TokenReceiver.withdrawToken(beneficiary) │
└────────────────────────────────────────────────────────────────────────┘
```

### Key Execution Steps
1. **Initialize Simulator**: Instantiates `CCIPLocalSimulator` and retrieves pre-deployed mock routers, LINK token, and CCIP-BnM faucet token.
2. **Deploy Contracts**: Deploys `TokenTransferor` and `TokenReceiver` with the mock router.
3. **Fund Test Account**: Mints CCIP-BnM via `.drip()` and retrieves LINK tokens via `requestLinkFromFaucet()`.
4. **Execute Transfer (Native Fee)**: Transfers tokens paying fee in native ETH.
5. **Execute Transfer (LINK Fee)**: Transfers tokens paying fee in LINK tokens.
6. **Verify State**: Validates `s_totalMessagesReceived` and `getLastReceivedMessage()`.
7. **Owner Withdrawal**: Tests `withdrawToken()` to a beneficiary.

### Run Command
```bash
forge script script/CCIPNoForkTest.s.sol:CCIPNoForkTestScript -vvv
```

---

## 3. Script 2: With Fork (`CCIPForkTest.s.sol`)

### Overview
This script executes a multi-chain simulation against live network state using Forge forks (e.g., Ethereum Sepolia to Arbitrum Sepolia), testing against real on-chain CCIP contracts.

### Architecture & Workflow
```
┌─────────────────────────────────────┐         ┌─────────────────────────────────────┐
│  Source Fork (Ethereum Sepolia)     │         │   Dest Fork (Arbitrum Sepolia)      │
├─────────────────────────────────────┤         ├─────────────────────────────────────┤
│ 1. vm.createSelectFork(sepoliaRpc)  │         │ 1. vm.createFork(arbRpc)            │
│ 2. Deploy CCIPLocalSimulatorFork    │         │                                     │
│    + vm.makePersistent()            │         │                                     │
│ 3. getNetworkDetails(11155111)      │         │ 4. getNetworkDetails(421614)        │
│ 4. Deploy TokenTransferor           │         │ 5. Deploy TokenReceiver             │
│ 5. Drip CCIP-BnM & Faucet LINK      │         │                                     │
│ 6. ccipSend (Native / LINK fees)    │         │                                     │
└──────────────────┬──────────────────┘         └──────────────────┬──────────────────┘
                   │                                               │
                   └───────► switchChainAndRouteMessage(destFork) ─┘
                                           │
                   ┌───────────────────────┴───────────────────────┐
                   │  - Switch to Destination Fork                 │
                   │  - Verify TokenReceiver balance & message ID  │
                   │  - Test Owner token withdrawal                │
                   └───────────────────────────────────────────────┘
```

### Key Execution Steps
1. **Setup Multi-Forks**: Creates Ethereum Sepolia (`11155111`) and Arbitrum Sepolia (`421614`) forks.
2. **Persistence**: Instantiates `CCIPLocalSimulatorFork` and marks it persistent across forks via `vm.makePersistent()`.
3. **Network Configuration**: Uses `getNetworkDetails(chainId)` from `Register.sol` to fetch official Router, LINK, and CCIP-BnM addresses.
4. **Cross-Chain Deployment**: Deploys `TokenTransferor` on source and `TokenReceiver` on destination.
5. **Funding & Dispatch**: Requests test tokens via faucet on source and sends messages using both Native and LINK fee payment options.
6. **Message Routing & Delivery**: Invokes `switchChainAndRouteMessage(destinationFork)` to capture events, routes the message, and ensures canonical delivery on the destination fork.
7. **State Verification & Withdrawal**: Switches to destination fork, verifies received token balance and decoded sender details in `TokenReceiver`, and executes owner withdrawal.

### Run Command
```bash
# Optional: Set custom RPC URLs
export SEPOLIA_RPC_URL="https://ethereum-sepolia-rpc.publicnode.com"
export ARBITRUM_SEPOLIA_RPC_URL="https://sepolia-rollup.arbitrum.io/rpc"

forge script script/CCIPForkTest.s.sol:CCIPForkTestScript -vvv
```

---

## 4. Technical Reference

| Feature | `CCIPLocalSimulator` (No Fork) | `CCIPLocalSimulatorFork` (With Fork) |
| :--- | :--- | :--- |
| **Environment** | Single local chain (Anvil) | Multi-chain RPC forks |
| **Speed** | Instant (< 2 seconds) | Network RPC dependent |
| **Dependencies** | Self-contained mock contracts | Canonical deployed contracts |
| **Message Routing** | Synchronous mock delivery | Event-based cross-fork routing (`switchChainAndRouteMessage`) |
| **Token Faucets** | `LinkToken` & `BurnMintERC677Helper` | Live testnet faucets / pranks |
