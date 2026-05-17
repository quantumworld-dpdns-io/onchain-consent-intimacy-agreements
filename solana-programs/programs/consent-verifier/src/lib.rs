use anchor_lang::prelude::*;
use anchor_lang::solana_program::{
    hash::hash,
    secp256k1_recover::secp256k1_recover,
    secp256k1_recover::Secp256k1RecoverError,
};

declare_id!("CNSVfXXXXXX...XXXX");

#[program]
pub mod consent_verifier {
    use super::*;

    pub fn verify_consent_proof(
        ctx: Context<VerifyConsentProof>,
        proof_data: Vec<u8>,
        public_key: [u8; 64],
        signature: [u8; 64],
        recovery_id: u8,
        message: Vec<u8>,
    ) -> Result<()> {
        let verifier = &mut ctx.accounts.verifier;

        let proof_hash = hash(&proof_data).to_bytes();
        require!(
            !verifier.used_proof_hashes.contains(&proof_hash),
            VerifierError::ProofAlreadyUsed
        );

        let message_hash = hash(&message).to_bytes();

        let recovered_pubkey = secp256k1_recover(&message_hash, recovery_id, &signature)
            .map_err(|_| VerifierError::InvalidSignature)?;

        let recovered_bytes = recovered_pubkey.to_bytes();
        let expected_bytes: [u8; 64] = public_key;
        require!(
            recovered_bytes == expected_bytes,
            VerifierError::SignerMismatch
        );

        verifier.used_proof_hashes.push(proof_hash);
        if verifier.used_proof_hashes.len() > MAX_PROOF_HASHES {
            verifier.used_proof_hashes.remove(0);
        }

        emit!(ConsentProofVerified {
            verifier_account: verifier.key(),
            proof_hash,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    pub fn initialize_verifier(ctx: Context<InitializeVerifier>) -> Result<()> {
        let verifier = &mut ctx.accounts.verifier;
        verifier.authority = ctx.accounts.authority.key();
        verifier.used_proof_hashes = Vec::new();
        Ok(())
    }
}

pub const MAX_PROOF_HASHES: usize = 1000;

#[account]
#[derive(InitSpace)]
pub struct VerifierAccount {
    pub authority: Pubkey,
    #[max_len(1000)]
    pub used_proof_hashes: Vec<[u8; 32]>,
}

#[derive(Accounts)]
pub struct InitializeVerifier<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + VerifierAccount::INIT_SPACE,
        seeds = [b"consent-verifier"],
        bump
    )]
    pub verifier: Account<'info, VerifierAccount>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct VerifyConsentProof<'info> {
    #[account(
        mut,
        seeds = [b"consent-verifier"],
        bump
    )]
    pub verifier: Account<'info, VerifierAccount>,
}

#[event]
pub struct ConsentProofVerified {
    pub verifier_account: Pubkey,
    pub proof_hash: [u8; 32],
    pub timestamp: i64,
}

#[error_code]
pub enum VerifierError {
    #[msg("This proof has already been used to prevent replay attacks")]
    ProofAlreadyUsed,
    #[msg("Invalid secp256k1 signature")]
    InvalidSignature,
    #[msg("Recovered public key does not match the expected signer")]
    SignerMismatch,
    #[msg("Internal secp256k1 recovery error")]
    Secp256k1Error,
}

impl From<Secp256k1RecoverError> for VerifierError {
    fn from(_: Secp256k1RecoverError) -> Self {
        VerifierError::Secp256k1Error
    }
}
