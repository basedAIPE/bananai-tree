// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title EmergencyRecovery
 * @notice Handles emergency situations and fund recovery
 * @dev Includes timelocks and multi-step recovery processes
 */
contract EmergencyRecovery is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant RECOVERY_ROLE = keccak256("RECOVERY_ROLE");

    struct RecoveryState {
        bool active;
        uint256 activationTime;
        address[] affectedTokens;
        mapping(address => uint256) frozenBalances;
        string reason;
        uint256 recoveryLevel;
        address initiator;
    }

    struct RefundClaim {
        address user;
        address token;
        uint256 amount;
        bool processed;
        uint256 timestamp;
        bytes32 merkleRoot;
    }

    // Time constants
    uint256 public constant RECOVERY_DELAY = 6 hours;
    uint256 public constant MAX_RECOVERY_DURATION = 30 days;
    uint256 public constant CLAIM_WINDOW = 90 days;
    uint256 public constant GUARDIAN_COOLDOWN = 24 hours;

    // Recovery levels
    uint256 public constant LEVEL_PAUSE = 1;
    uint256 public constant LEVEL_RESTRICTED = 2;
    uint256 public constant LEVEL_RECOVERY = 3;
    uint256 public constant LEVEL_EMERGENCY = 4;

    // State
    RecoveryState public recoveryState;
    mapping(bytes32 => RefundClaim) public refundClaims;
    mapping(address => uint256) public claimNonces;
    uint256 public lastGuardianAction;
    
    // Events
    event RecoveryActivated(
        uint256 level,
        string reason,
        address[] tokens
    );
    event RecoveryDeactivated(uint256 timestamp);
    event RefundClaimCreated(
        bytes32 indexed claimId,
        address user,
        address token,
        uint256 amount
    );
    event RefundProcessed(
        bytes32 indexed claimId,
        address user,
        uint256 amount
    );
    event FundsRescued(
        address indexed token,
        address recipient,
        uint256 amount
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GUARDIAN_ROLE, msg.sender);
        _grantRole(RECOVERY_ROLE, msg.sender);
    }

    /**
     * @notice Activates recovery mode
     * @param level Recovery level to activate
     * @param reason Reason for recovery
     * @param tokens Affected tokens
     */
    function activateRecovery(
        uint256 level,
        string calldata reason,
        address[] calldata tokens
    ) external onlyRole(GUARDIAN_ROLE) {
        require(!recoveryState.active, "Recovery active");
        require(level >= LEVEL_PAUSE && level <= LEVEL_EMERGENCY, "Invalid level");
        require(
            block.timestamp >= lastGuardianAction + GUARDIAN_COOLDOWN,
            "Guardian cooldown"
        );
        
        recoveryState.active = true;
        recoveryState.activationTime = block.timestamp;
        recoveryState.affectedTokens = tokens;
        recoveryState.reason = reason;
        recoveryState.recoveryLevel = level;
        recoveryState.initiator = msg.sender;

        // Snapshot balances
        for (uint256 i = 0; i < tokens.length; i++) {
            recoveryState.frozenBalances[tokens[i]] = 
                IERC20(tokens[i]).balanceOf(address(this));
        }

        lastGuardianAction = block.timestamp;
        emit RecoveryActivated(level, reason, tokens);
    }

    /**
     * @notice Creates a refund claim
     * @param user User address
     * @param token Token address
     * @param amount Amount to refund
     * @param merkleRoot Merkle root for proof verification
     */
    function createRefundClaim(
        address user,
        address token,
        uint256 amount,
        bytes32 merkleRoot
    ) external onlyRole(RECOVERY_ROLE) returns (bytes32) {
        require(recoveryState.active, "Not in recovery");
        require(
            recoveryState.recoveryLevel >= LEVEL_RECOVERY,
            "Insufficient recovery level"
        );
        
        bytes32 claimId = keccak256(
            abi.encodePacked(
                user,
                token,
                amount,
                claimNonces[user]++,
                merkleRoot
            )
        );

        refundClaims[claimId] = RefundClaim({
            user: user,
            token: token,
            amount: amount,
            processed: false,
            timestamp: block.timestamp,
            merkleRoot: merkleRoot
        });

        emit RefundClaimCreated(claimId, user, token, amount);
        return claimId;
    }

    /**
     * @notice Process a refund claim
     * @param claimId Claim identifier
     * @param merkleProof Proof of claim validity
     */
    function processRefund(
        bytes32 claimId,
        bytes32[] calldata merkleProof
    ) external nonReentrant onlyRole(RECOVERY_ROLE) {
        require(recoveryState.active, "Not in recovery");
        
        RefundClaim storage claim = refundClaims[claimId];
        require(!claim.processed, "Already processed");
        require(
            block.timestamp >= claim.timestamp + RECOVERY_DELAY,
            "Delay not met"
        );
        require(
            block.timestamp <= claim.timestamp + CLAIM_WINDOW,
            "Claim expired"
        );

        // Verify merkle proof
        require(
            _verifyMerkleProof(merkleProof, claim.merkleRoot, claimId),
            "Invalid proof"
        );

        claim.processed = true;
        
        // Process refund
        IERC20(claim.token).safeTransfer(claim.user, claim.amount);
        
        emit RefundProcessed(claimId, claim.user, claim.amount);
    }

    /**
     * @