// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract Vault is ERC4626 {
    constructor(IERC20 _asset) ERC4626(_asset) ERC20("Vault Staked Token", "vSTT") {}
}