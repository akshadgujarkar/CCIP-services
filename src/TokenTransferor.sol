// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@chainlink/local/src/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/local/src/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title TokenTransferor
/// @notice Contract for transferring tokens cross-chain via Chainlink CCIP
contract TokenTransferor is OwnerIsCreator {
    using SafeERC20 for IERC20;

    // Custom errors
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error NothingToWithdraw();
    error FailedToWithdrawEth(address owner, address target, uint256 value);
    error DestinationChainNotSupported(uint64 destinationChainSelector);
    error InvalidReceiverAddress();

    // Events
    event TokensTransferred(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );

    IRouterClient private immutable i_router;
    IERC20 private immutable i_linkToken;

    /// @notice Constructor initializes the CCIP Router and LINK token
    /// @param _router Address of the CCIP router contract
    /// @param _link Address of the LINK token contract
    constructor(address _router, address _link) {
        i_router = IRouterClient(_router);
        i_linkToken = IERC20(_link);
    }

    /// @notice Transfer tokens to a receiver on a destination chain paying fees in Native gas (e.g. ETH)
    /// @param _destinationChainSelector CCIP destination chain selector
    /// @param _receiver Address of the receiver on destination chain
    /// @param _token Address of the token to be transferred
    /// @param _amount Amount of the token to be transferred
    /// @return messageId Unique CCIP message identifier  
    function transferTokensPayNative(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount
    ) external payable returns (bytes32 messageId) {
        if (_receiver == address(0)) revert InvalidReceiverAddress();

        // Transfer tokens from sender to this contract
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // Approve the router to spend tokens
        IERC20(_token).safeApprove(address(i_router), _amount);

        // Construct CCIP message
        Client.EVM2AnyMessage memory ccipMessage = _buildCCIPMessage(
            _receiver,
            _token,
            _amount,
            address(0) // Native gas token for fees
        );

        // Calculate fee
        uint256 fees = i_router.getFee(_destinationChainSelector, ccipMessage);
        if (msg.value < fees) {
            revert NotEnoughBalance(msg.value, fees);
        }

        // Send CCIP message with native fee
        messageId = i_router.ccipSend{value: fees}(_destinationChainSelector, ccipMessage);

        // Refund any remaining excess native currency
        if (msg.value > fees) {
            payable(msg.sender).transfer(msg.value - fees);
        }

        emit TokensTransferred(
            messageId,
            _destinationChainSelector,
            _receiver,
            _token,
            _amount,
            address(0),
            fees
        );
    }

    /// @notice Transfer tokens to a receiver on a destination chain paying fees in LINK
    /// @param _destinationChainSelector CCIP destination chain selector
    /// @param _receiver Address of the receiver on destination chain
    /// @param _token Address of the token to be transferred
    /// @param _amount Amount of the token to be transferred
    /// @return messageId Unique CCIP message identifier
    function transferTokensPayLINK(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount
    ) external returns (bytes32 messageId) {
        if (_receiver == address(0)) revert InvalidReceiverAddress();

        // Transfer tokens from sender to this contract
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // Approve router for token
        IERC20(_token).safeApprove(address(i_router), _amount);

        // Construct CCIP message
        Client.EVM2AnyMessage memory ccipMessage = _buildCCIPMessage(
            _receiver,
            _token,
            _amount,
            address(i_linkToken)
        );

        // Calculate fee
        uint256 fees = i_router.getFee(_destinationChainSelector, ccipMessage);
        uint256 linkBalance = i_linkToken.balanceOf(address(this));

        // If contract doesn't have enough LINK, transfer from sender
        if (linkBalance < fees) {
            uint256 linkNeeded = fees - linkBalance;
            i_linkToken.safeTransferFrom(msg.sender, address(this), linkNeeded);
        }

        // Approve router for LINK fee
        i_linkToken.safeApprove(address(i_router), fees);

        // Send CCIP message
        messageId = i_router.ccipSend(_destinationChainSelector, ccipMessage);

        emit TokensTransferred(
            messageId,
            _destinationChainSelector,
            _receiver,
            _token,
            _amount,
            address(i_linkToken),
            fees
        );
    }

    /// @notice Builds CCIP message structure
    function _buildCCIPMessage(
        address _receiver,
        address _token,
        uint256 _amount,
        address _feeTokenAddress
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });

        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 0})
            ),
            feeToken: _feeTokenAddress
        });
    }

    /// @notice Allows the contract owner to withdraw tokens in case of emergency
    function withdrawToken(address _beneficiary, address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        if (amount == 0) revert NothingToWithdraw();
        IERC20(_token).safeTransfer(_beneficiary, amount);
    }

    /// @notice Allows the contract owner to withdraw native gas token
    function withdrawETH(address payable _beneficiary) external onlyOwner {
        uint256 amount = address(this).balance;
        if (amount == 0) revert NothingToWithdraw();
        (bool sent, ) = _beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

    /// @notice Return the CCIP router address
    function getRouter() external view returns (address) {
        return address(i_router);
    }

    /// @notice Return the LINK token address
    function getLinkToken() external view returns (address) {
        return address(i_linkToken);
    }

    receive() external payable {}
}
