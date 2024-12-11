// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function sync() external;
}

/**
 * @title BananAILiquidity
 * @notice Manages liquidity pools and fee collection for the BananAI Tree protocol
 * @dev Integrates with Uniswap V2 compatible DEXs for liquidity provision
 */
contract BananAILiquidity is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Access control roles
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant FEE_SETTER_ROLE = keccak256("FEE_SETTER_ROLE");

    // Protocol constants
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant MAX_FEE = 1000; // 10%
    uint256 public constant MIN_LIQUIDITY = 1000; // Minimum LP tokens to create

    // Protocol state
    IUniswapV2Factory public immutable factory;
    address public immutable bananaiToken;
    address public immutable WETH;
    uint256 public lpFee; // Fee in basis points
    address public feeCollector;

    // Liquidity tracking
    struct PoolInfo {
        uint256 totalLiquidity;
        uint256 lastUpdateBlock;
        uint256 accumulatedFees;
    }
    mapping(address => PoolInfo) public poolInfo;

    // Events
    event LiquidityAdded(
        address indexed token,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 liquidity
    );
    event LiquidityRemoved(
        address indexed token,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 liquidity
    );
    event FeeCollected(
        address indexed token,
        uint256 amount,
        address collector
    );
    event FeeUpdated(uint256 newFee);
    event FeeCollectorUpdated(address newCollector);

    /**
     * @notice Contract constructor
     * @param _factory Uniswap V2 factory address
     * @param _bananai BANANAI token address
     * @param _weth WETH address
     * @param _feeCollector Initial fee collector address
     * @param _initialFee Initial LP fee in basis points
     */
    constructor(
        address _factory,
        address _bananai,
        address _weth,
        address _feeCollector,
        uint256 _initialFee
    ) {
        require(_factory != address(0), "Invalid factory");
        require(_bananai != address(0), "Invalid BANANAI");
        require(_weth != address(0), "Invalid WETH");
        require(_feeCollector != address(0), "Invalid collector");
        require(_initialFee <= MAX_FEE, "Fee too high");

        factory = IUniswapV2Factory(_factory);
        bananaiToken = _bananai;
        WETH = _weth;
        feeCollector = _feeCollector;
        lpFee = _initialFee;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
        _grantRole(FEE_SETTER_ROLE, msg.sender);
    }

    /**
     * @notice Adds liquidity to the BANANAI/ETH pool
     * @param tokenAmount Amount of BANANAI tokens to add
     * @return liquidity Amount of LP tokens received
     */
    function addLiquidity(
        uint256 tokenAmount
    ) external payable nonReentrant whenNotPaused onlyRole(MANAGER_ROLE) returns (uint256) {
        require(msg.value > 0, "No ETH provided");
        require(tokenAmount > 0, "No tokens provided");

        // Calculate and collect fee
        uint256 feeAmount = (tokenAmount * lpFee) / FEE_DENOMINATOR;
        uint256 netAmount = tokenAmount - feeAmount;

        // Transfer tokens
        IERC20(bananaiToken).safeTransferFrom(msg.sender, address(this), tokenAmount);

        // Handle fee
        if (feeAmount > 0) {
            IERC20(bananaiToken).safeTransfer(feeCollector, feeAmount);
            emit FeeCollected(bananaiToken, feeAmount, feeCollector);
        }

        // Get or create pair
        address pair = factory.getPair(bananaiToken, WETH);
        if (pair == address(0)) {
            pair = factory.createPair(bananaiToken, WETH);
        }

        // Add liquidity
        IERC20(bananaiToken).safeTransfer(pair, netAmount);
        uint256 liquidity = IUniswapV2Pair(pair).mint{value: msg.value}(address(this));
        require(liquidity >= MIN_LIQUIDITY, "Insufficient liquidity");

        // Update pool info
        PoolInfo storage pool = poolInfo[pair];
        pool.totalLiquidity += liquidity;
        pool.lastUpdateBlock = block.number;
        pool.accumulatedFees += feeAmount;

        emit LiquidityAdded(bananaiToken, netAmount, msg.value, liquidity);

        // Return unused ETH
        if (msg.value > msg.value) {
            (bool success, ) = msg.sender.call{value: msg.value - msg.value}("");
            require(success, "ETH return failed");
        }

        return liquidity;
    }

    /**
     * @notice Removes liquidity from the BANANAI/ETH pool
     * @param liquidity Amount of LP tokens to burn
     * @param minTokenAmount Minimum BANANAI tokens to receive
     * @param minEthAmount Minimum ETH to receive
     * @return tokenAmount Amount of BANANAI tokens received
     * @return ethAmount Amount of ETH received
     */
    function removeLiquidity(
        uint256 liquidity,
        uint256 minTokenAmount,
        uint256 minEthAmount
    ) external nonReentrant whenNotPaused onlyRole(MANAGER_ROLE) returns (uint256, uint256) {
        require(liquidity > 0, "Invalid liquidity");

        address pair = factory.getPair(bananaiToken, WETH);
        require(pair != address(0), "No liquidity pair");

        // Approve and burn LP tokens
        IERC20(pair).safeApprove(pair, liquidity);
        (uint256 tokenAmount, uint256 ethAmount) = IUniswapV2Pair(pair).burn(address(this));

        require(tokenAmount >= minTokenAmount, "Insufficient tokens");
        require(ethAmount >= minEthAmount, "Insufficient ETH");

        // Update pool info
        PoolInfo storage pool = poolInfo[pair];
        pool.totalLiquidity -= liquidity;
        pool.lastUpdateBlock = block.number;

        emit LiquidityRemoved(bananaiToken, tokenAmount, ethAmount, liquidity);

        return (tokenAmount, ethAmount);
    }

    /**
     * @notice Get current liquidity value in ETH terms
     * @return value Total value of liquidity in ETH
     */
    function getLiquidityValue() external view returns (uint256) {
        address pair = factory.getPair(bananaiToken, WETH);
        if (pair == address(0)) return 0;

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        bool isBananaiToken0 = IUniswapV2Pair(pair).token0() == bananaiToken;

        uint256 ethReserve = isBananaiToken0 ? uint256(reserve1) : uint256(reserve0);
        return ethReserve * 2; // Return total ETH value of pool
    }

    // Admin functions
    function updateFeeCollector(
        address newCollector
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newCollector != address(0), "Invalid collector");
        feeCollector = newCollector;
        emit FeeCollectorUpdated(newCollector);
    }

    function updateLPFee(
        uint256 newFee
    ) external onlyRole(FEE_SETTER_ROLE) {
        require(newFee <= MAX_FEE, "Fee too high");
        lpFee = newFee;
        emit FeeUpdated(newFee);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    receive() external payable {}
}
