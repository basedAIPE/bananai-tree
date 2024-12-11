// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title DustRegistry
 * @notice Manages accepted tokens and their configurations
 * @dev Tracks token metadata and liquidity requirements
 */
contract DustRegistry is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    
    struct TokenInfo {
        bool accepted;
        uint256 minAmount;
        uint256 maxAmount;
        uint8 decimals;
        uint256 addedTimestamp;
        address[] liquidityPairs;
        uint256 dailyLimit;
        uint256 usedToday;
        uint256 lastResetTime;
    }
    
    // State variables
    mapping(address => TokenInfo) public tokens;
    address[] public acceptedTokens;
    uint256 public minimumLiquidityRequired;
    
    // Events
    event TokenAdded(
        address indexed token,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 dailyLimit
    );
    event TokenRemoved(address indexed token);
    event TokenLimitsUpdated(
        address indexed token,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 dailyLimit
    );
    event LiquidityRequirementUpdated(uint256 newRequirement);
    
    constructor(uint256 _minimumLiquidityRequired) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
        minimumLiquidityRequired = _minimumLiquidityRequired;
    }
    
    /**
     * @notice Adds a new token to the registry
     * @param token Token address
     * @param minAmount Minimum amount acceptable
     * @param maxAmount Maximum amount acceptable
     * @param dailyLimit Daily volume limit
     */
    function addToken(
        address token,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 dailyLimit
    ) external onlyRole(MANAGER_ROLE) {
        require(token != address(0), "Invalid token");
        require(!tokens[token].accepted, "Already accepted");
        require(minAmount > 0 && maxAmount >= minAmount, "Invalid limits");
        require(dailyLimit >= maxAmount, "Invalid daily limit");
        
        uint8 decimals = IERC20Metadata(token).decimals();
        address[] memory pairs = new address[](0);
        
        tokens[token] = TokenInfo({
            accepted: true,
            minAmount: minAmount,
            maxAmount: maxAmount,
            decimals: decimals,
            addedTimestamp: block.timestamp,
            liquidityPairs: pairs,
            dailyLimit: dailyLimit,
            usedToday: 0,
            lastResetTime: block.timestamp
        });
        
        acceptedTokens.push(token);
        emit TokenAdded(token, minAmount, maxAmount, dailyLimit);
    }
    
    /**
     * @notice Removes a token from the registry
     * @param token Token address
     */
    function removeToken(address token) external onlyRole(MANAGER_ROLE) {
        require(tokens[token].accepted, "Token not accepted");
        
        tokens[token].accepted = false;
        
        // Remove from accepted tokens array
        for (uint256 i = 0; i < acceptedTokens.length; i++) {
            if (acceptedTokens[i] == token) {
                acceptedTokens[i] = acceptedTokens[acceptedTokens.length - 1];
                acceptedTokens.pop();
                break;
            }
        }
        
        emit TokenRemoved(token);
    }
    
    /**
     * @notice Updates token limits
     * @param token Token address
     * @param minAmount New minimum amount
     * @param maxAmount New maximum amount
     * @param dailyLimit New daily limit
     */
    function updateTokenLimits(
        address token,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 dailyLimit
    ) external onlyRole(MANAGER_ROLE) {
        require(tokens[token].accepted, "Token not accepted");
        require(minAmount > 0 && maxAmount >= minAmount, "Invalid limits");
        require(dailyLimit >= maxAmount, "Invalid daily limit");
        
        TokenInfo storage info = tokens[token];
        info.minAmount = minAmount;
        info.maxAmount = maxAmount;
        info.dailyLimit = dailyLimit;
        
        emit TokenLimitsUpdated(token, minAmount, maxAmount, dailyLimit);
    }
    
    /**
     * @notice Checks if an amount is within acceptable limits
     * @param token Token address
     * @param amount Amount to check
     * @return Whether the amount is acceptable
     */
    function isAcceptableAmount(
        address token,
        uint256 amount
    ) external returns (bool) {
        TokenInfo storage info = tokens[token];
        require(info.accepted, "Token not accepted");
        
        // Reset daily limit if needed
        if (block.timestamp >= info.lastResetTime + 1 days) {
            info.usedToday = 0;
            info.lastResetTime = block.timestamp;
        }
        
        // Check limits
        if (amount < info.minAmount || amount > info.maxAmount) {
            return false;
        }
        
        // Check daily limit
        if (info.usedToday + amount > info.dailyLimit) {
            return false;
        }
        
        // Update used amount
        info.usedToday += amount;
        return true;
    }
    
    // View functions
    function isAccepted(address token) external view returns (bool) {
        return tokens[token].accepted;
    }
    
    function getTokenInfo(
        address token
    ) external view returns (TokenInfo memory) {
        return tokens[token];
    }
    
    function getAcceptedTokens() external view returns (address[] memory) {
        return acceptedTokens;
    }
    
    // Admin functions
    function updateMinimumLiquidity(
        uint256 newRequirement
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minimumLiquidityRequired = newRequirement;
        emit LiquidityRequirementUpdated(newRequirement);
    }
    
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
