// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {CCIPLocalSimulator, IRouterClient, LinkToken, BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {TokenTransferor} from "../src/TokenTransferor.sol";
import {TokenReceiver} from "../src/TokenReceiver.sol";
import {IERC20} from "@chainlink/local/src/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract DeployNoForkScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80) // Default Anvil key #0
        );

        address deployer = vm.addr(deployerPrivateKey);
        console2.log("Deployer address:", deployer);

        if (deployer.balance < 1 ether) {
            vm.deal(deployer, 100 ether);
        }

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy CCIP Local Simulator
        CCIPLocalSimulator ccipLocalSimulator = new CCIPLocalSimulator();
        (
            uint64 chainSelector,
            IRouterClient sourceRouter,
            IRouterClient destinationRouter,
            ,
            LinkToken linkToken,
            BurnMintERC677Helper ccipBnM,
            
        ) = ccipLocalSimulator.configuration();

        console2.log("CCIP Simulator Chain Selector:", chainSelector);
        console2.log("Source Router:", address(sourceRouter));
        console2.log("LINK Token:", address(linkToken));
        console2.log("CCIP-BnM Token:", address(ccipBnM));

        // 2. Deploy TokenTransferor and TokenReceiver
        TokenTransferor tokenTransferor = new TokenTransferor(
            address(sourceRouter),
            address(linkToken)
        );
        TokenReceiver tokenReceiver = new TokenReceiver(address(destinationRouter));

        console2.log("TokenTransferor deployed at:", address(tokenTransferor));
        console2.log("TokenReceiver deployed at:", address(tokenReceiver));

        // 3. Request LINK from Faucet and Mint CCIP-BnM
        ccipLocalSimulator.requestLinkFromFaucet(deployer, 5 ether);
        ccipBnM.drip(deployer); // Drips 1 ether of CCIP-BnM

        console2.log("Deployer CCIP-BnM balance before transfer:", ccipBnM.balanceOf(deployer));
        console2.log("Receiver CCIP-BnM balance before transfer:", ccipBnM.balanceOf(address(tokenReceiver)));

        // 4. Transfer tokens via CCIP paying with Native currency
        uint256 transferAmount = 0.25 ether;
        ccipBnM.approve(address(tokenTransferor), transferAmount);

        bytes32 messageId = tokenTransferor.transferTokensPayNative{value: 0.1 ether}(
            chainSelector,
            address(tokenReceiver),
            address(ccipBnM),
            transferAmount
        );

        console2.log("CCIP Message Sent! Message ID:");
        console2.logBytes32(messageId);

        console2.log("Deployer CCIP-BnM balance after transfer:", ccipBnM.balanceOf(deployer));
        console2.log("Receiver CCIP-BnM balance after transfer:", ccipBnM.balanceOf(address(tokenReceiver)));

        vm.stopBroadcast();
    }
}
