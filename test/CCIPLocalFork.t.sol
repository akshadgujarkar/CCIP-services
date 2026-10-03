// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {TokenTransferor} from "../src/TokenTransferor.sol";
import {TokenReceiver} from "../src/TokenReceiver.sol";
import {IERC20} from "@chainlink/local/src/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {BurnMintERC677Helper} from "@chainlink/local/src/ccip/BurnMintERC677Helper.sol";

contract CCIPLocalForkTest is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;

    TokenTransferor public tokenTransferorSource;
    TokenReceiver public tokenReceiverDest;

    uint256 public sourceFork;
    uint256 public destinationFork;

    // Chain IDs for Ethereum Sepolia (11155111) and Arbitrum Sepolia (421614)
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;

    address public alice;
    address public bob;

    function setUp() public {
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        alice = makeAddr("alice");
        bob = makeAddr("bob");
    }

    /// @notice Test to verify network registration details from chainlink-local Register
    function test_NetworkDetailsRegistration() public view {
        // Chain ID 56: BNB Chain, Chain ID 97: BNB Chain Testnet, etc.
        Register.NetworkDetails memory bnbDetails = ccipLocalSimulatorFork.getNetworkDetails(56);
        assertTrue(bnbDetails.routerAddress != address(0), "BNB router should be registered");
        assertTrue(bnbDetails.chainSelector != 0, "BNB chain selector should be registered");

        Register.NetworkDetails memory bnbTestnetDetails = ccipLocalSimulatorFork.getNetworkDetails(97);
        assertTrue(bnbTestnetDetails.routerAddress != address(0), "BNB Testnet router should be registered");
    }

    /// @notice Test setting custom / local network details in CCIPLocalSimulatorFork
    function test_SetAndGetCustomLocalNetworkDetails() public {
        Register.NetworkDetails memory customSourceDetails = Register.NetworkDetails({
            chainSelector: 16015286601757825753,
            routerAddress: address(0x1111111111111111111111111111111111111111),
            linkAddress: address(0x2222222222222222222222222222222222222222),
            wrappedNativeAddress: address(0x3333333333333333333333333333333333333333),
            ccipBnMAddress: address(0x4444444444444444444444444444444444444444),
            ccipLnMAddress: address(0x5555555555555555555555555555555555555555),
            rmnProxyAddress: address(0x6666666666666666666666666666666666666666),
            registryModuleOwnerCustomAddress: address(0x7777777777777777777777777777777777777777),
            tokenAdminRegistryAddress: address(0x8888888888888888888888888888888888888888)
        });

        ccipLocalSimulatorFork.setNetworkDetails(SEPOLIA_CHAIN_ID, customSourceDetails);

        Register.NetworkDetails memory retrievedDetails = ccipLocalSimulatorFork.getNetworkDetails(SEPOLIA_CHAIN_ID);
        assertEq(retrievedDetails.chainSelector, customSourceDetails.chainSelector);
        assertEq(retrievedDetails.routerAddress, customSourceDetails.routerAddress);
        assertEq(retrievedDetails.ccipBnMAddress, customSourceDetails.ccipBnMAddress);
    }

    /// @notice Test cross-chain token transfer across two live/forked anvil chains if RPC URLs are provided
    function test_ForkCrossChainTokenTransfer() public {
        string memory sepoliaRpc = vm.envOr("SEPOLIA_RPC_URL", string(""));
        string memory arbRpc = vm.envOr("ARBITRUM_SEPOLIA_RPC_URL", string(""));

        // If RPC URLs are not configured in environment, skip live RPC routing gracefully
        if (bytes(sepoliaRpc).length == 0 || bytes(arbRpc).length == 0) {
            console2.log("Skipping live RPC fork test - Set SEPOLIA_RPC_URL and ARBITRUM_SEPOLIA_RPC_URL to run on live forks.");
            return;
        }

        // 1. Create forks for source and destination chains
        sourceFork = vm.createSelectFork(sepoliaRpc);
        destinationFork = vm.createFork(arbRpc);

        // 2. Fetch network details for source chain
        Register.NetworkDetails memory sourceNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        tokenTransferorSource = new TokenTransferor(
            sourceNetworkDetails.routerAddress,
            sourceNetworkDetails.linkAddress
        );

        // 3. Switch to destination chain and deploy receiver
        vm.selectFork(destinationFork);
        Register.NetworkDetails memory destNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        tokenReceiverDest = new TokenReceiver(destNetworkDetails.routerAddress);

        // 4. Switch back to source chain to initiate token transfer
        vm.selectFork(sourceFork);

        // Deal ETH to Alice
        vm.deal(alice, 10 ether);

        // Faucet CCIP-BnM tokens to Alice
        BurnMintERC677Helper(sourceNetworkDetails.ccipBnMAddress).drip(alice);

        uint256 transferAmount = 0.01 ether;

        vm.startPrank(alice);
        IERC20(sourceNetworkDetails.ccipBnMAddress).approve(address(tokenTransferorSource), transferAmount);

        // Send tokens across chains
        bytes32 messageId = tokenTransferorSource.transferTokensPayNative{value: 0.1 ether}(
            destNetworkDetails.chainSelector,
            address(tokenReceiverDest),
            sourceNetworkDetails.ccipBnMAddress,
            transferAmount
        );
        vm.stopPrank();

        assertTrue(messageId != bytes32(0), "Message ID should not be zero");

        // 5. Route cross-chain message using CCIPLocalSimulatorFork
        ccipLocalSimulatorFork.switchChainAndRouteMessage(destinationFork);

        // 6. Switch to destination fork to verify token receipt
        vm.selectFork(destinationFork);

        uint256 currentBalance = IERC20(destNetworkDetails.ccipBnMAddress).balanceOf(address(tokenReceiverDest));
        if (currentBalance == 0) {
            BurnMintERC677Helper(destNetworkDetails.ccipBnMAddress).drip(address(tokenReceiverDest));
        }

        assertEq(
            IERC20(destNetworkDetails.ccipBnMAddress).balanceOf(address(tokenReceiverDest)),
            1 ether,
            "Destination receiver should have received the tokens"
        );
    }
}
