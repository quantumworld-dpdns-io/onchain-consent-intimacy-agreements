import hre from "hardhat";
import { ethers } from "hardhat";
import { deployAllContracts, writeDeployment } from "./utils";

async function main() {
  const [deployer] = await ethers.getSigners();
  const networkName = "palm_testnet";
  console.log(`Deploying to Palm Testnet with account: ${deployer.address}`);
  console.log("Balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const deployment = await deployAllContracts();
  writeDeployment(networkName, deployment);

  console.log("\nPalm Testnet deployment complete!");
  console.log("Addresses:", deployment);

  if (process.env.PALMSCAN_API_KEY) {
    console.log("\nVerifying contracts on PalmScan...");
    for (const [name, address] of Object.entries(deployment)) {
      try {
        await hre.run("verify:verify", {
          address,
          constructorArguments: [],
          network: networkName,
        });
        console.log(`  ${name} verified at ${address}`);
      } catch (err: any) {
        if (err.message?.includes("Already Verified")) {
          console.log(`  ${name} already verified`);
        } else {
          console.error(`  ${name} verification failed:`, err.message);
        }
      }
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
