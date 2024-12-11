export const deploymentConfig = {
  base: {
    // Base Mainnet
    chainId: 8453,
    addresses: {
      paraswapRouter: "0x1111111254EEB25477B68fb85Ed929f73A960582",
      paraswapProxy: "0x216B4B4Ba9F3e719726886d34a177484278Bfcae",
      weth: "0x4200000000000000000000000000000000000006",
      uniswapV2Factory: "0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6"
    },
    parameters: {
      minimumLiquidity: "1000000000000000000", // 1 ETH
      batchThreshold: "5000000000000000000", // 5 ETH
      initialFee: 300, // 3%
      gasPrice: "1000000000" // 1 gwei
    }
  },
  baseGoerli: {
    // Base Testnet
    chainId: 84531,
    addresses: {
      // Testnet addresses...
    },
    parameters: {
      minimumLiquidity: "100000000000000000", // 0.1 ETH
      batchThreshold: "500000000000000000", // 0.5 ETH
      initialFee: 300,
      gasPrice: "1000000000"
    }
  }
};

export const roles = {
  MINTER_ROLE: "0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6",
  EXECUTOR_ROLE: "0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63",
  MANAGER_ROLE: "0x241ecf16d79d0f8dbfb92cbc07fe17840425976cf0667f022fe9877caa831b08",
  GUARDIAN_ROLE: "0x8f2457e6f6548ed534c7f5ae63d5f706e8a9f45a774bdd8bd072b8e7e6c0b0e2"
};

export const contractNames = {
  TOKEN: "BananAIToken",
  REGISTRY: "DustRegistry",
  METRICS: "MetricsLibrary",
  ROUTER: "SwapRouter",
  LIQUIDITY: "BananAILiquidity",
  BATCH: "BatchProcessor",
  RECOVERY: "EmergencyRecovery",
  TREE: "BananAITree"
};
