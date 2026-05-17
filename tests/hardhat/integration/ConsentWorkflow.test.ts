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

describe("ConsentWorkflow Integration", function () {
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let charlie: SignerWithAddress;

  let registry: ConsentRegistry;
  let token: ConsentToken;
  let verifier: ConsentVerifier;
  let escrow: ConsentEscrow;
  let factory: ConsentFactory;
  let mockVerifier: MockVerifier;

  const SCOPE_INTIMACY = ethers.keccak256(ethers.toUtf8Bytes("intimacy"));
  const SCOPE_PHOTOS = ethers.keccak256(ethers.toUtf8Bytes("photographs"));
  const TEST_URI = "https://consent.protocol/metadata/1";
  const ENCRYPTED_DATA = ethers.hexlify(ethers.toUtf8Bytes("encrypted-content"));

  function buildTypedDataDomain(
    registryAddress: string,
    chainId: bigint
  ): Record<string, unknown> {
    return {
      name: "ConsentRegistry",
      version: "1",
      chainId,
      verifyingContract: registryAddress,
    };
  }

  const TYPED_DATA_TYPES = {
    Consent: [
      { name: "parties", type: "address[]" },
      { name: "scopes", type: "bytes32[]" },
      { name: "validFrom", type: "uint256" },
      { name: "validUntil", type: "uint256" },
      { name: "encryptedMetadataUri", type: "string" },
    ],
  };

  interface ConsentValue {
    parties: string[];
    scopes: string[];
    validFrom: bigint;
    validUntil: bigint;
    encryptedMetadataUri: string;
  }

  function consentToTypedValue(consent: {
    parties: string[];
    scopes: string[];
    validFrom: bigint;
    validUntil: bigint;
    encryptedMetadataUri: string;
  }): ConsentValue {
    return {
      parties: consent.parties,
      scopes: consent.scopes,
      validFrom: consent.validFrom,
      validUntil: consent.validUntil,
      encryptedMetadataUri: consent.encryptedMetadataUri,
    };
  }

  async function signConsent(
    signer: SignerWithAddress,
    consentValue: ConsentValue,
    domain: Record<string, unknown>
  ): Promise<string> {
    return signer.signTypedData(domain, TYPED_DATA_TYPES, consentValue);
  }

  function computeConsentId(consent: {
    parties: string[];
    scopes: string[];
    validFrom: bigint;
    validUntil: bigint;
    encryptedMetadataUri: string;
  }): string {
    return ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ["address[]", "bytes32[]", "uint256", "uint256", "string"],
        [consent.parties, consent.scopes, consent.validFrom, consent.validUntil, consent.encryptedMetadataUri]
      )
    );
  }

  interface ConsentStruct {
    id: string;
    parties: string[];
    scopes: string[];
    validFrom: bigint;
    validUntil: bigint;
    revoked: boolean;
    encryptedMetadataUri: string;
    createdAt: bigint;
  }

  function buildConsentStruct(value: ConsentValue): ConsentStruct {
    return {
      id: ethers.ZeroHash,
      parties: value.parties,
      scopes: value.scopes,
      validFrom: value.validFrom,
      validUntil: value.validUntil,
      revoked: false,
      encryptedMetadataUri: value.encryptedMetadataUri,
      createdAt: 0n,
    };
  }

  beforeEach(async function () {
    [alice, bob, charlie] = await ethers.getSigners();

    const RegistryFactory = await ethers.getContractFactory("ConsentRegistry");
    registry = await RegistryFactory.deploy();
    await registry.waitForDeployment();

    const TokenFactory = await ethers.getContractFactory("ConsentToken");
    token = await TokenFactory.deploy();
    await token.waitForDeployment();

    const VerifierFactory = await ethers.getContractFactory("ConsentVerifier");
    verifier = await VerifierFactory.deploy(await registry.getAddress());
    await verifier.waitForDeployment();

    const EscrowFactory = await ethers.getContractFactory("ConsentEscrow");
    escrow = await EscrowFactory.deploy(await registry.getAddress());
    await escrow.waitForDeployment();

    const FactoryFactory = await ethers.getContractFactory("ConsentFactory");
    factory = await FactoryFactory.deploy(await registry.getAddress());
    await factory.waitForDeployment();

    const MockFactory = await ethers.getContractFactory("MockVerifier");
    mockVerifier = await MockFactory.deploy();
    await mockVerifier.waitForDeployment();
  });

  describe("Full Lifecycle: Register -> Mint -> Verify -> Revoke", function () {
    it("should complete the full consent lifecycle", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consentValue: ConsentValue = {
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        encryptedMetadataUri: TEST_URI,
      };

      const domain = buildTypedDataDomain(
        await registry.getAddress(),
        (await ethers.provider.getNetwork()).chainId
      );

      const sigAlice = await signConsent(alice, consentValue, domain);
      const sigBob = await signConsent(bob, consentValue, domain);

      const consentStruct = buildConsentStruct(consentValue);

      const tx = await registry.registerConsent(consentStruct, [sigAlice, sigBob]);
      await tx.wait();

      const consentId = computeConsentId(consentValue);

      const stored = await registry.getConsent(consentId);
      expect(stored.parties).to.have.lengthOf(2);
      expect(stored.parties[0]).to.equal(await alice.getAddress());
      expect(stored.revoked).to.be.false;

      const isValidBefore = await registry.isConsentValid(consentId);
      expect(isValidBefore).to.be.true;

      const mintTx = await token.mintConsentReceipt(
        consentStruct.parties,
        consentId,
        TEST_URI
      );
      await mintTx.wait();

      const tokenId = await token.getConsentTokenId(consentId);
      expect(tokenId).to.equal(1n);

      const aliceBalance = await token.balanceOfParty(consentId, await alice.getAddress());
      expect(aliceBalance).to.equal(1n);

      const ageProof = ethers.hexlify(ethers.toUtf8Bytes("age-proof-data"));
      const publicInputs = [validUntil];

      const verifyTx = await verifier.verifyConsentAgeProof(consentId, ageProof, publicInputs);
      await verifyTx.wait();

      const proofHash = ethers.keccak256(
        ethers.solidityPacked(
          ["bytes32", "string", "bytes", "uint256[]"],
          [consentId, "age", ageProof, publicInputs]
        )
      );

      const isProofUsed = await verifier.isProofUsed(proofHash);
      expect(isProofUsed).to.be.true;

      const revokeTx = await registry.connect(alice).revokeConsent(consentId);
      await revokeTx.wait();

      const storedAfter = await registry.getConsent(consentId);
      expect(storedAfter.revoked).to.be.true;

      const isValidAfter = await registry.isConsentValid(consentId);
      expect(isValidAfter).to.be.false;
    });
  });

  describe("Multi-Party Registration", function () {
    it("should register a consent with three parties", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 30n * 86400n;

      const parties = [
        await alice.getAddress(),
        await bob.getAddress(),
        await charlie.getAddress(),
      ];

      const consentValue: ConsentValue = {
        parties,
        scopes: [SCOPE_INTIMACY, SCOPE_PHOTOS],
        validFrom,
        validUntil,
        encryptedMetadataUri: TEST_URI,
      };

      const domain = buildTypedDataDomain(
        await registry.getAddress(),
        (await ethers.provider.getNetwork()).chainId
      );

      const sigs = await Promise.all([
        signConsent(alice, consentValue, domain),
        signConsent(bob, consentValue, domain),
        signConsent(charlie, consentValue, domain),
      ]);

      const consentStruct = buildConsentStruct(consentValue);

      const tx = await registry.registerConsent(consentStruct, sigs);
      await tx.wait();

      const consentId = computeConsentId(consentValue);

      const stored = await registry.getConsent(consentId);
      expect(stored.parties).to.have.lengthOf(3);

      const partyConsents = await registry.getPartyConsents(await alice.getAddress());
      expect(partyConsents).to.include(consentId);
    });
  });

  describe("Event Emissions", function () {
    it("should emit ConsentRegistered event", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consentValue: ConsentValue = {
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        encryptedMetadataUri: TEST_URI,
      };

      const domain = buildTypedDataDomain(
        await registry.getAddress(),
        (await ethers.provider.getNetwork()).chainId
      );

      const sigs = await Promise.all([
        signConsent(alice, consentValue, domain),
        signConsent(bob, consentValue, domain),
      ]);

      const consentStruct = buildConsentStruct(consentValue);
      const consentId = computeConsentId(consentValue);

      await expect(registry.registerConsent(consentStruct, sigs))
        .to.emit(registry, "ConsentRegistered")
        .withArgs(consentId, consentStruct.parties, validFrom, validUntil);
    });

    it("should emit ConsentRevoked event", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consentValue: ConsentValue = {
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        encryptedMetadataUri: TEST_URI,
      };

      const domain = buildTypedDataDomain(
        await registry.getAddress(),
        (await ethers.provider.getNetwork()).chainId
      );

      const sigs = await Promise.all([
        signConsent(alice, consentValue, domain),
        signConsent(bob, consentValue, domain),
      ]);

      const consentStruct = buildConsentStruct(consentValue);

      await registry.registerConsent(consentStruct, sigs);
      const consentId = computeConsentId(consentValue);

      await expect(registry.connect(alice).revokeConsent(consentId))
        .to.emit(registry, "ConsentRevoked")
        .withArgs(consentId, await alice.getAddress());
    });

    it("should emit ConsentReceiptMinted event", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consentValue: ConsentValue = {
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        encryptedMetadataUri: TEST_URI,
      };

      const domain = buildTypedDataDomain(
        await registry.getAddress(),
        (await ethers.provider.getNetwork()).chainId
      );

      const sigs = await Promise.all([
        signConsent(alice, consentValue, domain),
        signConsent(bob, consentValue, domain),
      ]);

      const consentStruct = buildConsentStruct(consentValue);

      await registry.registerConsent(consentStruct, sigs);
      const consentId = computeConsentId(consentValue);

      await expect(
        token.mintConsentReceipt(consentStruct.parties, consentId, TEST_URI)
      )
        .to.emit(token, "ConsentReceiptMinted")
        .withArgs(consentId, consentStruct.parties, 1n);
    });
  });

  describe("Error Cases", function () {
    it("should revert on duplicate registration", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consentValue: ConsentValue = {
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        encryptedMetadataUri: TEST_URI,
      };

      const domain = buildTypedDataDomain(
        await registry.getAddress(),
        (await ethers.provider.getNetwork()).chainId
      );

      const sigs = await Promise.all([
        signConsent(alice, consentValue, domain),
        signConsent(bob, consentValue, domain),
      ]);

      const consentStruct = buildConsentStruct(consentValue);

      await registry.registerConsent(consentStruct, sigs);

      const sigs2 = await Promise.all([
        signConsent(alice, consentValue, domain),
        signConsent(bob, consentValue, domain),
      ]);

      await expect(
        registry.registerConsent(consentStruct, sigs2)
      ).to.be.revertedWith("ConsentRegistry: consent already exists");
    });

    it("should revert when non-party tries to revoke", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consentValue: ConsentValue = {
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        encryptedMetadataUri: TEST_URI,
      };

      const domain = buildTypedDataDomain(
        await registry.getAddress(),
        (await ethers.provider.getNetwork()).chainId
      );

      const sigs = await Promise.all([
        signConsent(alice, consentValue, domain),
        signConsent(bob, consentValue, domain),
      ]);

      const consentStruct = buildConsentStruct(consentValue);

      await registry.registerConsent(consentStruct, sigs);
      const consentId = computeConsentId(consentValue);

      await expect(
        registry.connect(charlie).revokeConsent(consentId)
      ).to.be.revertedWith("ConsentRegistry: not a party");
    });

    it("should revert on consent with no parties", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consentStruct = {
        id: ethers.ZeroHash,
        parties: [] as string[],
        scopes: [SCOPE_INTIMACY] as string[],
        validFrom,
        validUntil,
        revoked: false,
        encryptedMetadataUri: TEST_URI,
        createdAt: 0n,
      };

      await expect(
        registry.registerConsent(consentStruct, [])
      ).to.be.revertedWith("ConsentRegistry: no parties");
    });

    it("should revert on verifier proof replay", async function () {
      const proof = ethers.hexlify(ethers.toUtf8Bytes("some-proof"));
      const inputs = [42n];
      const consentId = ethers.ZeroHash;

      await verifier.verifyConsentAgeProof(consentId, proof, inputs);

      await expect(
        verifier.verifyConsentAgeProof(consentId, proof, inputs)
      ).to.be.revertedWithCustomError(verifier, "ProofAlreadyUsed");
    });

    it("should revert on empty proof in verifier", async function () {
      const emptyProof = "0x";
      const inputs = [42n];

      await expect(
        verifier.verifyConsentAgeProof(ethers.ZeroHash, emptyProof, inputs)
      ).to.be.revertedWithCustomError(verifier, "InvalidProof");
    });
  });

  describe("Escrow Workflow", function () {
    it("should store and retrieve encrypted data by parties", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consentValue: ConsentValue = {
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        encryptedMetadataUri: TEST_URI,
      };

      const domain = buildTypedDataDomain(
        await registry.getAddress(),
        (await ethers.provider.getNetwork()).chainId
      );

      const sigs = await Promise.all([
        signConsent(alice, consentValue, domain),
        signConsent(bob, consentValue, domain),
      ]);

      const consentStruct = buildConsentStruct(consentValue);

      await registry.registerConsent(consentStruct, sigs);
      const consentId = computeConsentId(consentValue);

      const storeTx = await escrow.connect(alice).storeEncryptedData(consentId, ENCRYPTED_DATA);
      await storeTx.wait();

      const stored = await escrow.connect(alice).getEncryptedData(consentId);
      expect(stored).to.equal(ENCRYPTED_DATA);

      const bobData = await escrow.connect(bob).getEncryptedData(consentId);
      expect(bobData).to.equal(ENCRYPTED_DATA);

      await expect(
        escrow.connect(charlie).getEncryptedData(consentId)
      ).to.be.revertedWith("ConsentEscrow: not a consent party");
    });
  });

  describe("Batch Queries", function () {
    it("should verify multiple consent statuses in batch", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consent1Value: ConsentValue = {
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        encryptedMetadataUri: "uri-1",
      };

      const consent2Value: ConsentValue = {
        parties: [await bob.getAddress(), await charlie.getAddress()],
        scopes: [SCOPE_PHOTOS],
        validFrom,
        validUntil,
        encryptedMetadataUri: "uri-2",
      };

      const domain = buildTypedDataDomain(
        await registry.getAddress(),
        (await ethers.provider.getNetwork()).chainId
      );

      const sigs1 = await Promise.all([
        signConsent(alice, consent1Value, domain),
        signConsent(bob, consent1Value, domain),
      ]);

      const sigs2 = await Promise.all([
        signConsent(bob, consent2Value, domain),
        signConsent(charlie, consent2Value, domain),
      ]);

      await registry.registerConsent(buildConsentStruct(consent1Value), sigs1);
      await registry.registerConsent(buildConsentStruct(consent2Value), sigs2);

      const consentId1 = computeConsentId(consent1Value);
      const consentId2 = computeConsentId(consent2Value);

      const validities = await registry.areConsentsValid([consentId1, consentId2]);
      expect(validities[0]).to.be.true;
      expect(validities[1]).to.be.true;

      await registry.connect(alice).revokeConsent(consentId1);

      const validitiesAfter = await registry.areConsentsValid([consentId1, consentId2]);
      expect(validitiesAfter[0]).to.be.false;
      expect(validitiesAfter[1]).to.be.true;
    });
  });

  describe("Token Transfer Restrictions", function () {
    it("should not allow transfers by default (ERC1155 allows them)", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consentValue: ConsentValue = {
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        encryptedMetadataUri: TEST_URI,
      };

      const domain = buildTypedDataDomain(
        await registry.getAddress(),
        (await ethers.provider.getNetwork()).chainId
      );

      const sigs = await Promise.all([
        signConsent(alice, consentValue, domain),
        signConsent(bob, consentValue, domain),
      ]);

      const consentStruct = buildConsentStruct(consentValue);

      await registry.registerConsent(consentStruct, sigs);
      const consentId = computeConsentId(consentValue);

      await token.mintConsentReceipt(consentStruct.parties, consentId, TEST_URI);
      const tokenId = await token.getConsentTokenId(consentId);

      await expect(
        token
          .connect(alice)
          ["safeTransferFrom(address,address,uint256,uint256,bytes)"](
            await alice.getAddress(),
            await charlie.getAddress(),
            tokenId,
            1n,
            "0x"
          )
      ).to.not.be.reverted;
    });
  });
});
