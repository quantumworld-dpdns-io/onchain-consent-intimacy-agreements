import { ethers } from "hardhat";
import fs from "fs";
import path from "path";
import { deployAllContracts, writeDeployment } from "./utils";

interface ChainDeployment {
  network: string;
  chainId: number;
  deployer: string;
  blockNumber: number;
  timestamp: string;
  gasUsed: string;
  addresses: Record<string, string>;
}

const CHAINS = [
  { name: "sepolia", chainId: 11155111 },
  { name: "bsc_testnet", chainId: 97 },
  { name: "amoy", chainId: 80002 },
  { name: "palm_testnet", chainId: 11297108099 },
  { name: "base_sepolia", chainId: 84532 },
] as const;

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Multi-chain deployment");
  console.log("Deployer:", deployer.address);
  console.log("Networks:", CHAINS.map((c) => c.name).join(", "));
  console.log("");

  const summary: ChainDeployment[] = [];

  for (const chain of CHAINS) {
    console.log(`═══════════════════════════════════════════`);
    console.log(`  Deploying to ${chain.name} (chainId: ${chain.chainId})`);
    console.log(`═══════════════════════════════════════════`);

    try {
      // Switch network in hardhat
      await ethers.provider.send("hardhat_reset", [
        {
          forking: {
            jsonRpcUrl: getRpcUrl(chain.name),
          },
        },
      ]);

      const balance = await deployer.provider.getBalance(deployer.address);
      console.log(`  Balance: ${balance.toString()}`);

      if (balance === 0n) {
        console.log(`  ⚠️  Zero balance — skipping ${chain.name}`);
        continue;
      }

      const deployment = await deployAllContracts();
      writeDeployment(chain.name, deployment);

      const deploymentRecord: ChainDeployment = {
        network: chain.name,
        chainId: chain.chainId,
        deployer: deployer.address,
        blockNumber: 0,
        timestamp: new Date().toISOString(),
        gasUsed: "0",
        addresses: deployment,
      };

      summary.push(deploymentRecord);

      console.log(`  ✅ ${chain.name} deployment complete`);
    } catch (error: any) {
      console.error(`  ❌ ${chain.name} deployment failed:`, error.message);
    }

    console.log("");
  }

  // Write summary
  const summaryPath = path.join(__dirname, "..", "..", "deployments", "summary.json");
  const summaryDir = path.dirname(summaryPath);
  if (!fs.existsSync(summaryDir)) {
    fs.mkdirSync(summaryDir, { recursive: true });
  }
  fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2));
  console.log(`\nDeployment summary written to ${summaryPath}`);

  // Print summary table
  console.log("\n═══════════════════════════════════════════");
  console.log("  DEPLOYMENT SUMMARY");
  console.log("═══════════════════════════════════════════");
  for (const record of summary) {
    console.log(`\n${record.network} (chainId: ${record.chainId}):`);
    for (const [name, address] of Object.entries(record.addresses)) {
      console.log(`  ${name}: ${address}`);
    }
  }
}

function getRpcUrl(network: string): string {
  const key = `${network.toUpperCase().replace(/-/g, "_")}_RPC_URL`;
  const url = process.env[key];
  if (!url) throw new Error(`${key} not set in .env`);
  return url;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
