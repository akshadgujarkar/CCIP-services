# Chainlink CCIP Cross-Chain Token Transfer & Local Testing

A complete reference implementation for cross-chain token transfers using the **Chainlink Cross-Chain Interoperability Protocol (CCIP)** and the **Chainlink Local** simulation toolkit (`@chainlink/local`).

This project shows how to send and receive tokens across blockchains and test the entire workflow locally in Foundry—both with single-chain mock simulations and multi-chain forked Anvil environments.

---

## 🌐 What is Chainlink CCIP?

The **Chainlink Cross-Chain Interoperability Protocol (CCIP)** provides a standard, secure interface for cross-chain communication. It enables smart contracts to:
- **Transfer Tokens**: Send tokens across different blockchain networks (via Lock & Mint, Burn & Mint, or Pool mechanisms).
- **Send Arbitrary Data**: Execute programmable function calls or send instructions to contracts on a destination chain.
- **Programmable Token Transfers**: Send tokens together with custom messages/data in a single cross-chain transaction.

### Key CCIP Concepts

1. **CCIP Router (`IRouterClient`)**: The entry point contract on each supported chain. Users and contracts call `router.ccipSend(...)` to initiate cross-chain requests.
2. **Chain Selector (`uint64`)**: A unique identifier assigned by Chainlink to each blockchain (different from EVM `chainId`), ensuring unambiguous cross-chain message routing.
3. **Fee Payments**: Senders can pay CCIP transaction fees either in **Native Gas (e.g. ETH)** or in **LINK tokens**.
4. **CCIP Receiver (`CCIPReceiver`)**: A base contract for destination chain applications implementing `_ccipReceive(...)` to safely receive tokens and decode payloads.
5. **Risk Management Network (RMN)**: An independent secondary verification network that monitors cross-chain transactions for anomalous activity before finalization.

---

## 🏗️ Project Architecture

```
[ Source Blockchain / Fork ]                        [ Destination Blockchain / Fork ]
 ┌─────────────────────────┐                         ┌─────────────────────────────┐
 │       TokenTransferor   │                         │        TokenReceiver        │
 │                         │                         │                             │
 │ transferTokensPayNative │                         │ _ccipReceive(message)       │
 │ transferTokensPayLINK   │                         │                             │
 └────────────┬────────────┘                         └──────────────▲──────────────┘
              │                                                     │
              ▼                                                     │
 ┌─────────────────────────┐                         ┌──────────────┴──────────────┐
 │       CCIP Router       │ ══════════════════════> │         CCIP Router         │
 │ (Local Simulator / Mock)│   Cross-Chain Message   │  (Destination OffRamp)      │
 └─────────────────────────┘                         └─────────────────────────────┘
```

### Smart Contracts

- [`src/TokenTransferor.sol`](file:///c:/Users/Akshad/Desktop/CCIP-services/src/TokenTransferor.sol): Handles token approvals, fee calculations via `getFee`, and calls `ccipSend` using either Native gas (ETH) or LINK.
- [`src/TokenReceiver.sol`](file:///c:/Users/Akshad/Desktop/CCIP-services/src/TokenReceiver.sol): Inherits `CCIPReceiver`, validating incoming CCIP calls and storing details of transferred tokens and messages.

---

## 🧪 Local Testing with Chainlink Local

Testing cross-chain applications traditionally required deploying to live testnets and waiting minutes for finality. With the **Chainlink Local** library (`@chainlink/local`), you can test CCIP locally in two ways:

### 1. Testing Without Forking (`CCIPLocalSimulator`)
Uses in-memory mock implementations of the CCIP Router, WETH9, LINK token, and CCIP-BnM (Burn and Mint) test tokens:
- **Instant execution**: No external RPC calls or internet connection required.
- **Config Helper**: `ccipLocalSimulator.configuration()` provides pre-deployed mock router and token instances.
- **Faucet**: `ccipBnM.drip(user)` and `ccipLocalSimulator.requestLinkFromFaucet(user, amount)` provide test funds instantly.

### 2. Testing With Forking (`CCIPLocalSimulatorFork`)
Simulates multi-chain environments by tracking transactions across forks:
- Switches between source and destination forks (`vm.selectFork(...)`).
- Reads network registry configurations using `getNetworkDetails(chainId)`.
- Automatically captures CCIP events on the source chain and routes them to the destination chain with:
  ```solidity
  ccipLocalSimulatorFork.switchChainAndRouteMessage(destinationForkId);
  ```

---

## 📁 Repository Structure

```
├── src/
│   ├── TokenTransferor.sol             # CCIP token sender contract
│   └── TokenReceiver.sol               # CCIP token receiver contract
├── test/
│   ├── CCIPLocalNoFork.t.sol           # In-memory local CCIP tests (No Fork)
│   └── CCIPLocalFork.t.sol             # Multi-chain forked simulation tests
├── script/
│   ├── DeployNoFork.s.sol              # Deployment & transfer script for single Anvil chain
│   └── DeployAndTransferFork.s.sol     # Multi-chain deployment script across 2 forks
├── scripts/
│   ├── run_two_anvils_demo.ps1         # PowerShell script to launch 2 Anvils & run demo
│   └── run_two_anvils_demo.sh          # Bash script to launch 2 Anvils & run demo
├── foundry.toml                        # Foundry config and package remappings
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/) (`forge`, `anvil`, `cast`)

### 1. Build Contracts

```bash
forge build
```

### 2. Run Tests

```bash
# Run all unit and simulation tests
forge test -vvv

# Run No-Fork tests (Mock Router & Local Simulation)
forge test --match-contract CCIPLocalNoForkTest -vvv

# Run Fork & Register tests
forge test --match-contract CCIPLocalForkTest -vvv
```

### 3. Run the Two Anvil Blockchains Demo

This demo automatically spawns two separate local Anvil nodes:
- **Chain A (Source)**: Port `8545` (Chain ID `11155111` / Sepolia)
- **Chain B (Destination)**: Port `8546` (Chain ID `421614` / Arbitrum Sepolia)

And executes the deployment, faucet funding, and CCIP cross-chain token transfer.

**On Windows (PowerShell):**
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_two_anvils_demo.ps1
```

**On Linux / macOS (Bash):**
```bash
chmod +x ./scripts/run_two_anvils_demo.sh
./scripts/run_two_anvils_demo.sh
```

---

## 📄 License

This project is licensed under the MIT License.
