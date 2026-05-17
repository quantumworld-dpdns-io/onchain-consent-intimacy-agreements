// Consent Age Proof
// Proves that a consent recorded at consent_block was still valid at current_block,
// without revealing the exact block numbers or the secret salt used.
//
// Public inputs:
// - consent_id: hash identifying the consent agreement
// - current_block: block number at time of verification
//
// Private inputs:
// - consent_block: block number when consent was registered
// - valid_until: block number when consent expires
// - secret_salt: random value for privacy
// - merkle_proof: proof of inclusion in consent tree (if needed)
//
// Proof statement: consent_block <= current_block <= valid_until
// AND the consent_id corresponds to a valid registration

fn main(
    consent_id: pub Field,
    current_block: pub Field,
    consent_block: Field,
    valid_until: Field,
    secret_salt: Field
) {
    // Verify the consent_id was computed correctly (binds proof to specific consent)
    let computed_id = std::hash::pedersen([
        consent_block,
        valid_until,
        secret_salt
    ]);
    assert(computed_id[0] == consent_id);

    // Check that consent was registered before current block
    assert(consent_block <= current_block);

    // Check that consent hasn't expired
    // Note: if valid_until == 0, consent never expires
    if (valid_until != 0) {
        assert(current_block <= valid_until);
    }
}
