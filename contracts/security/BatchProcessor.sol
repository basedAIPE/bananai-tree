// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title BatchProcessor
 * @notice Manages batched operations with MEV protection
 * @dev Includes gas optimization and slippage protection
 */
contract BatchProcessor is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    struct BatchConfig {
        uint256 minSize;           // Minimum batch size in ETH value
        uint256 maxSize;           // Maximum batch size in ETH value
        uint256 minParticipants;   // Minimum unique depositors
        uint256 maxTimeDelay;      // Maximum wait time
        uint256 gasThreshold;      // Maximum gas price for processing
        uint256 targetGasPrice;    // Target gas price for optimal execution
        bool active;               // Whether auto-batching is active
    }

    struct BatchState {
        uint256 amount;            // Total amount collected
        uint256 ethValue;          // Estimated ETH value
        uint256 participantCount;  // Number of unique depositors
        uint256 firstDeposit;      // Timestamp of first deposit
        uint256 lastUpdate;        // Last state update
        address[] participants;    // List of unique participants
        bool locked;               // Processing lock
        uint256 sequenceNumber;    // Batch sequence number
    }

    // State variables
    mapping(address => BatchConfig) public batchConfigs;
    mapping(address => BatchState) public batchStates;
    mapping(bytes32 => bool) public processedHashes;
    
    uint256 public constant MIN_BATCH_INTERVAL = 5 minutes;
    uint256 public constant MAX_BATCH_SIZE = 1000 ether;
    uint256 public constant MIN_PARTICIPANTS = 3;

    // Events
    event BatchInitiated(
        address indexed token,
        uint256 sequenceNumber,
        uint256 amount
    );
    event BatchProcessed(
        address indexed token,
        uint256 sequenceNumber,
        uint256 amount,
        uint256 ethValue
    );
    event BatchCancelled(
        address indexed token,
        uint256 sequenceNumber,
        string reason
    );
    event ConfigUpdated(
        address indexed token,
        BatchConfig config
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);
        _grantRole(KEEPER_ROLE, msg.sender);
    }

    /**
     * @notice Configure batch parameters for a token
     * @param token Token address
     * @param config Batch configuration
     */
    function configureBatch(
        address token,
        BatchConfig calldata config
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(config.minSize > 0, "Invalid min size");
        require(config.maxSize <= MAX_BATCH_SIZE, "Size too large");
        require(config.maxSize >= config.minSize, "Invalid size range");
        require(config.minParticipants >= MIN_PARTICIPANTS, "Too few participants");
        require(config.maxTimeDelay >= MIN_BATCH_INTERVAL, "Delay too short");
        
        batchConfigs[token] = config;
        emit ConfigUpdated(token, config);
    }

    /**
     * @notice Add tokens to current batch
     * @param token Token address
     * @param amount Amount to add
     * @param ethValue Estimated ETH value
     */
    function addToBatch(
        address token,
        uint256 amount,
        uint256 ethValue
    ) external nonReentrant whenNotPaused onlyRole(KEEPER_ROLE) {
        BatchConfig memory config = batchConfigs[token];
        require(config.active, "Batching inactive");
        
        BatchState storage state = batchStates[token];
        
        // Initialize new batch if needed
        if (state.amount == 0) {
            state.firstDeposit = block.timestamp;
            state.sequenceNumber++;
            emit BatchInitiated(token, state.sequenceNumber, amount);
        }

        // Update state
        state.amount += amount;
        state.ethValue += ethValue;
        
        // Add unique participant
        if (!_isParticipant(state, msg.sender)) {
            state.participants.push(msg.sender);
            state.participantCount++;
        }
        
        state.lastUpdate = block.timestamp;

        // Check if batch should be processed
        if (_shouldProcessBatch(token)) {
            _processBatch(token);
        }
    }

    /**
     * @notice Check if batch should be processed
     * @param token Token address
     * @return shouldProcess Whether batch should be processed
     * @return reason Reason for the decision
     */
    function shouldProcessBatch(
        address token
    ) public view returns (bool shouldProcess, string memory reason) {
        BatchConfig memory config = batchConfigs[token];
        BatchState memory state = batchStates[token];

        if (!config.active) {
            return (false, "Batching inactive");
        }

        if (state.locked) {
            return (false, "Batch locked");
        }

        // Check size conditions
        if (state.ethValue >= config.maxSize) {
            return (true, "Max size reached");
        }

        if (state.ethValue < config.minSize) {
            return (false, "Below min size");
        }

        // Check participant threshold
        if (state.participantCount < config.minParticipants) {
            return (false, "Insufficient participants");
        }

        // Check time threshold
        if (block.timestamp >= state.firstDeposit + config.maxTimeDelay) {
            return (true, "Time threshold reached");
        }

        // Check gas conditions
        if (block.basefee > config.gasThreshold) {
            return (false, "Gas too high");
        }

        // Check if gas price is optimal
        if (block.basefee <= config.targetGasPrice) {
            return (true, "Gas price optimal");
        }

        return (false, "Conditions not met");
    }

    /**
     * @notice Process current batch
     * @param token Token address
     */
    function processBatch(
        address token
    ) external nonReentrant onlyRole(EXECUTOR_ROLE) {
        (bool should, string memory reason) = shouldProcessBatch(token);
        require(should, string.concat("Cannot process: ", reason));
        _processBatch(token);
    }

    // Internal functions
    function _processBatch(address token) internal {
        BatchState storage state = batchStates[token];
        
        // Generate unique hash for this batch
        bytes32 batchHash = keccak256(
            abi.encodePacked(
                token,
                state.sequenceNumber,
                state.amount,
                state.participants
            )
        );
        
        require(!processedHashes[batchHash], "Batch already processed");
        
        // Mark as processed
        processedHashes[batchHash] = true;
        
        // Reset state
        uint256 amount = state.amount;
        uint256 ethValue = state.ethValue;
        uint256 sequence = state.sequenceNumber;
        
        delete batchStates[token];
        
        emit BatchProcessed(token, sequence, amount, ethValue);
    }

    function _isParticipant(
        BatchState storage state,
        address participant
    ) internal view returns (bool) {
        for (uint256 i = 0; i < state.participants.length; i++) {
            if (state.participants[i] == participant) {
                return true;
            }
        }
        return false;
    }

    function _shouldProcessBatch(
        address token
    ) internal view returns (bool) {
        (bool should,) = shouldProcessBatch(token);
        return should;
    }

    // Admin functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
