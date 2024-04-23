// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


// BRIDGE BASE TESTNET: 0x30d6D9Cb5De7B8Fa3da16655bd1188B8C4d4F87F
// params to build on base testnet: 0xe432150cce91c13a887f7D836923d5597adD8E31, 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6, 0x30d6D9Cb5De7B8Fa3da16655bd1188B8C4d4F87F

// BRIDGE SEPOLIA TESTNET: 0x07d38BF9e23Cd3Daf1C64FF64711a6E66ac0b58F
// params to build sepolia: 0xe432150cce91c13a887f7D836923d5597adD8E31, 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6, 0x0D41f814326cc88c27532f922F5d5B490047518a

// token BASE: 0x30d6D9Cb5De7B8Fa3da16655bd1188B8C4d4F87F
// token SEPOLIA: 0x0D41f814326cc88c27532f922F5d5B490047518a

// https://testnet.axelarscan.io/gmp/0x3f68db75f32891479ff057bb4f673a73c24f99f6f6eccf8d34fc9a0755903c12


import { AxelarExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol';
import { IAxelarGateway } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol';
import { IAxelarGasService } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol';
// import "@openzeppelin/contracts@4.0.0/access/Ownable.sol";
// import "@openzeppelin/contracts@4.0.0/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts@5.0.2/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract MicroBridge is AxelarExecutable, Ownable {
    // string public message;
    // string public sourceChain;
    // string public sourceAddress;
    IAxelarGasService public immutable gasService;
    IERC20 public token;
    uint256 sourceFee = 500000; // 0,5 USDC at source
    uint256 destinationFee = 500000; // 0,5 USDC at destination
    mapping(address => bool) public allowedSourceAddress;

    struct Transaction {
        uint256 amount;
        uint256 sourceFee;
        uint256 destinationFee;
        address recipient;
    }

    event Executed(string sourceChain, string _from, Transaction _transaction);

    mapping(address => Transaction[]) public receivedTransactions;

    constructor(address _gateway, address _gasReceiver, address _token)
    AxelarExecutable(_gateway)
    Ownable(msg.sender)
    {
        gasService = IAxelarGasService(_gasReceiver);
        token = IERC20(_token);
    }

    function bridge(
        string calldata destinationChain,
        string calldata destinationAddress,
        address recipientAddress,
        uint256 _amount
    ) external payable {
        require(msg.value > 0, 'Gas payment is required');

        uint256 senderBalance = token.balanceOf(msg.sender);
        uint256 amountWithFee = _amount + sourceFee + destinationFee;
        require(senderBalance >= amountWithFee, "less amount + baseFee + destinationFee is less that balance");

        TransferHelper.safeTransferFrom(address(token), msg.sender, address(this), amountWithFee);
        Transaction memory transaction = Transaction((amountWithFee - sourceFee), sourceFee, destinationFee, recipientAddress);

        bytes memory payload = abi.encode(transaction);
        gasService.payNativeGasForContractCall{ value: msg.value }(
            address(this),
            destinationChain,
            destinationAddress,
            payload,
            msg.sender
        );

        gateway.callContract(destinationChain, destinationAddress, payload);
    }

    function _execute(string calldata _sourceChain, string calldata _sourceAddress, bytes calldata _payload) internal override {
        require(allowedSourceAddress[address(bytes20(bytes(_sourceAddress)))] == true, 'sourceAddress not allowed');

        Transaction memory transaction = abi.decode(_payload, (Transaction));
        string memory sourceChain = _sourceChain;
        string memory  sourceAddress = _sourceAddress;
        receivedTransactions[transaction.recipient].push(transaction);
        // TransferHelper
        // check address
        uint256 balanceOf = token.balanceOf(address(this));
        // uint256 amountWithFee = _amount + sourceFee + destinationFee;
        require(balanceOf >= (transaction.amount - destinationFee), "less amount +  destinationFee is less that balance");
        TransferHelper.safeTransferFrom(address(token), address(this), transaction.recipient, (transaction.amount - destinationFee));

        emit Executed(sourceChain, sourceAddress, transaction);
    }

    function setAllowedSourceAddress(address _allowedAdress, bool _active) public onlyOwner {
        allowedSourceAddress[_allowedAdress] = _active;
    }

}