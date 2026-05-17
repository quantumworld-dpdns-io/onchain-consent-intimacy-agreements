import { ethers } from "hardhat";
import fs from "fs";
import path from "path";

export interface DeploymentAddresses {
  ConsentRegistry: string;
  ConsentEscrow: string;
  ConsentToken: string;
  ConsentVerifier: string;
  ConsentFactory: string;
  [key: string]: string;
}

const CONTRACT_NAMES = [
  "ConsentRegistry",
  "ConsentEscrow",
  "ConsentToken",
  "ConsentVerifier",
  "ConsentFactory",
] as const;

export async function deployAllContracts(): Promise<DeploymentAddresses> {
  const deployment: Partial<DeploymentAddresses> = {};

  for (const name of CONTRACT_NAMES) {
    console.log(`\nDeploying ${name}...`);
    const Contract = await ethers.getContractFactory(name);
    const contract = await Contract.deploy();
    await contract.waitForDeployment();
    const address = await contract.getAddress();
    deployment[name] = address;
    console.log(`  ${name} deployed at: ${address}`);
  }

  // Wire contracts together
  await wireContracts(deployment as DeploymentAddresses);

  return deployment as DeploymentAddresses;
}

async function wireContracts(deployment: DeploymentAddresses): Promise<void> {
  console.log("\nWiring contracts together...");

  const registry = await ethers.getContractAt("ConsentRegistry", deployment.ConsentRegistry);
  const escrow = await ethers.getContractAt("ConsentEscrow", deployment.ConsentEscrow);
  const token = await ethers.getContractAt("ConsentToken", deployment.ConsentToken);
  const verifier = await ethers.getContractAt("ConsentVerifier", deployment.ConsentVerifier);
  const factory = await ethers.getContractAt("ConsentFactory", deployment.ConsentFactory);

  // Set verifier on registry
  const registryRole = await registry.VERIFIER_ROLE();
  await registry.grantRole(registryRole, deployment.ConsentVerifier);
  console.log("  Granted VERIFIER_ROLE to ConsentVerifier");

  // Set minter role on token for escrow and registry
  const minterRole = await token.MINTER_ROLE();
  await token.grantRole(minterRole, deployment.ConsentEscrow);
  await token.grantRole(minterRole, deployment.ConsentRegistry);
  console.log("  Granted MINTER_ROLE to ConsentEscrow and ConsentRegistry");

  // Set factory on registry
  await registry.setFactory(deployment.ConsentFactory);
  console.log("  Set ConsentFactory on ConsentRegistry");

  // Set escrow on registry
  await registry.setEscrow(deployment.ConsentEscrow);
  console.log("  Set ConsentEscrow on ConsentRegistry");

  // Initialize factory with registry
  await factory.initialize(deployment.ConsentRegistry);
  console.log("  Initialized ConsentFactory with ConsentRegistry");
}

export function writeDeployment(network: string, addresses: DeploymentAddresses): void {
  const deployDir = path.join(__dirname, "..", "..", "deployments");
  if (!fs.existsSync(deployDir)) {
    fs.mkdirSync(deployDir, { recursive: true });
  }

  const timestamp = new Date().toISOString();
  const artifact = {
    network,
    chainId: 0, // will be filled by each script
    timestamp,
    deployer: "", // will be filled by each script
    addresses,
    transactionHash: "",
  };

  const filePath = path.join(deployDir, `${network}.json`);
  fs.writeFileSync(filePath, JSON.stringify(artifact, null, 2));
  console.log(`\nDeployment artifact written to ${filePath}`);
}
