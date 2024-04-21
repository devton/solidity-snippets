// SPDX-License-Identifier: MIT
pragma solidity >=0.8.16;
pragma abicoder v2;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
// import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IAxelarGateway.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


contract AxelarIntegration is Ownable, ReentrancyGuard {
    IAxelarGateway public axelarGateway;

    IERC20 private axlUSDC;

    constructor(address firstOwner, address _axelarGatewayAddress, address _axlUSDCAddress) Ownable(firstOwner) {
        axelarGateway = IAxelarGateway(_axelarGatewayAddress);
        axlUSDC = IERC20(_axlUSDCAddress);
    }

    function sendTokensToAnotherChain(string calldata destChain, string calldata destination, string memory symbol, uint256 amount) public nonReentrant onlyOwner {
        uint256 balance = axlUSDC.balanceOf(address(this));
        require(balance >= amount, "amount > balance");
        require(keccak256(bytes(symbol)) == keccak256(bytes("axlUSDC")), "only axlUSDC enabled");

        // Polygon
        TransferHelper.safeApprove(address(axlUSDC), address(axelarGateway), amount);
        axelarGateway.sendToken(destChain, destination, symbol, amount);
    }

    function recoverToken(address _tokenAddress, address recipient, uint256 _amount) external nonReentrant onlyOwner {
        IERC20 _token = IERC20(_tokenAddress);
        uint256 balance = _token.balanceOf(address(this));
        require(balance >= _amount, "_amount > balance");

        TransferHelper.safeTransferFrom(_tokenAddress, address(this), recipient, _amount);
    }
}