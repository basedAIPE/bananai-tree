import { deploymentConfig, contractNames } from "./config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

async function verifyContract(
  hre: HardhatRuntimeEnvironment,
  address: string,
  constructorArguments: any[]
) {
  try {
    await hre.run("verify:verify", {
      address,
      constructorArguments
    });
    console.log(`Verified contract at ${address}`);
  } catch (error) {
    console.error(`Error verifying contract at ${address}:`, error);
  }
}

async function main() {
  const deployedAddresses = require("../deployments/deployed.json");
  const network = hre.network.name;
  const config = deploymentConfig[network];

  if (!config) {
    throw new Error(`No config found for network ${network}`);
  }

  console.log(`Verifying contracts on ${network}...`);

  // Verify each contract
  await verifyContract(hre, deployedAddresses.bananaiToken, []);
  
  await verifyContract(hre, deployedAddresses.dustRegistry, [
    config.parameters.minimumLiquidity
  ]);

  await verifyContract(hre, deployedAddresses.swapRouter, [
    config.addresses.paraswapRouter,
    config.addresses.paraswapProxy
  ]);

  // ... verify remaining contracts

  console.log("Verification complete");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
