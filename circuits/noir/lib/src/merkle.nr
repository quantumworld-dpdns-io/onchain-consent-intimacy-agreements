// Merkle tree utilities for Noir circuits

// Verify a Merkle proof
pub fn verify_merkle_proof(
    leaf: Field,
    root: Field,
    proof: [Field; 10],
    directions: [u1; 10],
    depth: Field
) -> bool {
    let mut computed = leaf;
    for i in 0..10 {
        if (i as Field) < depth {
            let sibling = proof[i];
            if (directions[i] == 0) {
                computed = std::hash::pedersen([computed, sibling])[0];
            } else {
                computed = std::hash::pedersen([sibling, computed])[0];
            }
        }
    }
    computed == root
}

// Compute a Pedersen hash of two fields
pub fn hash_pair(left: Field, right: Field) -> Field {
    std::hash::pedersen([left, right])[0]
}
