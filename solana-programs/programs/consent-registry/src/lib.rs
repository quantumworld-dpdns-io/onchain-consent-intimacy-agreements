use anchor_lang::prelude::*;
use anchor_lang::solana_program::hash::hash;

declare_id!("CNSRgXXXXXX...XXXX");

#[program]
pub mod consent_registry {
    use super::*;

    pub fn register_consent(
        ctx: Context<RegisterConsent>,
        parties: Vec<Pubkey>,
        scopes: Vec<String>,
        valid_from: i64,
        valid_until: i64,
    ) -> Result<()> {
        require!(
            parties.len() >= 2,
            ConsentError::InsufficientParties
        );
        require!(
            !scopes.is_empty(),
            ConsentError::InvalidScope
        );
        require!(
            valid_until > valid_from,
            ConsentError::InvalidTimeRange
        );
        require!(
            Clock::get()?.unix_timestamp < valid_until,
            ConsentError::ConsentExpired
        );

        let consent = &mut ctx.accounts.consent;
        let creator = ctx.accounts.creator.key();

        require!(
            parties.contains(&creator),
            ConsentError::UnauthorizedParty
        );

        let seeds = &[
            b"consent".as_ref(),
            creator.as_ref(),
            &consent.nonce.to_le_bytes(),
            &[consent.bump],
        ];

        let (pda, bump) = Pubkey::find_program_address(seeds, ctx.program_id);
        require!(pda == consent.key(), ConsentError::PdaMismatch);

        consent.bump = bump;
        consent.creator = creator;
        consent.parties = parties.clone();
        consent.scopes = scopes.clone();
        consent.valid_from = valid_from;
        consent.valid_until = valid_until;
        consent.revoked = false;
        consent.nonce = Clock::get()?.slot;

        let mut party_pubkeys = parties.clone();
        party_pubkeys.sort();
        let hash_input: Vec<u8> = party_pubkeys
            .iter()
            .flat_map(|p| p.to_bytes())
            .chain(scopes.iter().flat_map(|s| s.as_bytes()).collect::<Vec<_>>())
            .collect();
        consent.consent_hash = hash(&hash_input).to_bytes();

        emit!(ConsentCreated {
            consent_account: consent.key(),
            parties: parties.clone(),
            scopes: scopes.clone(),
            valid_from,
            valid_until,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    pub fn revoke_consent(ctx: Context<RevokeConsent>) -> Result<()> {
        let consent = &mut ctx.accounts.consent;
        let signer = ctx.accounts.signer.key();

        require!(
            consent.parties.contains(&signer),
            ConsentError::UnauthorizedParty
        );
        require!(!consent.revoked, ConsentError::AlreadyRevoked);

        consent.revoked = true;

        emit!(ConsentRevoked {
            consent_account: consent.key(),
            revoked_by: signer,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    pub fn verify_consent(ctx: Context<VerifyConsent>) -> Result<()> {
        let consent = &ctx.accounts.consent;
        let clock = Clock::get()?;
        let now = clock.unix_timestamp;

        require!(!consent.revoked, ConsentError::ConsentRevoked);
        require!(
            now >= consent.valid_from && now <= consent.valid_until,
            ConsentError::ConsentExpired
        );

        emit!(ConsentVerified {
            consent_account: consent.key(),
            timestamp: now,
        });

        Ok(())
    }

    pub fn extend_consent(
        ctx: Context<ExtendConsent>,
        new_valid_until: i64,
    ) -> Result<()> {
        let consent = &mut ctx.accounts.consent;
        let signer = ctx.accounts.signer.key();
        let clock = Clock::get()?;
        let now = clock.unix_timestamp;

        require!(
            consent.parties.contains(&signer),
            ConsentError::UnauthorizedParty
        );
        require!(!consent.revoked, ConsentError::ConsentRevoked);
        require!(
            new_valid_until > consent.valid_until,
            ConsentError::InvalidExtension
        );
        require!(
            new_valid_until > now,
            ConsentError::ConsentExpired
        );

        let old_valid_until = consent.valid_until;
        consent.valid_until = new_valid_until;

        emit!(ConsentExtended {
            consent_account: consent.key(),
            extended_by: signer,
            old_valid_until,
            new_valid_until,
            timestamp: now,
        });

        Ok(())
    }
}

#[account]
#[derive(InitSpace)]
pub struct ConsentAccount {
    pub creator: Pubkey,
    pub parties: Vec<Pubkey>,
    #[max_len(10)]
    pub scopes: Vec<String>,
    pub valid_from: i64,
    pub valid_until: i64,
    pub revoked: bool,
    pub bump: u8,
    pub nonce: u64,
    pub consent_hash: [u8; 32],
}

#[derive(Accounts)]
#[instruction(parties: Vec<Pubkey>, scopes: Vec<String>, valid_from: i64, valid_until: i64)]
pub struct RegisterConsent<'info> {
    #[account(
        init,
        payer = creator,
        space = 8 + ConsentAccount::INIT_SPACE,
        seeds = [b"consent", creator.key().as_ref(), &consent.nonce.to_le_bytes()],
        bump
    )]
    pub consent: Account<'info, ConsentAccount>,
    #[account(mut)]
    pub creator: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct RevokeConsent<'info> {
    #[account(
        mut,
        seeds = [b"consent", consent.creator.as_ref(), &consent.nonce.to_le_bytes()],
        bump = consent.bump
    )]
    pub consent: Account<'info, ConsentAccount>,
    pub signer: Signer<'info>,
}

#[derive(Accounts)]
pub struct VerifyConsent<'info> {
    #[account(
        seeds = [b"consent", consent.creator.as_ref(), &consent.nonce.to_le_bytes()],
        bump = consent.bump
    )]
    pub consent: Account<'info, ConsentAccount>,
}

