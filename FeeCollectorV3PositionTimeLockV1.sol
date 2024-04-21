// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;
pragma abicoder v2;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
// import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
// import "@openzeppelin/contracts@5.0.2/interfaces/IERC4626.sol";
// import "@openzeppelin/contracts/utils/math/SafeMath.sol";


interface INonfungiblePositionManager {

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);

    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

contract FeeCollectorV3PositionTimeLockV1 is IERC721Receiver, Ownable, ReentrancyGuard {
    uint256 public defaultLockDuration = 7 days;

    struct LockedPosition {
        INonfungiblePositionManager positionManager;
        address positionOwner;
        uint256 tokenId;
        uint256 releaseTime;
    }

    // mapping(address => mapping(address => uint256)) public userLockedPositionsTokenId;
    mapping(address => mapping(bytes32 => LockedPosition)) private lockedPositions;

    // INonfungiblePositionManager public positionManager;

    constructor(address initialOwner) Ownable(initialOwner) {}

    event FeesCollected(address indexed user, address indexed positionManager, uint256 tokenId, uint256 amount0, uint256 amount1);
    event PositionLocked(address indexed user, address indexed positionManager, uint256 tokenId, uint256 releaseTime);
    event PositionUnlocked(address indexed user, address indexed positionManager, uint256 tokenId);

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata) external pure override returns (bytes4) {
        // require(address(whitelistedNftContract) == _msgSender());
        // _stakeNft(tokenId, from);
        return IERC721Receiver.onERC721Received.selector;
    }

    function getPositionWithKey(address _from, bytes32 _key) external returns (memory LockedPosition) {
        LockedPosition memory lockedPosition = lockedPositions[_from][_key];
        return lockedPosition;
    }

    function getPositionWithAddress(address _from, address _positionManager, uint256 tokenId) external view returns(memory LockedPosition) {
        bytes32 _key = keyForPosition(_from, _positionManager, tokenId);
        return getPositionWithKey(_from, _key);
    }

    function keyForPosition(address _from, address _positionManger, uint256 tokenId) external view returns(bytes32) {
        return keccak256(abi.encodePacked(_from, _positionManager, tokenId));
    }

    function _hashLockedPositionKey(address _positionManager, uint256 tokenId) private view returns(bytes32) {
        return keccak256(abi.encodePacked(_msgSender(), _positionManager, tokenId));
    }

    function collectFees(address _positionManager, uint256 tokenId, address recipient) external nonReentrant returns (uint256 amount0Collected, uint256 amount1Collected) {
        LockedPosition storage lockedPosition = lockedPositions[_msgSender()][_hashLockedPositionKey(_positionManager, tokenId)];
        require(lockedPosition.positionOwner == _msgSender(), "failed to load position");

        INonfungiblePositionManager positionManager = lockedPosition.positionManager;
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: lockedPosition.tokenId,
            recipient: recipient,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0Collected, amount1Collected) = positionManager.collect(params);
        emit FeesCollected(_msgSender(), _positionManager, tokenId, amount0Collected, amount1Collected);

        return(amount0Collected, amount1Collected);
    }

    function lockPosition(address _positionManager, uint256 tokenId, uint256 lockDurationInSeconds) external {
        uint256 _duration = lockDurationInSeconds;
        if(lockDurationInSeconds == 0) {
            _duration = defaultLockDuration;
        }
        // LockedPosition storage lockedposition = lockedPositions[_msgSender()][_hashLockedPositionKey(_positionManager, tokenId)];
        // require(lockedposition.tokenId != 0, "failed position already locked");
        uint256 releaseTime = (block.timestamp + (_duration));
        require(releaseTime > block.timestamp, "Release time must be in the future");

        INonfungiblePositionManager positionManager = INonfungiblePositionManager(_positionManager);
        positionManager.safeTransferFrom(_msgSender(), address(this), tokenId);

        lockedPositions[_msgSender()][_hashLockedPositionKey(_positionManager, tokenId)] = LockedPosition(positionManager, _msgSender(), tokenId, releaseTime);

        emit PositionLocked(_msgSender(), _positionManager, tokenId, releaseTime);
    }

    function unlockPosition(address _positionManager, uint256 tokenId) external {
        LockedPosition storage lockedPosition = lockedPositions[_msgSender()][_hashLockedPositionKey(_positionManager, tokenId)];
        require(lockedPosition.positionOwner == _msgSender(), "failed to load position, not Owner");
        require(block.timestamp >= lockedPosition.releaseTime, "not in time to unlock");

        INonfungiblePositionManager positionManager = lockedPosition.positionManager;
        positionManager.safeTransferFrom(address(this), _msgSender(), tokenId);

        delete lockedPositions[_msgSender()][_hashLockedPositionKey(_positionManager, tokenId)];
    }


}