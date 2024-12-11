// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title MetricsLibrary
 * @notice Handles all metric calculations for the BananAI protocol with strict rate limits
 * @dev Uses harmonic means and enforces a maximum 99% issuance rate
 */
contract MetricsLibrary is AccessControl, ReentrancyGuard {
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    
    // Precision and limits
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_ISSUANCE_RATE = 99 * PRECISION / 100;  // 99% absolute maximum
    uint256 public constant BASE_RATE_CAP = 90 * PRECISION / 100;      // 90% base maximum
    uint256 public constant MAX_VELOCITY_BONUS = PRECISION / 5;         // 20% maximum velocity bonus
    uint256 public constant MAX_AMOUNT_BONUS = PRECISION / 10;         // 10% maximum size bonus
    uint256 public constant MAX_STABILITY_REDUCTION = PRECISION / 5;   // 20% maximum stability penalty
    
    // Time windows
    uint256 public constant HISTORY_LENGTH = 24;           // 24 hour history
    uint256 public constant MIN_POINTS = 3;                // Minimum points for valid metrics
    uint256 public constant UPDATE_INTERVAL = 1 hours;     // Minimum time between updates
    uint256 public constant LARGE_AMOUNT_THRESHOLD = 100 ether;  // Threshold for amount bonus
    
    struct TokenMetrics {
        // Price metrics
        uint256[] pricePoints;
        uint256 harmonicMeanPrice;
        uint256 priceIndex;
        
        // Volume metrics
        uint256[] volumePoints;
        uint256 volumeVelocity;
        uint256 volumeIndex;
        
        // Liquidity metrics
        uint256[] liquidityPoints;
        uint256 harmonicMeanLiquidity;
        uint256 liquidityIndex;
        
        // Time tracking
        uint256 lastUpdateTimestamp;
        uint256 lastVelocityUpdate;
    }
    
    // State
    mapping(address => TokenMetrics) public tokenMetrics;
    
    // Events
    event MetricsUpdated(
        address indexed token,
        uint256 harmonicMeanPrice,
        uint256 harmonicMeanLiquidity,
        uint256 volumeVelocity,
        uint256 timestamp
    );
    
    event RateCalculated(
        address indexed token,
        uint256 baseRate,
        uint256 velocityBonus,
        uint256 stabilityFactor,
        uint256 amountBonus,
        uint256 finalRate
    );
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, msg.sender);
    }
    
    /**
     * @notice Updates metrics for a token
     * @param token Token address
     * @param price Current price in ETH
     * @param liquidity Current liquidity
     * @param volume Current volume
     */
    function updateMetrics(
        address token,
        uint256 price,
        uint256 liquidity,
        uint256 volume
    ) external onlyRole(UPDATER_ROLE) returns (TokenMetrics memory) {
        TokenMetrics storage metrics = tokenMetrics[token];
        
        // Initialize if first update
        if (metrics.pricePoints.length == 0) {
            _initializeMetrics(metrics);
        }
        
        // Update all metrics
        _updateMetricPoint(metrics.pricePoints, metrics.priceIndex, price);
        _updateMetricPoint(metrics.liquidityPoints, metrics.liquidityIndex, liquidity);
        _updateMetricPoint(metrics.volumePoints, metrics.volumeIndex, volume);
        
        // Calculate harmonic means
        metrics.harmonicMeanPrice = _calculateHarmonicMean(metrics.pricePoints);
        metrics.harmonicMeanLiquidity = _calculateHarmonicMean(metrics.liquidityPoints);
        
        // Update indices
        metrics.priceIndex = (metrics.priceIndex + 1) % HISTORY_LENGTH;
        metrics.liquidityIndex = (metrics.liquidityIndex + 1) % HISTORY_LENGTH;
        metrics.volumeIndex = (metrics.volumeIndex + 1) % HISTORY_LENGTH;
        
        // Update velocity if enough time has passed
        if (block.timestamp >= metrics.lastVelocityUpdate + UPDATE_INTERVAL) {
            metrics.volumeVelocity = _calculateVolumeVelocity(metrics.volumePoints);
            metrics.lastVelocityUpdate = block.timestamp;
        }
        
        metrics.lastUpdateTimestamp = block.timestamp;
        
        emit MetricsUpdated(
            token,
            metrics.harmonicMeanPrice,
            metrics.harmonicMeanLiquidity,
            metrics.volumeVelocity,
            block.timestamp
        );
        
        return metrics;
    }
    
    /**
     * @notice Calculates issuance rate with strict caps
     * @param token Token address
     * @param amount Amount being deposited
     * @return Rate to apply (scaled by PRECISION)
     */
    function calculateIssuanceRate(
        address token,
        uint256 amount
    ) external view returns (uint256) {
        TokenMetrics storage metrics = tokenMetrics[token];
        require(metrics.lastUpdateTimestamp > 0, "No metrics available");
        
        // Calculate base rate (capped at BASE_RATE_CAP)
        uint256 baseRate = Math.min(
            _calculateLiquidityRate(metrics.harmonicMeanLiquidity),
            BASE_RATE_CAP
        );
        
        // Calculate velocity bonus (capped at MAX_VELOCITY_BONUS)
        uint256 velocityBonus = Math.min(
            _calculateVelocityBonus(metrics.volumeVelocity),
            MAX_VELOCITY_BONUS
        );
        
        // Calculate stability factor (reduction capped at MAX_STABILITY_REDUCTION)
        uint256 stabilityFactor = _calculateStabilityFactor(metrics.pricePoints);
        
        // Apply stability factor to combined base rate and velocity bonus
        uint256 rateWithBonuses = ((baseRate + velocityBonus) * stabilityFactor) / PRECISION;
        
        // Calculate amount bonus (capped at MAX_AMOUNT_BONUS)
        uint256 amountBonus = Math.min(
            _calculateAmountBonus(amount, rateWithBonuses),
            MAX_AMOUNT_BONUS
        );
        
        // Combine all factors and apply final cap
        uint256 finalRate = Math.min(
            rateWithBonuses + amountBonus,
            MAX_ISSUANCE_RATE
        );
        
        emit RateCalculated(
            token,
            baseRate,
            velocityBonus,
            stabilityFactor,
            amountBonus,
            finalRate
        );
        
        return finalRate;
    }
    
    // Internal calculation functions
    function _calculateLiquidityRate(
        uint256 liquidity
    ) internal pure returns (uint256) {
        if (liquidity == 0) return 0;
        return Math.min(
            (liquidity * PRECISION) / 1000 ether,
            BASE_RATE_CAP
        );
    }
    
    function _calculateVelocityBonus(
        uint256 velocity
    ) internal pure returns (uint256) {
        if (velocity <= PRECISION) return 0;
        return Math.min(
            ((velocity - PRECISION) * PRECISION) / 10,
            MAX_VELOCITY_BONUS
        );
    }
    
    function _calculateStabilityFactor(
        uint256[] memory prices
    ) internal pure returns (uint256) {
        if (prices.length < MIN_POINTS) return PRECISION;
        
        uint256 maxDeviation = 0;
        uint256 lastPrice = prices[prices.length - 1];
        
        for (uint256 i = 0; i < prices.length - 1; i++) {
            if (prices[i] == 0) continue;
            
            uint256 deviation = lastPrice > prices[i] 
                ? lastPrice - prices[i]
                : prices[i] - lastPrice;
                
            maxDeviation = Math.max(maxDeviation, deviation);
        }
        
        uint256 reduction = Math.min(
            (maxDeviation * PRECISION) / lastPrice,
            MAX_STABILITY_REDUCTION
        );
        
        return PRECISION - reduction;
    }
    
    function _calculateAmountBonus(
        uint256 amount,
        uint256 baseRate
    ) internal pure returns (uint256) {
        if (amount < LARGE_AMOUNT_THRESHOLD) return 0;
        return Math.min(
            baseRate / 10,
            MAX_AMOUNT_BONUS
        );
    }
    
    function _calculateHarmonicMean(
        uint256[] memory points
    ) internal pure returns (uint256) {
        uint256 validPoints = 0;
        uint256 sum = 0;
        
        for (uint256 i = 0; i < points.length; i++) {
            if (points[i] > 0) {
                sum += (PRECISION * PRECISION) / points[i];
                validPoints++;
            }
        }
        
        if (validPoints < MIN_POINTS) return 0;
        return (validPoints * PRECISION) / (sum / PRECISION);
    }
    
    function _calculateVolumeVelocity(
        uint256[] memory volumes
    ) internal pure returns (uint256) {
        if (volumes.length < 2) return 0;
        
        uint256 current = volumes[volumes.length - 1];
        uint256 previous = volumes[volumes.length - 2];
        
        if (previous == 0) return 0;
        return (current * PRECISION) / previous;
    }
    
    function _updateMetricPoint(
        uint256[] storage buffer,
        uint256 index,
        uint256 value
    ) internal {
        buffer[index] = value;
    }
    
    function _initializeMetrics(
        TokenMetrics storage metrics
    ) internal {
        metrics.pricePoints = new uint256[](HISTORY_LENGTH);
        metrics.volumePoints = new uint256[](HISTORY_LENGTH);
        metrics.liquidityPoints = new uint256[](HISTORY_LENGTH);
    }
    
    // View functions for testing and verification
    function getMaxPossibleRate() external pure returns (uint256) {
        return MAX_ISSUANCE_RATE;
    }
    
    function simulateRateComponents(
        uint256 liquidity,
        uint256 velocity,
        uint256[] calldata prices,
        uint256 amount
    ) external pure returns (
        uint256 baseRate,
        uint256 velocityBonus,
        uint256 stabilityFactor,
        uint256 amountBonus,
        uint256 finalRate
    ) {
        baseRate = _calculateLiquidityRate(liquidity);
        velocityBonus = _calculateVelocityBonus(velocity);
        stabilityFactor = _calculateStabilityFactor(prices);
        
        uint256 rateWithBonuses = ((baseRate + velocityBonus) * stabilityFactor) / PRECISION;
        amountBonus = _calculateAmountBonus(amount, rateWithBonuses);
        
        finalRate = Math.min(
            rateWithBonuses + amountBonus,
            MAX_ISSUANCE_RATE
        );
        
        return (baseRate, velocityBonus, stabilityFactor, amountBonus, finalRate);
    }
}
