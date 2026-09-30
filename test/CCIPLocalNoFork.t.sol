// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {CCIPLocalSimulator, IRouterClient, LinkToken, BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {TokenTransferor} from "../src/TokenTransferor.sol";
import {TokenReceiver} from "../src/TokenReceiver.sol";
import {IERC20} from "@chainlink/local/src/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract CCIPLocalNoForkTest is Test {
    CCIPLocalSimulator public ccipLocalSimulator;
    TokenTransferor public tokenTransferor;
    TokenReceiver public tokenReceiver;

    uint64 public chainSelector;
    IRouterClient public sourceRouter;
    IRouterClient public destinationRouter;
    LinkToken public linkToken;
    BurnMintERC677Helper public ccipBnM;

    address public alice;
    address public bob;

    uint256 public constant INITIAL_TRANSFER_AMOUNT = 100 ether;
    uint256 public constant INITIAL_LINK_AMOUNT = 10 ether;

    event TokensTransferred(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );

    function setUp() public {
        // Initialize CCIP Local Simulator (No Fork)
        ccipLocalSimulator = new CCIPLocalSimulator();

        (
            uint64 _chainSelector,
            IRouterClient _sourceRouter,
            IRouterClient _destinationRouter,
            ,
            LinkToken _linkToken,
            BurnMintERC677Helper _ccipBnM,
            
        ) = ccipLocalSimulator.configuration();

        chainSelector = _chainSelector;
        sourceRouter = _sourceRouter;
        destinationRouter = _destinationRouter;
        linkToken = _linkToken;
        ccipBnM = _ccipBnM;

        // Deploy Transferor and Receiver contracts
        tokenTransferor = new TokenTransferor(address(sourceRouter), address(linkToken));
        tokenReceiver = new TokenReceiver(address(destinationRouter));

        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Fund Alice with ETH
        vm.deal(alice, 100 ether);

        // Faucet LINK to Alice and Transferor
        ccipLocalSimulator.requestLinkFromFaucet(alice, INITIAL_LINK_AMOUNT);

        // Mint CCIP-BnM test tokens to Alice
        ccipBnM.drip(alice); // gives 1 ether of CCIP-BnM
    }

    function test_CCIPTokenTransfer_PayWithNative_ToEOA() public {
        uint256 transferAmount = 0.1 ether;
        uint256 bobInitialBalance = ccipBnM.balanceOf(bob);
        uint256 aliceInitialBalance = ccipBnM.balanceOf(alice);

        vm.startPrank(alice);
        ccipBnM.approve(address(tokenTransferor), transferAmount);

        // Execute token transfer paying fee in Native ETH
        bytes32 messageId = tokenTransferor.transferTokensPayNative{value: 1 ether}(
            chainSelector,
            bob,
            address(ccipBnM),
            transferAmount
        );
        vm.stopPrank();

        assertTrue(messageId != bytes32(0), "Message ID should not be zero");
        assertEq(ccipBnM.balanceOf(bob), bobInitialBalance + transferAmount, "Bob should receive CCIP-BnM tokens");
        assertEq(ccipBnM.balanceOf(alice), aliceInitialBalance - transferAmount, "Alice balance should decrease");
    }

    function test_CCIPTokenTransfer_PayWithLINK_ToEOA() public {
        uint256 transferAmount = 0.2 ether;
        uint256 bobInitialBalance = ccipBnM.balanceOf(bob);
        uint256 aliceInitialBalance = ccipBnM.balanceOf(alice);
        uint256 aliceInitialLink = linkToken.balanceOf(alice);

        vm.startPrank(alice);
        ccipBnM.approve(address(tokenTransferor), transferAmount);
        linkToken.approve(address(tokenTransferor), 5 ether);

        // Execute token transfer paying fee in LINK
        bytes32 messageId = tokenTransferor.transferTokensPayLINK(
            chainSelector,
            bob,
            address(ccipBnM),
            transferAmount
        );
        vm.stopPrank();

        assertTrue(messageId != bytes32(0), "Message ID should not be zero");
        assertEq(ccipBnM.balanceOf(bob), bobInitialBalance + transferAmount, "Bob should receive tokens");
        assertEq(ccipBnM.balanceOf(alice), aliceInitialBalance - transferAmount, "Alice balance should decrease");
        assertLe(linkToken.balanceOf(alice), aliceInitialLink, "Alice LINK balance should be less than or equal to initial");
    }

    function test_CCIPTokenTransfer_PayWithNative_ToTokenReceiverContract() public {
        uint256 transferAmount = 0.5 ether;
        uint256 receiverInitialBalance = ccipBnM.balanceOf(address(tokenReceiver));

        vm.startPrank(alice);
        ccipBnM.approve(address(tokenTransferor), transferAmount);

        bytes32 messageId = tokenTransferor.transferTokensPayNative{value: 1 ether}(
            chainSelector,
            address(tokenReceiver),
            address(ccipBnM),
            transferAmount
        );
        vm.stopPrank();

        assertTrue(messageId != bytes32(0), "Message ID should not be zero");
        assertEq(
            ccipBnM.balanceOf(address(tokenReceiver)),
            receiverInitialBalance + transferAmount,
            "Receiver contract should receive CCIP-BnM tokens"
        );
    }

    function test_RevertWhen_InvalidReceiverAddress() public {
        vm.startPrank(alice);
        ccipBnM.approve(address(tokenTransferor), 1 ether);

        vm.expectRevert(TokenTransferor.InvalidReceiverAddress.selector);
        tokenTransferor.transferTokensPayNative{value: 1 ether}(
            chainSelector,
            address(0),
            address(ccipBnM),
            0.1 ether
        );
        vm.stopPrank();
    }
}
