// Consent type definitions for Noir circuits

struct ConsentPublicInputs {
    consent_id: Field,
    chain_id: Field,
    timestamp: Field,
}

struct PartyInclusionProof {
    consent_id: Field,
    party_hash: Field,
    merkle_root: Field,
    merkle_proof: [Field; 10],
    depth: Field,
}

struct ScopeInclusionProof {
    consent_id: Field,
    scope_hash: Field,
    scope_root: Field,
    merkle_proof: [Field; 10],
    depth: Field,
}
