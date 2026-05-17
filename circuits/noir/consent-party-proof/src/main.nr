// Consent Party Proof
// Proves that a specific party (identified by their address hash) is 
// included in the set of parties for a given consent agreement,
// without revealing the full list of parties.
//
// Public inputs:
// - consent_id: hash identifying the consent agreement
// - merkle_root: root of the Merkle tree of parties
//
// Private inputs:
// - party_hash: hash of the party's address
// - merkle_proof: Merkle proof of party inclusion [Field; MAX_TREE_DEPTH]
// - tree_depth: actual depth of the Merkle tree

fn main(
    consent_id: pub Field,
    merkle_root: pub Field,
    party_hash: Field,
    merkle_proof: [Field; 10],
    tree_depth: Field
) {
    // Recompute the Merkle root from the party hash and proof
    let mut computed_root = party_hash;
    for i in 0..10 {
        // Branch based on proof direction
        // In production, you'd have direction bits for each level
        let sibling = merkle_proof[i];
        if (sibling != 0) {
            computed_root = std::hash::pedersen([computed_root, sibling])[0];
        }
    }
    
    // Verify computed root matches the public merkle_root
    assert(computed_root == merkle_root);
    
    // Bind this proof to the specific consent_id
    // The consent_id is derived from the merkle_root and other consent parameters
    assert(merkle_root == consent_id); // Simplified - in prod, consent_id = hash(merkle_root, scopes_root, timestamps)
}
