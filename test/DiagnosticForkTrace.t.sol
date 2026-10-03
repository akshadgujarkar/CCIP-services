// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {CCIPLocalSimulatorFork, Register, IRouterFork, IEVM2EVMOffRampFork} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {TokenTransferor} from "../src/TokenTransferor.sol";
import {TokenReceiver} from "../src/TokenReceiver.sol";
import {IERC20} from "@chainlink/local/src/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {BurnMintERC677Helper} from "@chainlink/local/src/ccip/BurnMintERC677Helper.sol";
import {Internal} from "@chainlink/contracts-ccip/contracts/libraries/Internal.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

contract DiagnosticForkTrace is Test {
    CCIPLocalSimulatorFork public ccipFork;
    TokenTransferor public tokenTransferorSource;
    TokenReceiver public tokenReceiverDest;

    uint256 public sourceFork;
    uint256 public destinationFork;

    string constant SEPOLIA_RPC = "https://ethereum-sepolia-rpc.publicnode.com";
    string constant ARB_SEPOLIA_RPC = "https://sepolia-rollup.arbitrum.io/rpc";

    uint256 constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant ARB_SEPOLIA_CHAIN_ID = 421614;

    address alice = makeAddr("alice");

    function setUp() public {
        string memory sepoliaRpc = vm.envOr("SEPOLIA_RPC_URL", SEPOLIA_RPC);
        string memory arbRpc = vm.envOr("ARBITRUM_SEPOLIA_RPC_URL", ARB_SEPOLIA_RPC);

        sourceFork = vm.createSelectFork(sepoliaRpc);
        destinationFork = vm.createFork(arbRpc);

        ccipFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipFork));
    }

    function test_DiagnoseExactOffRampRevert() public {
        console2.log("\n========================================================");
        console2.log("=== DIAGNOSTIC FORK TRACE: INVESTIGATING OFFRAMP ====");
        console2.log("========================================================");

        Register.NetworkDetails memory sourceNet = ccipFork.getNetworkDetails(SEPOLIA_CHAIN_ID);
        Register.NetworkDetails memory destNet = ccipFork.getNetworkDetails(ARB_SEPOLIA_CHAIN_ID);

        // Deploy contracts
        vm.selectFork(sourceFork);
        tokenTransferorSource = new TokenTransferor(sourceNet.routerAddress, sourceNet.linkAddress);

        vm.selectFork(destinationFork);
        tokenReceiverDest = new TokenReceiver(destNet.routerAddress);

        // Dispatch transfer on source
        bytes32 messageId = _dispatchSourceTransfer(sourceNet, destNet);

        // Inspect captured logs on source
        _inspectSourceLogs();

        // Inspect OffRamps on destination
        _inspectDestinationOffRamps(sourceNet, destNet, messageId);
    }

    function _dispatchSourceTransfer(
        Register.NetworkDetails memory sourceNet,
        Register.NetworkDetails memory destNet
    ) internal returns (bytes32 messageId) {
        vm.selectFork(sourceFork);
        vm.deal(alice, 5 ether);
        BurnMintERC677Helper(sourceNet.ccipBnMAddress).drip(alice);

        uint256 transferAmount = 0.01 ether;
        vm.startPrank(alice);
        IERC20(sourceNet.ccipBnMAddress).approve(address(tokenTransferorSource), transferAmount);
        
        messageId = tokenTransferorSource.transferTokensPayNative{value: 0.1 ether}(
            destNet.chainSelector,
            address(tokenReceiverDest),
            sourceNet.ccipBnMAddress,
            transferAmount
        );
        vm.stopPrank();

        console2.log("1. Message Dispatched on Source (Sepolia)");
        console2.log("   Message ID:", vm.toString(messageId));
        console2.log("   Source Router:", sourceNet.routerAddress);
        console2.log("   Dest Router  :", destNet.routerAddress);
    }

    function _inspectSourceLogs() internal view {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        console2.log("\n2. Captured Logs count:", logs.length);
        console2.log("   CCIPLocalSimulatorFork.CCIPMessageSent.selector:", vm.toString(CCIPLocalSimulatorFork.CCIPMessageSent.selector));

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == bytes32(0x371bc2ff0a006f4ef863b1d27a065d4e9f938b6d883eb154572b4aea593b32cc)) {
                console2.log("   [+] Found OnRamp Event (0x371bc2ff...) at Log index:", i);
                console2.log("       Emitter:", logs[i].emitter);
                console2.log("       Topic 1 (destChainSelector):", vm.toString(logs[i].topics[1]));
                console2.log("       Topic 2 (sender)           :", vm.toString(logs[i].topics[2]));
                console2.log("       Topic 3 (messageId)        :", vm.toString(logs[i].topics[3]));
            }
        }
    }

    function _inspectDestinationOffRamps(
        Register.NetworkDetails memory sourceNet,
        Register.NetworkDetails memory destNet,
        bytes32 messageId
    ) internal {
        vm.selectFork(destinationFork);
        IRouterFork.OffRamp[] memory offRamps = IRouterFork(destNet.routerAddress).getOffRamps();
        console2.log("\n3. Destination Router OffRamps count:", offRamps.length);

        address targetOffRamp = 0xC93218EB7B778bC0c13E5296140C8E4Fa1C440DA;
        console2.log("\n4. Inspecting Active Destination OffRamp for Sepolia:", targetOffRamp);

        (bool okCfg, bytes memory rawCfg) = targetOffRamp.staticcall(
            abi.encodeWithSignature("getSourceChainConfig(uint64)", sourceNet.chainSelector)
        );
        console2.log("   getSourceChainConfig raw call success:", okCfg);
        console2.log("   raw bytes length:", rawCfg.length);
        console2.logBytes(rawCfg);

        _testDirectOffRampCalls(sourceNet, destNet, targetOffRamp, messageId);
    }

    function _testDirectOffRampCalls(
        Register.NetworkDetails memory sourceNet,
        Register.NetworkDetails memory destNet,
        address targetOffRamp,
        bytes32 messageId
    ) internal {
        console2.log("\n5. Executing executeSingleMessage calls...");

        uint256 gasLimit = 200_000;
        Internal.Any2EVMTokenTransfer[] memory tokenAmounts = new Internal.Any2EVMTokenTransfer[](1);
        tokenAmounts[0] = Internal.Any2EVMTokenTransfer({
            sourcePoolAddress: abi.encode(address(0xabc0dF19Ce41b0b5e711366636e32F5914493B99)),
            destTokenAddress: destNet.ccipBnMAddress,
            destGasAmount: 0,
            extraData: "",
            amount: 0.01 ether
        });

        Internal.RampMessageHeader memory header = Internal.RampMessageHeader({
            messageId: messageId,
            sourceChainSelector: sourceNet.chainSelector,
            destChainSelector: destNet.chainSelector,
            sequenceNumber: 161,
            nonce: 1
        });

        Internal.Any2EVMRampMessage memory any2EVMRampMessage = Internal.Any2EVMRampMessage({
            header: header,
            sender: abi.encodePacked(address(tokenTransferorSource)),
            data: "",
            receiver: address(tokenReceiverDest),
            gasLimit: gasLimit,
            tokenAmounts: tokenAmounts
        });

        bytes[] memory offchainTokenData = new bytes[](1);
        uint32[] memory tokenGasOverrides = new uint32[](1);
        tokenGasOverrides[0] = uint32(gasLimit);

        // Test v1.6 OffRamp
        vm.startPrank(targetOffRamp);
        (bool successV16, bytes memory returnDataV16) = targetOffRamp.call(
            abi.encodeWithSelector(
                IEVM2EVMOffRampFork.executeSingleMessage.selector,
                any2EVMRampMessage,
                offchainTokenData,
                tokenGasOverrides
            )
        );
        vm.stopPrank();

        console2.log("\n6. DIRECT CALL RESULT on v1.6 OffRamp (0xC93218EB7B778bC0c13E5296140C8E4Fa1C440DA):");
        console2.log("   Success:", successV16);
        console2.log("   Revert Bytes Length:", returnDataV16.length);
        console2.logBytes(returnDataV16);

        // Test v1.5 OffRamp
        address v15OffRamp = 0xBed6e9131916d724418C8a6FE810F727302a5c00;
        vm.startPrank(v15OffRamp);
        (bool successV15, bytes memory returnDataV15) = v15OffRamp.call(
            abi.encodeWithSelector(
                IEVM2EVMOffRampFork.executeSingleMessage.selector,
                any2EVMRampMessage,
                offchainTokenData,
                tokenGasOverrides
            )
        );
        vm.stopPrank();

        console2.log("\n7. DIRECT CALL RESULT on v1.5 OffRamp (0xBed6e9131916d724418C8a6FE810F727302a5c00):");
        console2.log("   Success:", successV15);
        console2.log("   Revert Bytes Length:", returnDataV15.length);
        console2.logBytes(returnDataV15);
        if (returnDataV15.length >= 4) {
            console2.log("   Error Selector:", vm.toString(bytes4(returnDataV15)));
        }

        console2.log("\n========================================================\n");
    }
}
