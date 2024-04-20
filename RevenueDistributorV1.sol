// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
// import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol" as TH;
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
// import "@openzeppelin/contracts/utils/math/SafeMath.sol";



library TransferHelper {
    /// @notice Transfers tokens from the targeted address to the given destination
    /// @notice Errors with 'STF' if transfer fails
    /// @param token The contract address of the token to be transferred
    /// @param from The originating address from which the tokens will be transferred
    /// @param to The destination address of the transfer
    /// @param value The amount to be transferred
    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'STF');
    }

    /// @notice Transfers tokens from msg.sender to a recipient
    /// @dev Errors with ST if transfer fails
    /// @param token The contract address of the token which will be transferred
    /// @param to The recipient of the transfer
    /// @param value The value of the transfer
    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'ST');
    }

    /// @notice Approves the stipulated contract to spend the given allowance in the given token
    /// @dev Errors with 'SA' if transfer fails
    /// @param token The contract address of the token to be approved
    /// @param to The target of the approval
    /// @param value The amount of the given token the target will be allowed to spend
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'SA');
    }

    /// @notice Transfers ETH to the recipient address
    /// @dev Fails with `STE`
    /// @param to The destination of the transfer
    /// @param value The value to be transferred
    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'STE');
    }
}



// should receive a erc20 token to
// register the revenue distribution share into the correct vault
// and deliver the remaning to the treasure contract
// only accept receive the tokens from a call of distribute func

contract RevenueDistributorV1 is Ownable {

    event NewRevenueDistribution(uint256 totalRevenueTokens, uint256 totalAmountOutToken, uint256 totalTokenInVault, uint256 totalTotalSupply, uint256 totalToTreasury, uint256 totalToVault);

    address payable private _treasury;
    address payable private _oldTreasury;
    // address private _token;
    IERC20 private _token;
    IERC20 private _revenueToken;
    IERC4626 private _vault;
    ISwapRouter private immutable _swapRouter;
    uint24 public constant poolFee = 3000;
    uint24 constant BPS = 1E4;

    struct RevenueDistribution {
        uint256 timestamp;
        uint256 blockNumber;
        uint256 totalRevenueTokenAmountIn;
        uint256 totalTokenFromRevenueAmount;
        uint256 totalTokenToVault;
        uint256 totalTokenToTreasury;
        uint256 totalStakedVault;
        uint256 totalTokenSupply;
    }

    RevenueDistribution[] public revenueDistributions;


    constructor(address initialOwner, ISwapRouter swapRouterAddress, address revenueTokenAddress, address treasuryAddress, address vaultAddress)
        Ownable(initialOwner)
    {
        _treasury = payable(treasuryAddress);
        _vault = IERC4626(vaultAddress);
        _token = IERC20(_vault.asset());
        _revenueToken = IERC20(revenueTokenAddress);
        _swapRouter = swapRouterAddress;
    }

    function totalDistributions() public view returns (uint256) {
        return revenueDistributions.length;
    }

    function swapRouter() external view returns (address swapRouerAddress) {
        return address(_swapRouter);
    }

    function revenueToken() external view returns (address revenueTokenAddress) {
        return address(_revenueToken);
    }

    function asset() external view returns (address assetTokenAddress) {
        return address(_token);
    }

    function vault() external view returns (address vaultAddress) {
        return address(_vault);
    }

    function treasury() external view returns (address treasuryWallet) {
        return address(_treasury);
    }

    function changeTreasury(address newTreasury) public virtual onlyOwner {
        require(newTreasury != address(0), "invalid treasury wallet");
        require(newTreasury != address(this), "invalid treasury wallet");
        require(newTreasury != owner(), "invalid treasury wallet, cannot be same of owner");
        require(newTreasury != _treasury, "invalid treasury wallet, cannot be same of owner");

        _oldTreasury = _treasury;
        _treasury = payable(newTreasury);
    }

    function distributeRewards(uint256 amountIn, uint256 amountOutMin, uint160 _sqrtPriceLimitX96) external onlyOwner returns(RevenueDistribution memory _rd) {
        TransferHelper.safeTransferFrom(address(_revenueToken), _msgSender(), address(this), amountIn);
        TransferHelper.safeApprove(address(_revenueToken), address(_swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(_revenueToken),
                tokenOut: address(_token),
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: _sqrtPriceLimitX96
            });

        uint256 amountOut = _swapRouter.exactInputSingle(params);
        uint256 balanceInTokenFromThis = _token.balanceOf(address(this));
        TransferHelper.safeApprove(address(_token), address(this), balanceInTokenFromThis);

        (uint256 totalToTreasoury, uint256 totalToVault) = _ratioDistribution(amountOut);
        TransferHelper.safeTransferFrom(address(_token), address(this), address(_vault), totalToVault);
        uint256 remainingBalance = _token.balanceOf(address(this));
        TransferHelper.safeTransferFrom(address(_token), address(this), _treasury, remainingBalance);

        RevenueDistribution memory rd = RevenueDistribution({
            timestamp: block.timestamp,
            blockNumber: block.number,
            totalRevenueTokenAmountIn: amountIn,
            totalTokenFromRevenueAmount: amountOut,
            totalTokenToVault: totalToVault,
            totalTokenToTreasury: totalToTreasoury,
            totalStakedVault: _vault.totalAssets(),
            totalTokenSupply: _token.totalSupply()
        });

        revenueDistributions.push(rd);

        emit NewRevenueDistribution(amountIn, amountOut, _vault.totalAssets(), _token.totalSupply(), totalToTreasoury, totalToVault);

        return rd;
    }

    function _ratioDistribution(uint256 _amount) internal view returns (uint256 totalToTrearusy, uint256 totalToVault) {
        uint256 totalRatio = 100*BPS;
        uint256 vaultRatio = (_vault.totalAssets() * BPS) / _token.totalSupply();
        // uint256 vaultRatio = vaultTotalAssets.mul(BPS).div(_token.totalSupply());

        require(vaultRatio <= totalRatio, "vault ratio more that total ratio");

        totalToVault = (vaultRatio * _amount) / BPS;
        totalToTrearusy = _amount - totalToVault;
    }

    function ratioDistribution(uint256 _amount) external view returns (uint256 totalToTrearusy, uint256 totalToVault) {
        return _ratioDistribution(_amount);
    }

}