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

const EIP712_DOMAIN_TYPEHASH = ethers.keccak256(
  ethers.toUtf8Bytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
);

const CONSENT_TYPEHASH = ethers.keccak256(
  ethers.toUtf8Bytes(
    "Consent(address[] parties,bytes32[] scopes,uint256 validFrom,uint256 validUntil,string encryptedMetadataUri)"
  )
);

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

  async function getDomainSeparator(contract: ConsentRegistry): Promise<string> {
    return contract.getDomainSeparator();
  }

  async function signConsent(
    signer: SignerWithAddress,
    consent: {
      id: string;
      parties: string[];
      scopes: string[];
      validFrom: bigint;
      validUntil: bigint;
      revoked: boolean;
      encryptedMetadataUri: string;
      createdAt: bigint;
    },
    domainSeparator: string
  ): Promise<string> {
    const partiesHash = ethers.keccak256(
      ethers.solidityPacked(["address[]"], [consent.parties])
    );
    const scopesHash = ethers.keccak256(
      ethers.solidityPacked(["bytes32[]"], [consent.scopes])
    );
    const uriHash = ethers.keccak256(ethers.toUtf8Bytes(consent.encryptedMetadataUri));

    const structHash = ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ["bytes32", "bytes32", "bytes32", "uint256", "uint256", "bytes32"],
        [CONSENT_TYPEHASH, partiesHash, scopesHash, consent.validFrom, consent.validUntil, uriHash]
      )
    );

    const digest = ethers.keccak256(
      ethers.concat(["\x19\x01", domainSeparator, structHash])
    );

    const sig = await signer.signMessage(ethers.getBytes(digest));
    return ethers.Signature.from(sig).serialized;
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

      const consentStruct = {
        id: ethers.ZeroHash,
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        revoked: false,
        encryptedMetadataUri: TEST_URI,
        createdAt: 0n,
      };

      const domainSep = await getDomainSeparator(registry);

      const sigAlice = await signConsent(alice, consentStruct, domainSep);
      const sigBob = await signConsent(bob, consentStruct, domainSep);

      const tx = await registry.registerConsent(consentStruct, [sigAlice, sigBob]);
      const receipt = await tx.wait();

      const consentId = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["address[]", "bytes32[]", "uint256", "uint256", "string"],
          [consentStruct.parties, consentStruct.scopes, validFrom, validUntil, TEST_URI]
        )
      );

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

      const isProofUsed = await verifier.isProofUsed(
        ethers.keccak256(
          ethers.concat([
            ethers.solidityPacked(["bytes32"], [consentId]),
            ethers.toUtf8Bytes("age"),
            ethers.solidityPacked(["bytes"], [ageProof]),
            ethers.AbiCoder.defaultAbiCoder().encode(["uint256[]"], [publicInputs]),
          ])
        )
      );
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

      const consentStruct = {
        id: ethers.ZeroHash,
        parties,
        scopes: [SCOPE_INTIMACY, SCOPE_PHOTOS],
        validFrom,
        validUntil,
        revoked: false,
        encryptedMetadataUri: TEST_URI,
        createdAt: 0n,
      };

      const domainSep = await getDomainSeparator(registry);

      const sigs = await Promise.all([
        signConsent(alice, consentStruct, domainSep),
        signConsent(bob, consentStruct, domainSep),
        signConsent(charlie, consentStruct, domainSep),
      ]);

      const tx = await registry.registerConsent(consentStruct, sigs);
      await tx.wait();

      const consentId = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["address[]", "bytes32[]", "uint256", "uint256", "string"],
          [parties, consentStruct.scopes, validFrom, validUntil, TEST_URI]
        )
      );

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

      const consentStruct = {
        id: ethers.ZeroHash,
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        revoked: false,
        encryptedMetadataUri: TEST_URI,
        createdAt: 0n,
      };

      const domainSep = await getDomainSeparator(registry);

      const sigs = await Promise.all([
        signConsent(alice, consentStruct, domainSep),
        signConsent(bob, consentStruct, domainSep),
      ]);

      const consentId = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["address[]", "bytes32[]", "uint256", "uint256", "string"],
          [consentStruct.parties, consentStruct.scopes, validFrom, validUntil, TEST_URI]
        )
      );

      await expect(registry.registerConsent(consentStruct, sigs))
        .to.emit(registry, "ConsentRegistered")
        .withArgs(consentId, consentStruct.parties, validFrom, validUntil);
    });

    it("should emit ConsentRevoked event", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consentStruct = {
        id: ethers.ZeroHash,
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        revoked: false,
        encryptedMetadataUri: TEST_URI,
        createdAt: 0n,
      };

      const domainSep = await getDomainSeparator(registry);

      const sigs = await Promise.all([
        signConsent(alice, consentStruct, domainSep),
        signConsent(bob, consentStruct, domainSep),
      ]);

      const tx = await registry.registerConsent(consentStruct, sigs);
      const receipt = await tx.wait();

      const consentId = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["address[]", "bytes32[]", "uint256", "uint256", "string"],
          [consentStruct.parties, consentStruct.scopes, validFrom, validUntil, TEST_URI]
        )
      );

      await expect(registry.connect(alice).revokeConsent(consentId))
        .to.emit(registry, "ConsentRevoked")
        .withArgs(consentId, await alice.getAddress());
    });
  });

  describe("Error Cases", function () {
    it("should revert on duplicate registration", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consentStruct = {
        id: ethers.ZeroHash,
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        revoked: false,
        encryptedMetadataUri: TEST_URI,
        createdAt: 0n,
      };

      const domainSep = await getDomainSeparator(registry);

      const sigs = await Promise.all([
        signConsent(alice, consentStruct, domainSep),
        signConsent(bob, consentStruct, domainSep),
      ]);

      await registry.registerConsent(consentStruct, sigs);

      await expect(
        registry.registerConsent(consentStruct, sigs)
      ).to.be.revertedWith("ConsentRegistry: consent already exists");
    });

    it("should revert when non-party tries to revoke", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consentStruct = {
        id: ethers.ZeroHash,
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        revoked: false,
        encryptedMetadataUri: TEST_URI,
        createdAt: 0n,
      };

      const domainSep = await getDomainSeparator(registry);

      const sigs = await Promise.all([
        signConsent(alice, consentStruct, domainSep),
        signConsent(bob, consentStruct, domainSep),
      ]);

      const tx = await registry.registerConsent(consentStruct, sigs);
      const receipt = await tx.wait();

      const consentId = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["address[]", "bytes32[]", "uint256", "uint256", "string"],
          [consentStruct.parties, consentStruct.scopes, validFrom, validUntil, TEST_URI]
        )
      );

      await expect(
        registry.connect(charlie).revokeConsent(consentId)
      ).to.be.revertedWith("ConsentRegistry: not a party");
    });

    it("should revert on consent with no parties", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consentStruct = {
        id: ethers.ZeroHash,
        parties: [],
        scopes: [SCOPE_INTIMACY],
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
  });

  describe("Escrow Workflow", function () {
    it("should store and retrieve encrypted data", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consentStruct = {
        id: ethers.ZeroHash,
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        revoked: false,
        encryptedMetadataUri: TEST_URI,
        createdAt: 0n,
      };

      const domainSep = await getDomainSeparator(registry);

      const sigs = await Promise.all([
        signConsent(alice, consentStruct, domainSep),
        signConsent(bob, consentStruct, domainSep),
      ]);

      const tx = await registry.registerConsent(consentStruct, sigs);
      await tx.wait();

      const consentId = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["address[]", "bytes32[]", "uint256", "uint256", "string"],
          [consentStruct.parties, consentStruct.scopes, validFrom, validUntil, TEST_URI]
        )
      );

      await expect(
        escrow.connect(alice).storeEncryptedData(consentId, ENCRYPTED_DATA)
      ).to.emit(escrow, "EncryptionStored").withArgs(consentId, await alice.getAddress(), anyValue);

      const stored = await escrow.connect(alice).getEncryptedData(consentId);
      expect(stored).to.equal(ENCRYPTED_DATA);

      const bobData = await escrow.connect(bob).getEncryptedData(consentId);
      expect(bobData).to.equal(ENCRYPTED_DATA);
    });
  });

  describe("Batch Queries", function () {
    it("should verify multiple consent statuses in batch", async function () {
      const validFrom = BigInt(Math.floor(Date.now() / 1000));
      const validUntil = validFrom + 7n * 86400n;

      const consent1Struct = {
        id: ethers.ZeroHash,
        parties: [await alice.getAddress(), await bob.getAddress()],
        scopes: [SCOPE_INTIMACY],
        validFrom,
        validUntil,
        revoked: false,
        encryptedMetadataUri: "uri-1",
        createdAt: 0n,
      };

      const consent2Struct = {
        id: ethers.ZeroHash,
        parties: [await bob.getAddress(), await charlie.getAddress()],
        scopes: [SCOPE_PHOTOS],
        validFrom,
        validUntil,
        revoked: false,
        encryptedMetadataUri: "uri-2",
        createdAt: 0n,
      };

      const domainSep = await getDomainSeparator(registry);

      const sigs1 = await Promise.all([
        signConsent(alice, consent1Struct, domainSep),
        signConsent(bob, consent1Struct, domainSep),
      ]);

      const sigs2 = await Promise.all([
        signConsent(bob, consent2Struct, domainSep),
        signConsent(charlie, consent2Struct, domainSep),
      ]);

      await registry.registerConsent(consent1Struct, sigs1);
      await registry.registerConsent(consent2Struct, sigs2);

      const consentId1 = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["address[]", "bytes32[]", "uint256", "uint256", "string"],
          [consent1Struct.parties, consent1Struct.scopes, validFrom, validUntil, "uri-1"]
        )
      );

      const consentId2 = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["address[]", "bytes32[]", "uint256", "uint256", "string"],
          [consent2Struct.parties, consent2Struct.scopes, validFrom, validUntil, "uri-2"]
        )
      );

      const validities = await registry.areConsentsValid([consentId1, consentId2]);
      expect(validities[0]).to.be.true;
      expect(validities[1]).to.be.true;

      await registry.connect(alice).revokeConsent(consentId1);

      const validitiesAfter = await registry.areConsentsValid([consentId1, consentId2]);
      expect(validitiesAfter[0]).to.be.false;
      expect(validitiesAfter[1]).to.be.true;
    });
  });
});

const anyValue = 0n as unknown as bigint;
