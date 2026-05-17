import hre from "hardhat";
import fs from "fs";
import path from "path";

interface DeploymentArtifact {
  network: string;
  chainId: number;
  timestamp: string;
  deployer: string;
  addresses: Record<string, string>;
  transactionHash: string;
}

const NETWORK_MAP: Record<string, string> = {
  sepolia: "sepolia",
  bsc_testnet: "bscTestnet",
  amoy: "amoy",
  palm_testnet: "palmTestnet",
  base_sepolia: "baseSepolia",
};

async function main() {
  const networkArg = process.argv[2];
  if (!networkArg) {
    console.error("Usage: npx hardhat run scripts/verify/all-contracts.ts --network <network>");
    process.exitCode = 1;
    return;
  }

  const network = NETWORK_MAP[networkArg];
  if (!network) {
    console.error(`Unknown network: ${networkArg}`);
    console.error(`Supported: ${Object.keys(NETWORK_MAP).join(", ")}`);
    process.exitCode = 1;
    return;
  }

  const deployDir = path.join(__dirname, "..", "..", "deployments");
  const artifactPath = path.join(deployDir, `${networkArg}.json`);

  if (!fs.existsSync(artifactPath)) {
    console.error(`Deployment artifact not found: ${artifactPath}`);
    console.error("Run a deployment script first.");
    process.exitCode = 1;
    return;
  }

  const artifact: DeploymentArtifact = JSON.parse(
    fs.readFileSync(artifactPath, "utf-8")
  );

  console.log(`Verifying contracts on ${networkArg}...`);
  console.log(`Network: ${network} (chainId: ${artifact.chainId})`);
  console.log(`Deployed at: ${artifact.timestamp}`);
  console.log("");

  for (const [name, address] of Object.entries(artifact.addresses)) {
    console.log(`Verifying ${name} at ${address}...`);

    try {
      await hre.run("verify:verify", {
        address,
        constructorArguments: [],
        network,
      });
      console.log(`  ✅ ${name} verified successfully`);
    } catch (error: any) {
      if (
        error.message?.includes("Already Verified") ||
        error.message?.includes("already verified")
      ) {
        console.log(`  ⏭️  ${name} already verified`);
      } else {
        console.error(`  ❌ ${name} verification failed:`, error.message);
      }
    }

    console.log("");
  }

  const verified = artifact.addresses.length;
  console.log(`Verification complete. Checked ${verified} contracts.`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
