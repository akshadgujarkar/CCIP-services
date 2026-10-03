// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {BurnMintERC677Helper} from "@chainlink/local/src/ccip/BurnMintERC677Helper.sol";
import {IERC20} from "@chainlink/local/src/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

/// @title Example01ForkTest
/// @notice Tests cross-chain token transfer between Arbitrum Sepolia and Ethereum Sepolia using CCIPLocalSimulatorFork
/// @dev Implements the official Chainlink documentation guide for forked environments
contract Example01ForkTest is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    uint256 public destinationFork;
    uint256 public sourceFork;

    address public alice;
    address public bob;

    BurnMintERC677Helper public destinationCCIPBnMToken;
    uint64 public destinationChainSelector;

    BurnMintERC677Helper public sourceCCIPBnMToken;
    IERC20 public sourceLinkToken;
    IRouterClient public sourceRouter;

    function setUp() public {
        string memory DESTINATION_RPC_URL = vm.envOr(
            "ETHEREUM_SEPOLIA_RPC_URL",
            vm.envOr("SEPOLIA_RPC_URL", string("https://ethereum-sepolia-rpc.publicnode.com"))
        );
        string memory SOURCE_RPC_URL = vm.envOr(
            "ARBITRUM_SEPOLIA_RPC_URL",
            string("https://sepolia-rollup.arbitrum.io/rpc")
        );

        destinationFork = vm.createSelectFork(DESTINATION_RPC_URL);
        sourceFork = vm.createFork(SOURCE_RPC_URL);

        bob = makeAddr("bob");
        alice = makeAddr("alice");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        Register.NetworkDetails memory destinationNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        destinationCCIPBnMToken = BurnMintERC677Helper(destinationNetworkDetails.ccipBnMAddress);
        destinationChainSelector = destinationNetworkDetails.chainSelector;

        vm.selectFork(sourceFork);
        Register.NetworkDetails memory sourceNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        sourceCCIPBnMToken = BurnMintERC677Helper(sourceNetworkDetails.ccipBnMAddress);
        sourceLinkToken = IERC20(sourceNetworkDetails.linkAddress);
        sourceRouter = IRouterClient(sourceNetworkDetails.routerAddress);
    }

    function prepareScenario() public returns (Client.EVMTokenAmount[] memory tokensToSendDetails, uint256 amountToSend) {
        vm.selectFork(sourceFork);
        vm.startPrank(alice);
        sourceCCIPBnMToken.drip(alice);

        amountToSend = 100;
        sourceCCIPBnMToken.approve(address(sourceRouter), amountToSend);

        tokensToSendDetails = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenToSendDetails =
            Client.EVMTokenAmount({token: address(sourceCCIPBnMToken), amount: amountToSend});
        tokensToSendDetails[0] = tokenToSendDetails;

        vm.stopPrank();
    }

    function test_transferTokensFromEoaToEoaPayFeesInLink() public {
        (Client.EVMTokenAmount[] memory tokensToSendDetails, uint256 amountToSend) = prepareScenario();

        vm.selectFork(destinationFork);
        uint256 balanceOfBobBefore = destinationCCIPBnMToken.balanceOf(bob);

        vm.selectFork(sourceFork);
        uint256 balanceOfAliceBefore = sourceCCIPBnMToken.balanceOf(alice);

        ccipLocalSimulatorFork.requestLinkFromFaucet(alice, 10 ether);

        vm.startPrank(alice);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(bob),
            data: abi.encode(""),
            tokenAmounts: tokensToSendDetails,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})),
            feeToken: address(sourceLinkToken)
        });

        uint256 fees = sourceRouter.getFee(destinationChainSelector, message);
        sourceLinkToken.approve(address(sourceRouter), fees);

        sourceRouter.ccipSend(destinationChainSelector, message);
        vm.stopPrank();

        uint256 balanceOfAliceAfter = sourceCCIPBnMToken.balanceOf(alice);
        assertEq(balanceOfAliceAfter, balanceOfAliceBefore - amountToSend);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(destinationFork);
        vm.selectFork(destinationFork);

        uint256 balanceOfBobAfter = destinationCCIPBnMToken.balanceOf(bob);
        assertEq(balanceOfBobAfter, balanceOfBobBefore + amountToSend);
    }

    function test_transferTokensFromEoaToEoaPayFeesInNative() public {
        (Client.EVMTokenAmount[] memory tokensToSendDetails, uint256 amountToSend) = prepareScenario();

        vm.selectFork(destinationFork);
        uint256 balanceOfBobBefore = destinationCCIPBnMToken.balanceOf(bob);

        vm.selectFork(sourceFork);
        uint256 balanceOfAliceBefore = sourceCCIPBnMToken.balanceOf(alice);

        vm.startPrank(alice);
        vm.deal(alice, 5 ether);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(bob),
            data: abi.encode(""),
            tokenAmounts: tokensToSendDetails,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})),
            feeToken: address(0)
        });

        uint256 fees = sourceRouter.getFee(destinationChainSelector, message);
        sourceRouter.ccipSend{value: fees}(destinationChainSelector, message);
        vm.stopPrank();

        uint256 balanceOfAliceAfter = sourceCCIPBnMToken.balanceOf(alice);
        assertEq(balanceOfAliceAfter, balanceOfAliceBefore - amountToSend);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(destinationFork);
        vm.selectFork(destinationFork);

        uint256 balanceOfBobAfter = destinationCCIPBnMToken.balanceOf(bob);
        assertEq(balanceOfBobAfter, balanceOfBobBefore + amountToSend);
    }
}
