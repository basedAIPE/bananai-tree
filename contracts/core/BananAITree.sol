// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IDustRegistry.sol";
import "../interfaces/IMetricsLibrary.sol";
import "../interfaces/ISwapRouter.sol";
import "../interfaces/IBananAILiquidity.sol";
import "../interfaces/IBananAIToken.sol";

/**
 * @title BananAITree
 * @notice Main contract for the BananAI Tree protocol
 * @dev Handles dust collection, conversion, and liquidity management
 */
contract BananAITree is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant BATCH_ROLE = keccak256("BATCH_ROLE");

    // Component references
    IDustRegistry public immutable dustRegistry;
    IMetricsLibrary public immutable metricsLib;
    ISwapRouter public immutable swapRouter;
    IBananAILiquidity public immutable liquidityManager;
    IBananAIToken public immutable bananaiToken;
    address public immutable WETH;

    // Batch configuration
    uint256 public constant MIN_BATCH_SIZE = 1 ether;
    uint256 public batchThreshold;
    mapping(address => uint256) public pendingDust;
    mapping(address => uint256) public dustDepositors;
    
    // User tracking
    struct UserDeposit {
        uint256 amount;
        uint256 timestamp;
        uint256 estimatedValue;
    }
    mapping(address => mapping(address => UserDeposit[])) public userDeposits;

    // Events
    event DustDeposited(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 estimatedValue,
        uint256 bananaiMinted
    );
    event BatchProcessed(
        address indexed token,
        uint256 totalAmount,
        uint256 ethReceived,
        uint256 bananaiUsed
    );
    event BatchThresholdUpdated(uint256 newThreshold);

    constructor(
        address _dustRegistry,
        address _metricsLib,
        address _swapRouter,
        address _liquidityManager,
        address _bananaiToken,
        address _weth,
        uint256 _batchThreshold
    ) {
        require(_dustRegistry != address(0), "Invalid registry");
        require(_metricsLib != address(0), "Invalid metrics");
        require(_swapRouter != address(0), "Invalid router");
        require(_liquidityManager != address(0), "Invalid liquidity");
        require(_bananaiToken != address(0), "Invalid token");
        require(_weth != address(0), "Invalid WETH");

        dustRegistry = IDustRegistry(_dustRegistry);
        metricsLib = IMetricsLibrary(_metricsLib);
        swapRouter = ISwapRouter(_swapRouter);
        liquidityManager = IBananAILiquidity(_liquidityManager);
        bananaiToken = IBananAIToken(_bananaiToken);
        WETH = _weth;
        batchThreshold = _batchThreshold;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(BATCH_ROLE, msg.sender);
    }

    /**
     * @notice Deposits dust tokens into the protocol
     * @param tokens Array of token addresses to deposit
     * @param amounts Array of amounts to deposit
     */
    function depositDust(
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external nonReentrant whenNotPaused {
        require(tokens.length == amounts.length, "Length mismatch");
        require(tokens.length > 0, "Empty deposit");

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = amounts[i];

            require(dustRegistry.isAccepted(token), "Token not accepted");
            require(amount > 0, "Zero amount");

            // Get optimal swap route for valuation
            ISwapRouter.SwapRoute memory route = swapRouter.getOptimalSwap(
                token,
                WETH,
                amount
            );

            // Calculate BANANAI issuance
            uint256 issuanceRate = metricsLib.calculateIssuanceRate(token, amount);
            uint256 bananaiToMint = (route.expectedReturn * issuanceRate) / 1e18;

            // Transfer and track dust
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            pendingDust[token] += amount;
            dustDepositors[token]++;

            // Store user deposit
            userDeposits[msg.sender][token].push(UserDeposit({
                amount: amount,
                timestamp: block.timestamp,
                estimatedValue: route.expectedReturn
            }));

            // Mint BANANAI
            bananaiToken.mint(msg.sender, bananaiToMint);

            // Update metrics
            metricsLib.updateMetrics(
                token,
                route.expectedReturn,
                liquidityManager.getLiquidityValue(),
                amount
            );

            emit DustDeposited(
                msg.sender,
                token,
                amount,
                route.expectedReturn,
                bananaiToMint
            );

            // Process batch if threshold met
            if (pendingDust[token] >= batchThreshold) {
                _processBatch(token);
            }
        }
    }

    /**
     * @notice Processes a batch of collected dust
     * @param token The token to process
     */
    function _processBatch(address token) internal {
        uint256 amount = pendingDust[token];
        require(amount >= MIN_BATCH_SIZE, "Batch too small");

        // Swap dust for ETH
        IERC20(token).safeApprove(address(swapRouter), amount);
        
        ISwapRouter.SwapParams memory params = ISwapRouter.SwapParams({
            srcToken: token,
            destToken: WETH,
            amount: amount,
            minReturn: 0,
            receiver: address(this)
        });

        uint256 ethReceived = swapRouter.executeSwap(params);

        // Add liquidity
        uint256 bananaiAmount = (ethReceived * 1e18) / metricsLib.getMetrics(token).harmonicMeanPrice;
        bananaiToken.mint(address(this), bananaiAmount);
        
        bananaiToken.approve(address(liquidityManager), bananaiAmount);
        liquidityManager.addLiquidity{value: ethReceived}(bananaiAmount);

        // Reset batch tracking
        pendingDust[token] = 0;
        dustDepositors[token] = 0;

        emit BatchProcessed(
            token,
            amount,
            ethReceived,
            bananaiAmount
        );
    }

    // Admin functions...
    function setBatchThreshold(uint256 newThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newThreshold >= MIN_BATCH_SIZE, "Threshold too low");
        batchThreshold = newThreshold;
        emit BatchThresholdUpdated(newThreshold);
    }

    function emergencyProcessBatch(address token) external onlyRole(BATCH_ROLE) {
        _processBatch(token);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // View functions...
    function getPendingBatch(address token) external view returns (
        uint256 amount,
        uint256 depositors,
        uint256 estimatedEth
    ) {
        amount = pendingDust[token];
        depositors = dustDepositors[token];
        
        if (amount > 0) {
            ISwapRouter.SwapRoute memory route = swapRouter.getOptimalSwap(
                token,
                WETH,
                amount
            );
            estimatedEth = route.expectedReturn;
        }
    }

    function getUserDeposits(
        address user,
        address token
    ) external view returns (UserDeposit[] memory) {
        return userDeposits[user][token];
    }

    receive() external payable {}
}
