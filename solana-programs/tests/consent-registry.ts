import * as anchor from "@coral-xyz/anchor";
import { Program, AnchorProvider, BN, web3 } from "@coral-xyz/anchor";
import { ConsentRegistry } from "../target/types/consent_registry";
import { expect, use } from "chai";
import * as chaiAsPromised from "chai-as-promised";

use(chaiAsPromised);

describe("consent-registry", () => {
  const provider = AnchorProvider.env();
  anchor.setProvider(provider);

  const program = anchor.workspace
    .ConsentRegistry as Program<ConsentRegistry>;
  const payer = provider.wallet.publicKey;

  let consentPda: web3.PublicKey;
  let consentBump: number;
  let nonce: BN;

  const party2 = web3.Keypair.generate();
  const party3 = web3.Keypair.generate();

  const scopes = ["intimacy", "data-sharing"];
  const validFrom = new BN(Math.floor(Date.now() / 1000) - 3600);
  const validUntil = new BN(Math.floor(Date.now() / 1000) + 86400 * 30);

  it("registers a new consent agreement", async () => {
    nonce = new BN(Date.now());

    const [pda, bump] = web3.PublicKey.findProgramAddressSync(
      [
        Buffer.from("consent"),
        payer.toBuffer(),
        nonce.toArrayLike(Buffer, "le", 8),
      ],
      program.programId
    );
    consentPda = pda;
    consentBump = bump;

    const tx = await program.methods
      .registerConsent(
        [payer, party2.publicKey, party3.publicKey],
        scopes,
        validFrom,
        validUntil
      )
      .accounts({
        consent: consentPda,
        creator: payer,
        systemProgram: web3.SystemProgram.programId,
      })
      .rpc();

    const consent = await program.account.consentAccount.fetch(consentPda);

    expect(consent.creator.toString()).to.equal(payer.toString());
    expect(consent.parties.length).to.equal(3);
    expect(consent.parties[0].toString()).to.equal(payer.toString());
    expect(consent.scopes).to.deep.equal(scopes);
    expect(consent.validFrom.eq(validFrom)).to.be.true;
    expect(consent.validUntil.eq(validUntil)).to.be.true;
    expect(consent.revoked).to.be.false;
    expect(consent.nonce.eq(nonce)).to.be.true;
  });

  it("verifies a valid consent", async () => {
    await expect(
      program.methods
        .verifyConsent()
        .accounts({ consent: consentPda })
        .rpc()
    ).to.be.fulfilled;
  });

  it("revokes a consent agreement", async () => {
    const tx = await program.methods
      .revokeConsent()
      .accounts({
        consent: consentPda,
        signer: payer,
      })
      .rpc();

    const consent = await program.account.consentAccount.fetch(consentPda);
    expect(consent.revoked).to.be.true;
  });

  it("fails verification on revoked consent", async () => {
    await expect(
      program.methods
        .verifyConsent()
        .accounts({ consent: consentPda })
        .rpc()
    ).to.be.rejectedWith("ConsentRevoked");
  });

  it("fails revoking already revoked consent", async () => {
    await expect(
      program.methods
        .revokeConsent()
        .accounts({
          consent: consentPda,
          signer: payer,
        })
        .rpc()
    ).to.be.rejectedWith("AlreadyRevoked");
  });

  it("registers a new consent for extension test", async () => {
    const newNonce = new BN(Date.now() + 1000);

    const [pda, bump] = web3.PublicKey.findProgramAddressSync(
      [
        Buffer.from("consent"),
        payer.toBuffer(),
        newNonce.toArrayLike(Buffer, "le", 8),
      ],
      program.programId
    );

    await program.methods
      .registerConsent(
        [payer, party2.publicKey],
        ["intimacy"],
        validFrom,
        validUntil
      )
      .accounts({
        consent: pda,
        creator: payer,
        systemProgram: web3.SystemProgram.programId,
      })
      .rpc();

    consentPda = pda;
  });

  it("extends consent validity", async () => {
    const newValidUntil = new BN(
      Math.floor(Date.now() / 1000) + 86400 * 60
    );

    const tx = await program.methods
      .extendConsent(newValidUntil)
      .accounts({
        consent: consentPda,
        signer: payer,
      })
      .rpc();

    const consent = await program.account.consentAccount.fetch(consentPda);
    expect(consent.validUntil.eq(newValidUntil)).to.be.true;
  });

  it("fails extension by non-party", async () => {
    const attacker = web3.Keypair.generate();

    await expect(
      program.methods
        .extendConsent(new BN(Math.floor(Date.now() / 1000) + 86400 * 90))
        .accounts({
          consent: consentPda,
          signer: attacker.publicKey,
        })
        .signers([attacker])
        .rpc()
    ).to.be.rejectedWith("UnauthorizedParty");
  });

  it("fails extension with past timestamp", async () => {
    await expect(
      program.methods
        .extendConsent(new BN(Math.floor(Date.now() / 1000) - 3600))
        .accounts({
          consent: consentPda,
          signer: payer,
        })
        .rpc()
    ).to.be.rejected;
  });

  it("fails registration with single party", async () => {
    const singleNonce = new BN(Date.now() + 9999);

    const [pda] = web3.PublicKey.findProgramAddressSync(
      [
        Buffer.from("consent"),
        payer.toBuffer(),
        singleNonce.toArrayLike(Buffer, "le", 8),
      ],
      program.programId
    );

    await expect(
      program.methods
        .registerConsent(
          [payer],
          scopes,
          validFrom,
          validUntil
        )
        .accounts({
          consent: pda,
          creator: payer,
          systemProgram: web3.SystemProgram.programId,
        })
        .rpc()
    ).to.be.rejectedWith("InsufficientParties");
  });

  it("fails registration with empty scopes", async () => {
    const emptyScopeNonce = new BN(Date.now() + 99999);

    const [pda] = web3.PublicKey.findProgramAddressSync(
      [
        Buffer.from("consent"),
        payer.toBuffer(),
        emptyScopeNonce.toArrayLike(Buffer, "le", 8),
      ],
      program.programId
    );

    await expect(
      program.methods
        .registerConsent(
          [payer, party2.publicKey],
          [],
          validFrom,
          validUntil
        )
        .accounts({
          consent: pda,
          creator: payer,
          systemProgram: web3.SystemProgram.programId,
        })
        .rpc()
    ).to.be.rejectedWith("InvalidScope");
  });
});
