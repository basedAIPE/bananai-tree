// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title SwapRouter
 * @notice Manages token swaps through Paraswap integration
 * @dev Handles optimal route finding and swap execution
 */
contract SwapRouter is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    
    // Paraswap integration
    address public immutable augustusSwapper;
    address public immutable tokenTransferProxy;
    uint256 public constant PARTIAL_FILL = 0; // No partial fills allowed
    uint256 public constant DEFAULT_DEADLINE = 20 minutes;
    
    // Protocol settings
    uint256 public constant MAX_SLIPPAGE = 1000; // 10% max slippage
    uint256 public slippageTolerance = 100; // 1% default slippage
    uint256 public maxGasPrice = 500 gwei;
    
    struct SwapParams {
        address srcToken;
        address destToken;
        uint256 srcAmount;
        uint256 destAmount;
        uint256 minDestAmount;
        bytes permitData;
        bytes payload;
    }
    
    struct SwapRoute {
        uint256 expectedReturn;
        bytes swapData;
        uint256 gas;
    }
    
    // Events
    event SwapExecuted(
        address indexed srcToken,
        address indexed destToken,
        address indexed user,
        uint256 srcAmount,
        uint256 destAmount
    );
    
    event SlippageUpdated(uint256 newSlippage);
    event GasLimitUpdated(uint256 newLimit);
    event ReferralSet(bytes32 referral);
    
    /**
     * @notice Contract constructor
     * @param _augustus Paraswap Augustus address
     * @param _transferProxy Paraswap TokenTransferProxy address
     */
    constructor(
        address _augustus,
        address _transferProxy
    ) {
        require(_augustus != address(0), "Invalid Augustus");
        require(_transferProxy != address(0), "Invalid proxy");
        
        augustusSwapper = _augustus;
        tokenTransferProxy = _transferProxy;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);
    }
    
    /**
     * @notice Gets the optimal swap route through Paraswap
     * @param srcToken Source token address
     * @param destToken Destination token address
     * @param amount Amount to swap
     * @return SwapRoute Optimal route information
     */
    function getOptimalSwap(
        address srcToken,
        address destToken,
        uint256 amount
    ) external view whenNotPaused returns (SwapRoute memory) {
        require(amount > 0, "Invalid amount");
        
        // Call to Paraswap price API
        (uint256 expectedReturn, bytes memory swapData) = _getParaswapRate(
            srcToken,
            destToken,
            amount
        );
        
        // Estimate gas (implementation specific to route)
        uint256 estimatedGas = _estimateSwapGas(swapData);
        
        return SwapRoute({
            expectedReturn: expectedReturn,
            swapData: swapData,
            gas: estimatedGas
        });
    }
    
    /**
     * @notice Executes a swap through Paraswap
     * @param params Swap parameters
     * @return destAmount Amount of destination tokens received
     */
    function executeSwap(
        SwapParams calldata params
    ) external nonReentrant whenNotPaused onlyRole(EXECUTOR_ROLE) returns (uint256) {
        require(params.srcAmount > 0, "Invalid amount");
        require(params.minDestAmount > 0, "Invalid min return");
        require(block.basefee <= maxGasPrice, "Gas price too high");
        
        // Transfer tokens to this contract
        IERC20(params.srcToken).safeTransferFrom(
            msg.sender,
            address(this),
            params.srcAmount
        );
        
        // Approve Paraswap proxy
        IERC20(params.srcToken).safeApprove(tokenTransferProxy, params.srcAmount);
        
        // Execute swap
        uint256 destAmount = _executeParaswapSwap(params);
        require(destAmount >= params.minDestAmount, "Slippage too high");
        
        // Transfer received tokens to user
        IERC20(params.destToken).safeTransfer(msg.sender, destAmount);
        
        emit SwapExecuted(
            params.srcToken,
            params.destToken,
            msg.sender,
            params.srcAmount,
            destAmount
        );
        
        return destAmount;
    }
    
    /**
     * @notice Gets swap rate from Paraswap
     */
    function _getParaswapRate(
        address srcToken,
        address destToken,
        uint256 amount
    ) internal view returns (uint256, bytes memory) {
        // Implementation will call Paraswap price API
        // Placeholder for demonstration
        return (0, "");
    }
    
    /**
     * @notice Estimates gas for swap
     */
    function _estimateSwapGas(
        bytes memory swapData
    ) internal view returns (uint256) {
        // Implementation will estimate gas based on route
        return 300000; // Base estimate
    }
    
    /**
     * @notice Executes swap through Paraswap
     */
    function _executeParaswapSwap(
        SwapParams calldata params
    ) internal returns (uint256) {
        // Implementation will call Augustus contract
        // Placeholder for demonstration
        return 0;
    }
    
    // Admin functions
    function updateSlippage(
        uint256 newSlippage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newSlippage <= MAX_SLIPPAGE, "Slippage too high");
        slippageTolerance = newSlippage;
        emit SlippageUpdated(newSlippage);
    }
    
    function updateGasLimit(
        uint256 newLimit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxGasPrice = newLimit;
        emit GasLimitUpdated(newLimit);
    }
    
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
    
    // Emergency functions
    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).safeTransfer(to, amount);
    }
}