#[derive(Accounts)]
pub struct ExtendConsent<'info> {
    #[account(
        mut,
        seeds = [b"consent", consent.creator.as_ref(), &consent.nonce.to_le_bytes()],
        bump = consent.bump
    )]
    pub consent: Account<'info, ConsentAccount>,
    pub signer: Signer<'info>,
}

#[event]
pub struct ConsentCreated {
    pub consent_account: Pubkey,
    pub parties: Vec<Pubkey>,
    pub scopes: Vec<String>,
    pub valid_from: i64,
    pub valid_until: i64,
    pub timestamp: i64,
}

#[event]
pub struct ConsentRevoked {
    pub consent_account: Pubkey,
    pub revoked_by: Pubkey,
    pub timestamp: i64,
}

#[event]
pub struct ConsentVerified {
    pub consent_account: Pubkey,
    pub timestamp: i64,
}

#[event]
pub struct ConsentExtended {
    pub consent_account: Pubkey,
    pub extended_by: Pubkey,
    pub old_valid_until: i64,
    pub new_valid_until: i64,
    pub timestamp: i64,
}

#[error_code]
pub enum ConsentError {
    #[msg("Consent agreement has expired")]
    ConsentExpired,
    #[msg("Consent agreement has been revoked")]
    ConsentRevoked,
    #[msg("Caller is not an authorized party to this consent")]
    UnauthorizedParty,
    #[msg("Invalid cryptographic signature provided")]
    InvalidSignature,
    #[msg("Consent agreement already exists with these parameters")]
    ConsentAlreadyExists,
    #[msg("At least two parties are required")]
    InsufficientParties,
    #[msg("Scope list cannot be empty")]
    InvalidScope,
    #[msg("valid_until must be after valid_from")]
    InvalidTimeRange,
    #[msg("Consent is already revoked")]
    AlreadyRevoked,
    #[msg("Extension must be later than current expiry")]
    InvalidExtension,
    #[msg("PDA derivation mismatch")]
    PdaMismatch,
}
