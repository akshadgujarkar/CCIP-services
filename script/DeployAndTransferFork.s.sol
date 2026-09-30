// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {TokenTransferor} from "../src/TokenTransferor.sol";
import {TokenReceiver} from "../src/TokenReceiver.sol";
import {IERC20} from "@chainlink/local/src/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {BurnMintERC677Helper} from "@chainlink/local/src/ccip/BurnMintERC677Helper.sol";

contract DeployAndTransferForkScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );

        address deployer = vm.addr(deployerPrivateKey);
        console2.log("Deployer:", deployer);

        string memory sepoliaRpc = vm.envOr("SEPOLIA_RPC_URL", string("http://127.0.0.1:8545"));
        string memory arbRpc = vm.envOr("ARBITRUM_SEPOLIA_RPC_URL", string("http://127.0.0.1:8546"));

        CCIPLocalSimulatorFork ccipFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipFork));

        // 1. Create and Select Source Fork (e.g. Sepolia)
        uint256 sourceFork = vm.createSelectFork(sepoliaRpc);
        console2.log("Source Chain ID:", block.chainid);

        Register.NetworkDetails memory sourceDetails = ccipFork.getNetworkDetails(block.chainid);
        
        vm.startBroadcast(deployerPrivateKey);
        TokenTransferor tokenTransferor = new TokenTransferor(
            sourceDetails.routerAddress,
            sourceDetails.linkAddress
        );
        console2.log("TokenTransferor deployed on Source Fork:", address(tokenTransferor));
        vm.stopBroadcast();

        // 2. Create and Select Destination Fork (e.g. Arbitrum Sepolia)
        uint256 destFork = vm.createSelectFork(arbRpc);
        console2.log("Destination Chain ID:", block.chainid);

        Register.NetworkDetails memory destDetails = ccipFork.getNetworkDetails(block.chainid);
        
        vm.startBroadcast(deployerPrivateKey);
        TokenReceiver tokenReceiver = new TokenReceiver(destDetails.routerAddress);
        console2.log("TokenReceiver deployed on Destination Fork:", address(tokenReceiver));
        vm.stopBroadcast();

        // 3. Switch back to Source Chain and initiate cross-chain transfer
        vm.selectFork(sourceFork);
        console2.log("Switched back to Source Chain for transfer");

        vm.startBroadcast(deployerPrivateKey);
        
        // Faucet BnM test tokens to deployer on source chain
        if (sourceDetails.ccipBnMAddress != address(0)) {
            BurnMintERC677Helper(sourceDetails.ccipBnMAddress).drip(deployer);
            uint256 transferAmount = 0.05 ether;

            IERC20(sourceDetails.ccipBnMAddress).approve(address(tokenTransferor), transferAmount);

            bytes32 messageId = tokenTransferor.transferTokensPayNative{value: 0.1 ether}(
                destDetails.chainSelector,
                address(tokenReceiver),
                sourceDetails.ccipBnMAddress,
                transferAmount
            );

            console2.log("CCIP Send Initiated with Message ID:");
            console2.logBytes32(messageId);
        }
        vm.stopBroadcast();

        // 4. Route the message to Destination Chain
        ccipFork.switchChainAndRouteMessage(destFork);
        console2.log("Cross-chain message routed to destination fork successfully!");
    }
}
