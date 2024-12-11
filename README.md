# BananAI Tree Protocol

## Overview
The BananAI Tree Protocol is a decentralized dust collection and liquidity management system. It allows users to convert small token balances ("dust") into BANANAI tokens, which are backed by consolidated liquidity.

## Contract Structure

```
contracts/
├── core/
│   ├── BananAIToken.sol
│   ├── BananAITree.sol
│   └── BananAILiquidity.sol
├── periphery/
│   ├── SwapRouter.sol
│   └── DustRegistry.sol
├── libraries/
│   └── MetricsLibrary.sol
├── governance/
│   └── BananAIGovernor.sol
└── security/
    ├── BatchProcessor.sol
    └── EmergencyRecovery.sol
```

## Core Components

### BananAIToken (contracts/core/BananAIToken.sol)
- ERC20 token implementation
- Minting/burning controls
- Access control for protocol operations

### BananAITree (contracts/core/BananAITree.sol)
- Main protocol contract
- Handles dust deposits
- Coordinates between components
- Manages issuance rates

### BananAILiquidity (contracts/core/BananAILiquidity.sol)
- Manages liquidity pools
- Handles LP token operations
- Fee collection and distribution

## Periphery

### SwapRouter (contracts/periphery/SwapRouter.sol)
- Paraswap integration
- Optimal path finding
- Slippage protection

### DustRegistry (contracts/periphery/DustRegistry.sol)
- Token whitelist management
- Dust amount validation
- Liquidity pair tracking

## Libraries

### MetricsLibrary (contracts/libraries/MetricsLibrary.sol)
- Price calculations
- Volume tracking
- Liquidity metrics
- Harmonic mean calculations

## Security

### BatchProcessor (contracts/security/BatchProcessor.sol)
- Advanced batching strategies
- Gas optimization
- MEV protection

### EmergencyRecovery (contracts/security/EmergencyRecovery.sol)
- Emergency procedures
- Fund recovery
- Refund management

## Deployment Order
1. BananAIToken
2. DustRegistry
3. MetricsLibrary
4. SwapRouter
5. BananAILiquidity
6. BatchProcessor
7. EmergencyRecovery
8. BananAITree

## Configuration

### Required Environment Variables
```
DEPLOYER_PRIVATE_KEY=
PARASWAP_ROUTER=
NETWORK_RPC_URL=
ETHERSCAN_API_KEY=
```

### Network Specifics
Base Network:
- Chain ID: 8453
- Block Time: ~2s
- Gas Token: ETH

## Security Considerations

### Roles
- DEFAULT_ADMIN_ROLE: Protocol governance
- OPERATOR_ROLE: Day-to-day operations
- GUARDIAN_ROLE: Emergency actions
- KEEPER_ROLE: Automated operations

### Timelock Periods
- Emergency Recovery: 6 hours
- Batch Processing: Configurable (default 24 hours)
- Governance Actions: 48 hours

## Integration Examples

### Depositing Dust
```solidity
// Approve token first
token.approve(bananaiTree, amount);

// Deposit dust
bananaiTree.depositDust([tokenAddress], [amount]);
```

### Batch Processing
```solidity
// Check if batch should be processed
(bool should, string memory reason) = batchProcessor.shouldProcessBatch(token);

// Process if conditions met
if (should) {
    batchProcessor.processBatch(token);
}
```

## Testing

```bash
# Install dependencies
yarn install

# Run tests
yarn test

# Run coverage
yarn coverage
```

## Auditing Checklist
- [ ] Access Control
- [ ] Reentrancy Protection
- [ ] Integer Overflow/Underflow
- [ ] Price Manipulation
- [ ] MEV Protection
- [ ] Emergency Procedures
- [ ] Gas Optimization

## License
MIT
