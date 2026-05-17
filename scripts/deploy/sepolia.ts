import hre from "hardhat";
import { ethers } from "hardhat";
import { deployAllContracts, writeDeployment } from "./utils";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying to Sepolia with account:", deployer.address);
  console.log("Balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const deployment = await deployAllContracts();

  writeDeployment("sepolia", deployment);

  console.log("\nSepolia deployment complete!");
  console.log("Addresses:", deployment);

  // Verify on Etherscan
  if (process.env.ETHERSCAN_API_KEY) {
    console.log("\nVerifying contracts on Etherscan...");
    for (const [name, address] of Object.entries(deployment)) {
      try {
        await hre.run("verify:verify", {
          address,
          constructorArguments: [],
          network: "sepolia",
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
