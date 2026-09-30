// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@chainlink/local/src/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/local/src/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";

/// @title TokenReceiver
/// @notice Contract that receives tokens and messages cross-chain via Chainlink CCIP
contract TokenReceiver is CCIPReceiver, OwnerIsCreator {
    using SafeERC20 for IERC20;

    // Struct to store received message details
    struct MessageDetails {
        bytes32 messageId;
        uint64 sourceChainSelector;
        address sender;
        address token;
        uint256 amount;
        string text;
    }

    MessageDetails public s_lastReceivedMessage;
    uint256 public s_totalMessagesReceived;

    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        address token,
        uint256 amount,
        string text
    );

    /// @notice Constructor initializes the CCIP Router in base CCIPReceiver
    /// @param _router Address of the CCIP router contract
    constructor(address _router) CCIPReceiver(_router) {}

    /// @notice Internal function called by ccipReceive when a CCIP message arrives
    /// @param message Incoming CCIP message
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        address token = address(0);
        uint256 amount = 0;

        if (message.destTokenAmounts.length > 0) {
            token = message.destTokenAmounts[0].token;
            amount = message.destTokenAmounts[0].amount;
        }

        string memory text = "";
        if (message.data.length > 0) {
            text = abi.decode(message.data, (string));
        }

        address sender = abi.decode(message.sender, (address));

        s_lastReceivedMessage = MessageDetails({
            messageId: message.messageId,
            sourceChainSelector: message.sourceChainSelector,
            sender: sender,
            token: token,
            amount: amount,
            text: text
        });

        s_totalMessagesReceived += 1;

        emit MessageReceived(
            message.messageId,
            message.sourceChainSelector,
            sender,
            token,
            amount,
            text
        );
    }

    /// @notice Get details of last received message
    function getLastReceivedMessage() external view returns (MessageDetails memory) {
        return s_lastReceivedMessage;
    }

    /// @notice Allows owner to withdraw received tokens
    function withdrawToken(address _beneficiary, address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_beneficiary, amount);
    }
}
