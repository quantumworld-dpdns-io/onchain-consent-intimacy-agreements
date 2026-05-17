use anchor_lang::prelude::*;
use anchor_lang::system_program;
use anchor_spl::token::{self, Burn, Mint, MintTo, Token, TokenAccount};

declare_id!("CNSTkXXXXXX...XXXX");

#[program]
pub mod consent_token {
    use super::*;

    pub fn initialize_token_mint(
        ctx: Context<InitializeTokenMint>,
        _consent_nonce: u64,
        metadata_uri: String,
        expiration: i64,
    ) -> Result<()> {
        let mint = &mut ctx.accounts.mint;
        mint.authority = ctx.accounts.authority.key();
        Ok(())
    }

    pub fn mint_consent_receipt(
        ctx: Context<MintConsentReceipt>,
        amount: u64,
    ) -> Result<()> {
        let mint = &ctx.accounts.mint;
        let token_program = &ctx.accounts.token_program;

        let seeds = &[
            b"consent-token".as_ref(),
            mint.key().as_ref(),
            &[ctx.accounts.mint_bump],
        ];
        let signer_seeds = &[&seeds[..]];

        let cpi_ctx = CpiContext::new_with_signer(
            token_program.to_account_info(),
            MintTo {
                mint: mint.to_account_info(),
                to: ctx.accounts.destination.to_account_info(),
                authority: ctx.accounts.authority.to_account_info(),
            },
            signer_seeds,
        );

        token::mint_to(cpi_ctx, amount)?;

        emit!(ConsentReceiptMinted {
            mint: mint.key(),
            destination: ctx.accounts.destination.key(),
            amount,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    pub fn burn_consent_receipt(
        ctx: Context<BurnConsentReceipt>,
        amount: u64,
    ) -> Result<()> {
        let mint = &ctx.accounts.mint;

        let seeds = &[
            b"consent-token".as_ref(),
            mint.key().as_ref(),
            &[ctx.accounts.mint_bump],
        ];
        let signer_seeds = &[&seeds[..]];

        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Burn {
                mint: mint.to_account_info(),
                from: ctx.accounts.source.to_account_info(),
                authority: ctx.accounts.authority.to_account_info(),
            },
            signer_seeds,
        );

        token::burn(cpi_ctx, amount)?;

        emit!(ConsentReceiptBurned {
            mint: mint.key(),
            source: ctx.accounts.source.key(),
            amount,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }
}

#[account]
#[derive(InitSpace)]
pub struct ConsentTokenMetadata {
    pub consent_registry: Pubkey,
    pub consent_nonce: u64,
    #[max_len(200)]
    pub metadata_uri: String,
    pub expiration: i64,
}

#[derive(Accounts)]
#[instruction(consent_nonce: u64, metadata_uri: String, expiration: i64)]
pub struct InitializeTokenMint<'info> {
    #[account(
        init,
        payer = authority,
        mint::decimals = 0,
        mint::authority = authority,
        mint::freeze_authority = Option::None,
        seeds = [b"consent-token", &consent_nonce.to_le_bytes()],
        bump
    )]
    pub mint: Account<'info, Mint>,
    #[account(
        init,
        payer = authority,
        space = 8 + ConsentTokenMetadata::INIT_SPACE,
        seeds = [b"consent-token-meta", mint.key().as_ref()],
        bump
    )]
    pub metadata: Account<'info, ConsentTokenMetadata>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub rent: Sysvar<'info, Rent>,
    pub system_program: Program<'info, System>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct MintConsentReceipt<'info> {
    #[account(
        mut,
        seeds = [b"consent-token", &mint_bump.to_le_bytes()],
        bump
    )]
    pub mint: Account<'info, Mint>,
    #[account(
        init_if_needed,
        payer = authority,
        token::mint = mint,
        token::authority = authority,
    )]
    pub destination: Account<'info, TokenAccount>,
    #[account(mut)]
    pub authority: Signer<'info>,
    /// CHECK: PDA authority for the mint, validated via seeds
    #[account(
        seeds = [b"consent-token", mint.key().as_ref()],
        bump = mint_bump
    )]
    pub mint_authority: AccountInfo<'info>,
    pub rent: Sysvar<'info, Rent>,
    pub system_program: Program<'info, System>,
    pub token_program: Program<'info, Token>,
    pub mint_bump: u8,
}

#[derive(Accounts)]
pub struct BurnConsentReceipt<'info> {
    #[account(
        mut,
        seeds = [b"consent-token", &mint_bump.to_le_bytes()],
        bump
    )]
    pub mint: Account<'info, Mint>,
    #[account(
        mut,
        token::mint = mint,
    )]
    pub source: Account<'info, TokenAccount>,
    pub authority: Signer<'info>,
    /// CHECK: PDA authority for the mint, validated via seeds
    #[account(
        seeds = [b"consent-token", mint.key().as_ref()],
        bump = mint_bump
    )]
    pub mint_authority: AccountInfo<'info>,
    pub token_program: Program<'info, Token>,
    pub mint_bump: u8,
}

#[event]
pub struct ConsentReceiptMinted {
    pub mint: Pubkey,
    pub destination: Pubkey,
    pub amount: u64,
    pub timestamp: i64,
}

#[event]
pub struct ConsentReceiptBurned {
    pub mint: Pubkey,
    pub source: Pubkey,
    pub amount: u64,
    pub timestamp: i64,
}
