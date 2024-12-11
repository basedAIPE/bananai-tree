import { ethers, upgrades, network } from "hardhat";
import { Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

// Configuration for different networks
const config = {
  base: {
    paraswapRouter: "0x1111111254EEB25477B68fb85Ed929f73A960582",
    paraswapProxy: "0x216B4B4Ba9F3e719726886d34a177484278Bfcae",
    weth: "0x4200000000000000000000000000000000000006",
    uniswapV2Factory: "0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6",
    minimumLiquidity: ethers.utils.parseEther("1"),
    batchThreshold: ethers.utils.parseEther("5"),
    gasPrice: 1000000000, // 1 gwei
  }
};

interface DeployedContracts {
  bananaiToken: Contract;
  dustRegistry: Contract;
  metricsLibrary: Contract;
  swapRouter: Contract;
  bananaiLiquidity: Contract;
  batchProcessor: Contract;
  emergencyRecovery: Contract;
  bananaiTree: Contract;
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  const networkConfig = config[network.name];
  if (!networkConfig) {
    throw new Error(`No config for network ${network.name}`);
  }

  const deployed = await deployContracts(deployer, networkConfig);
  await configureContracts(deployed, deployer, networkConfig);
  await verifyContracts(deployed, networkConfig);
}

async function deployContracts(
  deployer: SignerWithAddress,
  config: any
): Promise<DeployedContracts> {
  console.log("Starting contract deployment...");

  // Deploy BananAIToken
  console.log("Deploying BananAIToken...");
  const BananAIToken = await ethers.getContractFactory("BananAIToken");
  const bananaiToken = await BananAIToken.deploy();
  await bananaiToken.deployed();
  console.log("BananAIToken deployed to:", bananaiToken.address);

  // Deploy DustRegistry
  console.log("Deploying DustRegistry...");
  const DustRegistry = await ethers.getContractFactory("DustRegistry");
  const dustRegistry = await DustRegistry.deploy(config.minimumLiquidity);
  await dustRegistry.deployed();
  console.log("DustRegistry deployed to:", dustRegistry.address);

  // Deploy MetricsLibrary
  console.log("Deploying MetricsLibrary...");
  const MetricsLibrary = await ethers.getContractFactory("MetricsLibrary");
  const metricsLibrary = await MetricsLibrary.deploy();
  await metricsLibrary.deployed();
  console.log("MetricsLibrary deployed to:", metricsLibrary.address);

  // Deploy SwapRouter
  console.log("Deploying SwapRouter...");
  const SwapRouter = await ethers.getContractFactory("SwapRouter");
  const swapRouter = await SwapRouter.deploy(
    config.paraswapRouter,
    config.paraswapProxy
  );
  await swapRouter.deployed();
  console.log("SwapRouter deployed to:", swapRouter.address);

  // Deploy BananAILiquidity
  console.log("Deploying BananAILiquidity...");
  const BananAILiquidity = await ethers.getContractFactory("BananAILiquidity");
  const bananaiLiquidity = await BananAILiquidity.deploy(
    config.uniswapV2Factory,
    bananaiToken.address,
    config.weth,
    deployer.address, // Initial fee collector
    300 // 3% initial fee
  );
  await bananaiLiquidity.deployed();
  console.log("BananAILiquidity deployed to:", bananaiLiquidity.address);

  // Deploy BatchProcessor
  console.log("Deploying BatchProcessor...");
  const BatchProcessor = await ethers.getContractFactory("BatchProcessor");
  const batchProcessor = await BatchProcessor.deploy();
  await batchProcessor.deployed();
  console.log("BatchProcessor deployed to:", batchProcessor.address);

  // Deploy EmergencyRecovery
  console.log("Deploying EmergencyRecovery...");
  const EmergencyRecovery = await ethers.getContractFactory("EmergencyRecovery");
  const emergencyRecovery = await EmergencyRecovery.deploy();
  await emergencyRecovery.deployed();
  console.log("EmergencyRecovery deployed to:", emergencyRecovery.address);

  // Deploy BananAITree
  console.log("Deploying BananAITree...");
  const BananAITree = await ethers.getContractFactory("BananAITree");
  const bananaiTree = await BananAITree.deploy(
    dustRegistry.address,
    metricsLibrary.address,
    swapRouter.address,
    bananaiLiquidity.address,
    bananaiToken.address,
    config.weth,
    config.batchThreshold
  );
  await bananaiTree.deployed();
  console.log("BananAITree deployed to:", bananaiTree.address);

  return {
    bananaiToken,
    dustRegistry,
    metricsLibrary,
    swapRouter,
    bananaiLiquidity,
    batchProcessor,
    emergencyRecovery,
    bananaiTree
  };
}

async function configureContracts(
  contracts: DeployedContracts,
  deployer: SignerWithAddress,
  config: any
) {
  console.log("Configuring contracts...");

  // Grant roles
  const MINTER_ROLE = await contracts.bananaiToken.MINTER_ROLE();
  await contracts.bananaiToken.grantRole(MINTER_ROLE, contracts.bananaiTree.address);

  const UPDATER_ROLE = await contracts.metricsLibrary.UPDATER_ROLE();
  await contracts.metricsLibrary.grantRole(UPDATER_ROLE, contracts.bananaiTree.address);

  const EXECUTOR_ROLE = await contracts.swapRouter.EXECUTOR_ROLE();
  await contracts.swapRouter.grantRole(EXECUTOR_ROLE, contracts.bananaiTree.address);

  const MANAGER_ROLE = await contracts.bananaiLiquidity.MANAGER_ROLE();
  await contracts.bananaiLiquidity.grantRole(MANAGER_ROLE, contracts.bananaiTree.address);

  // Configure batch processor
  await contracts.batchProcessor.configureBatch(
    contracts.bananaiToken.address,
    {
      minSize: ethers.utils.parseEther("1"),
      maxSize: ethers.utils.parseEther("100"),
      minParticipants: 3,
      maxTimeDelay: 3600, // 1 hour
      gasThreshold: ethers.utils.parseUnits("2", "gwei"),
      targetGasPrice: ethers.utils.parseUnits("1", "gwei"),
      active: true
    }
  );

  console.log("Contract configuration completed");
}

async function verifyContracts(
  contracts: DeployedContracts,
  config: any
) {
  if (network.name === "hardhat") return;

  console.log("Verifying contracts...");

  try {
    await hre.run("verify:verify", {
      address: contracts.bananaiToken.address,
      constructorArguments: []
    });

    await hre.run("verify:verify", {
      address: contracts.dustRegistry.address,
      constructorArguments: [config.minimumLiquidity]
    });

    // Verify remaining contracts...

    console.log("Contract verification completed");
  } catch (error) {
    console.error("Error during contract verification:", error);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
