import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import {
  ConsentRegistry,
  ConsentToken,
  ConsentVerifier,
  ConsentEscrow,
  ConsentFactory,
  MockVerifier,
} from "../../../typechain-types";

describe("Deployment Verification", function () {
  let deployer: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;

  let registry: ConsentRegistry;
  let token: ConsentToken;
  let verifier: ConsentVerifier;
  let escrow: ConsentEscrow;
  let factory: ConsentFactory;
  let mockVerifier: MockVerifier;

  beforeEach(async function () {
    [deployer, alice, bob] = await ethers.getSigners();
  });

  describe("Contract Deployment", function () {
    it("should deploy ConsentRegistry with correct initial state", async function () {
      const RegistryFactory = await ethers.getContractFactory("ConsentRegistry");
      registry = await RegistryFactory.deploy();
      await registry.waitForDeployment();

      const registryAddress = await registry.getAddress();
      expect(registryAddress).to.properAddress;
      expect(registryAddress).to.not.equal(ethers.ZeroAddress);

      const count = await registry.getConsentCount();
      expect(count).to.equal(0n);

      const domainSep = await registry.getDomainSeparator();
      expect(domainSep).to.not.equal(ethers.ZeroHash);
    });

    it("should deploy ConsentToken with correct initial state", async function () {
      const TokenFactory = await ethers.getContractFactory("ConsentToken");
      token = await TokenFactory.deploy();
      await token.waitForDeployment();

      const tokenAddress = await token.getAddress();
      expect(tokenAddress).to.properAddress;

      expect(await token.name()).to.equal("ConsentReceiptToken");
      expect(await token.symbol()).to.equal("CRT");
      expect(await token.getNextTokenId()).to.equal(1n);
      expect(await token.getTotalMinted()).to.equal(0n);
    });

    it("should deploy ConsentVerifier with correct registry reference", async function () {
      const RegistryFactory = await ethers.getContractFactory("ConsentRegistry");
      registry = await RegistryFactory.deploy();
      await registry.waitForDeployment();

      const VerifierFactory = await ethers.getContractFactory("ConsentVerifier");
      verifier = await VerifierFactory.deploy(await registry.getAddress());
      await verifier.waitForDeployment();

      const verifierAddress = await verifier.getAddress();
      expect(verifierAddress).to.properAddress;

      const storedRegistry = await verifier.consentRegistry();
      expect(storedRegistry).to.equal(await registry.getAddress());
    });

    it("should deploy ConsentEscrow with correct registry reference", async function () {
      const RegistryFactory = await ethers.getContractFactory("ConsentRegistry");
      registry = await RegistryFactory.deploy();
      await registry.waitForDeployment();

      const EscrowFactory = await ethers.getContractFactory("ConsentEscrow");
      escrow = await EscrowFactory.deploy(await registry.getAddress());
      await escrow.waitForDeployment();

      const escrowAddress = await escrow.getAddress();
      expect(escrowAddress).to.properAddress;

      const storedRegistry = await escrow.consentRegistry();
      expect(storedRegistry).to.equal(await registry.getAddress());
    });

    it("should deploy MockVerifier with correct initial state", async function () {
      const MockFactory = await ethers.getContractFactory("MockVerifier");
      mockVerifier = await MockFactory.deploy();
      await mockVerifier.waitForDeployment();

      const mockAddress = await mockVerifier.getAddress();
      expect(mockAddress).to.properAddress;

      const isUsed = await mockVerifier.isProofUsed(ethers.ZeroHash);
      expect(isUsed).to.be.false;
    });
  });

  describe("Factory creates child contracts", function () {
    it("should deploy ConsentFactory with correct implementation reference", async function () {
      const RegistryFactory = await ethers.getContractFactory("ConsentRegistry");
      registry = await RegistryFactory.deploy();
      await registry.waitForDeployment();

      const FactoryFactory = await ethers.getContractFactory("ConsentFactory");
      factory = await FactoryFactory.deploy(await registry.getAddress());
      await factory.waitForDeployment();

      const factoryAddress = await factory.getAddress();
      expect(factoryAddress).to.properAddress;

      const defaultImpl = await factory.defaultImplementation();
      expect(defaultImpl).to.equal(await registry.getAddress());
    });

    it("should deploy child contracts via factory", async function () {
      const RegistryFactory = await ethers.getContractFactory("ConsentRegistry");
      registry = await RegistryFactory.deploy();
      await registry.waitForDeployment();

      const FactoryFactory = await ethers.getContractFactory("ConsentFactory");
      factory = await FactoryFactory.deploy(await registry.getAddress());
      await factory.waitForDeployment();

      const salt = ethers.keccak256(ethers.toUtf8Bytes("deployment-1"));
      const initializer = "0x";

      const tx = await factory.deployConsentContract(salt, initializer);
      const receipt = await tx.wait();

      const deployedAddress = await factory.getDeployedAddress(salt);
      expect(deployedAddress).to.not.equal(ethers.ZeroAddress);
      expect(await factory.isDeployedFromFactory(deployedAddress)).to.be.true;
      expect(await factory.isSaltUsed(salt)).to.be.true;
      expect(await factory.getDeploymentCount()).to.equal(1n);

      const predicted = await factory.predictDeploymentAddress(salt);
      expect(predicted).to.equal(deployedAddress);

      const deployedList = await factory.getDeployedConsents();
      expect(deployedList).to.have.lengthOf(1);
      expect(deployedList[0]).to.equal(deployedAddress);
    });

    it("should revert on duplicate salt usage", async function () {
      const RegistryFactory = await ethers.getContractFactory("ConsentRegistry");
      registry = await RegistryFactory.deploy();
      await registry.waitForDeployment();

      const FactoryFactory = await ethers.getContractFactory("ConsentFactory");
      factory = await FactoryFactory.deploy(await registry.getAddress());
      await factory.waitForDeployment();

      const salt = ethers.keccak256(ethers.toUtf8Bytes("unique-salt"));

      await factory.deployConsentContract(salt, "0x");

      await expect(
        factory.deployConsentContract(salt, "0x")
      ).to.be.revertedWith("ConsentFactory: salt already used");
    });

    it("should deploy multiple children with different salts", async function () {
      const RegistryFactory = await ethers.getContractFactory("ConsentRegistry");
      registry = await RegistryFactory.deploy();
      await registry.waitForDeployment();

      const FactoryFactory = await ethers.getContractFactory("ConsentFactory");
      factory = await FactoryFactory.deploy(await registry.getAddress());
      await factory.waitForDeployment();

      const salt1 = ethers.keccak256(ethers.toUtf8Bytes("child-1"));
      const salt2 = ethers.keccak256(ethers.toUtf8Bytes("child-2"));
      const salt3 = ethers.keccak256(ethers.toUtf8Bytes("child-3"));

      await factory.deployConsentContract(salt1, "0x");
      await factory.deployConsentContract(salt2, "0x");
      await factory.deployConsentContract(salt3, "0x");

      expect(await factory.getDeploymentCount()).to.equal(3n);

      const allDeployed = await factory.getDeployedConsents();
      expect(allDeployed).to.have.lengthOf(3);

      const addr1 = await factory.getDeployedAddress(salt1);
      const addr2 = await factory.getDeployedAddress(salt2);
      const addr3 = await factory.getDeployedAddress(salt3);

      expect(addr1).to.not.equal(addr2);
      expect(addr2).to.not.equal(addr3);
      expect(addr1).to.not.equal(addr3);
    });
  });

  describe("Cross-Contract Permissions", function () {
    it("should verify consent status from Verifier points to correct Registry", async function () {
      const RegistryFactory = await ethers.getContractFactory("ConsentRegistry");
      registry = await RegistryFactory.deploy();
      await registry.waitForDeployment();

      const VerifierFactory = await ethers.getContractFactory("ConsentVerifier");
      verifier = await VerifierFactory.deploy(await registry.getAddress());
      await verifier.waitForDeployment();

      const EscrowFactory = await ethers.getContractFactory("ConsentEscrow");
      escrow = await EscrowFactory.deploy(await registry.getAddress());
      await escrow.waitForDeployment();

      expect(await verifier.consentRegistry()).to.equal(await escrow.consentRegistry());
      expect(await verifier.consentRegistry()).to.equal(await registry.getAddress());
    });

    it("should enforce party-only access across contracts", async function () {
      const RegistryFactory = await ethers.getContractFactory("ConsentRegistry");
      registry = await RegistryFactory.deploy();
      await registry.waitForDeployment();

      const EscrowFactory = await ethers.getContractFactory("ConsentEscrow");
      escrow = await EscrowFactory.deploy(await registry.getAddress());
      await escrow.waitForDeployment();

      const SCOPE = ethers.keccak256(ethers.toUtf8Bytes("test"));
      const TEST_URI = "ipfs://test";
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const typedDataDomain = {
        name: "ConsentRegistry",
        version: "1",
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: await registry.getAddress(),
      };

      const typedDataTypes = {
        Consent: [
          { name: "parties", type: "address[]" },
          { name: "scopes", type: "bytes32[]" },
          { name: "validFrom", type: "uint256" },
          { name: "validUntil", type: "uint256" },
          { name: "encryptedMetadataUri", type: "string" },
        ],
      };

      const consentValue = {
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE],
        validFrom,
        validUntil,
        encryptedMetadataUri: TEST_URI,
      };

      const sigAlice = await alice.signTypedData(typedDataDomain, typedDataTypes, consentValue);
      const sigBob = await bob.signTypedData(typedDataDomain, typedDataTypes, consentValue);

      const consentStruct = {
        id: ethers.ZeroHash,
        parties: consentValue.parties,
        scopes: consentValue.scopes,
        validFrom: validFrom,
        validUntil: validUntil,
        revoked: false,
        encryptedMetadataUri: TEST_URI,
        createdAt: 0n,
      };

      const registerTx = await registry.registerConsent(consentStruct, [sigAlice, sigBob]);
      await registerTx.wait();

      const consentId = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["address[]", "bytes32[]", "uint256", "uint256", "string"],
          [consentValue.parties, consentValue.scopes, validFrom, validUntil, TEST_URI]
        )
      );

      const encryptedData = ethers.hexlify(ethers.toUtf8Bytes("secret"));

      await expect(
        escrow.connect(alice).storeEncryptedData(consentId, encryptedData)
      ).to.emit(escrow, "EncryptionStored");

      const data = await escrow.connect(alice).getEncryptedData(consentId);
      expect(data).to.equal(encryptedData);

      await expect(
        escrow.connect(deployer).getEncryptedData(consentId)
      ).to.be.revertedWith("ConsentEscrow: not a consent party");

      const isValid = await registry.isConsentValid(consentId);
      expect(isValid).to.be.true;

      await registry.connect(alice).revokeConsent(consentId);

      const isValidAfter = await registry.isConsentValid(consentId);
      expect(isValidAfter).to.be.false;
    });
  });

  describe("Constructor Validation", function () {
    it("should revert ConsentVerifier with zero registry address", async function () {
      const VerifierFactory = await ethers.getContractFactory("ConsentVerifier");
      await expect(
        VerifierFactory.deploy(ethers.ZeroAddress)
      ).to.be.revertedWith("ConsentVerifier: invalid registry address");
    });

    it("should revert ConsentEscrow with zero registry address", async function () {
      const EscrowFactory = await ethers.getContractFactory("ConsentEscrow");
      await expect(
        EscrowFactory.deploy(ethers.ZeroAddress)
      ).to.be.revertedWith("ConsentEscrow: invalid registry address");
    });

    it("should revert ConsentFactory with zero implementation address", async function () {
      const FactoryFactory = await ethers.getContractFactory("ConsentFactory");
      await expect(
        FactoryFactory.deploy(ethers.ZeroAddress)
      ).to.be.revertedWith("ConsentFactory: invalid implementation");
    });
  });

  describe("ConsentRegistry Self-Consistency", function () {
    it("should maintain correct consent count", async function () {
      const RegistryFactory = await ethers.getContractFactory("ConsentRegistry");
      registry = await RegistryFactory.deploy();
      await registry.waitForDeployment();

      expect(await registry.getConsentCount()).to.equal(0n);

      const SCOPE = ethers.keccak256(ethers.toUtf8Bytes("test"));
      const TEST_URI = "ipfs://test";
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const typedDataDomain = {
        name: "ConsentRegistry",
        version: "1",
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: await registry.getAddress(),
      };

      const typedDataTypes = {
        Consent: [
          { name: "parties", type: "address[]" },
          { name: "scopes", type: "bytes32[]" },
          { name: "validFrom", type: "uint256" },
          { name: "validUntil", type: "uint256" },
          { name: "encryptedMetadataUri", type: "string" },
        ],
      };

      const consentValue = {
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE],
        validFrom,
        validUntil,
        encryptedMetadataUri: TEST_URI,
      };

      const sigAlice = await alice.signTypedData(typedDataDomain, typedDataTypes, consentValue);
      const sigBob = await bob.signTypedData(typedDataDomain, typedDataTypes, consentValue);

      const consentStruct = {
        id: ethers.ZeroHash,
        parties: consentValue.parties,
        scopes: consentValue.scopes,
        validFrom: validFrom,
        validUntil: validUntil,
        revoked: false,
        encryptedMetadataUri: TEST_URI,
        createdAt: 0n,
      };

      await registry.registerConsent(consentStruct, [sigAlice, sigBob]);
      expect(await registry.getConsentCount()).to.equal(1n);

      const consentValue2 = {
        parties: [await bob.getAddress(), await alice.getAddress()],
        scopes: [SCOPE],
        validFrom,
        validUntil: validFrom + 30n * 86400n,
        encryptedMetadataUri: "ipfs://test-2",
      };

      const sigAlice2 = await alice.signTypedData(typedDataDomain, typedDataTypes, consentValue2);
      const sigBob2 = await bob.signTypedData(typedDataDomain, typedDataTypes, consentValue2);

      const consentStruct2 = {
        id: ethers.ZeroHash,
        parties: consentValue2.parties,
        scopes: consentValue2.scopes,
        validFrom: validFrom,
        validUntil: validFrom + 30n * 86400n,
        revoked: false,
        encryptedMetadataUri: "ipfs://test-2",
        createdAt: 0n,
      };

      await registry.registerConsent(consentStruct2, [sigAlice2, sigBob2]);
      expect(await registry.getConsentCount()).to.equal(2n);
    });
  });
});
