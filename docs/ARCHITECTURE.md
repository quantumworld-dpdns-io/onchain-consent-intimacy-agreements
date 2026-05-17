# Architecture

## Smart Contract Architecture

### High-Level Data Flow

```
 Party A                   Party B
    |                         |
    |--- sign(agreement) ---->|
    |<--- sign(agreement) ----|
    |                         |
    |--- submit to chain ---->|
    |                         |
    v                         v
┌─────────────────────────────────┐
│       ConsentRegistry          │
│  stores: hash(metadata),       │
│  parties[], expiry, status,    │
│  scope, escrowId               │
└───────────┬─────────────────────┘
            │
            v
┌─────────────────────────────────┐
│       ConsentEscrow            │
│  stores: encrypted(metadata)   │
│  access: parties + authorized  │
└───────────┬─────────────────────┘
            │
            v
┌─────────────────────────────────┐
│       ConsentToken             │
│  ERC-1155: mint receipt NFT    │
│  to each party                 │
└───────────┬─────────────────────┘
            │
            v
┌─────────────────────────────────┐
│       ConsentVerifier          │
│  on-chain ZK proof validation  │
│  (via Noir/RISC Zero)          │
└─────────────────────────────────┘
```

### Consent Lifecycle

```
           ┌──────────┐
           │  Draft   │
           └────┬─────┘
                │ parties sign
                v
           ┌──────────┐
           │  Active  │◄────┐
           └────┬─────┘     │
                │            │ revoke
     ┌──────────┼──────────┐│
     v          v          v│
  ┌──────┐ ┌────────┐ ┌────┴───┐
  │Expired│ │Revoked │ │Completed│
  └──────┘ └────────┘ └────────┘
```

1. **Draft** — Agreement is created on-chain; parties submit signatures.
2. **Active** — All parties have signed; timer starts.
3. **Expired** — Block timestamp exceeds `startTime + duration`; consent invalid.
4. **Revoked** — Any party calls `revoke()`; immediate invalidation.
5. **Completed** — All intended actions performed; explicit completion.

### Contract Interactions

```
User / Agent
    │
    ├── ConsentRegistry.register()
    │       │
    │       ├── emits ConsentCreated(consentId, parties, expiry)
    │       ├── calls ConsentEscrow.store() [if metadata provided]
    │       └── calls ConsentToken.mint() [receipt NFTs]
    │
    ├── ConsentRegistry.revoke()
    │       │
    │       ├── emits ConsentRevoked(consentId, revoker)
    │       └── calls ConsentEscrow.lock()
    │
    ├── ConsentRegistry.isConsentValid(consentId, proof)
    │       │
    │       └── calls ConsentVerifier.verify()
    │
    └── ConsentVerifier.verifyProof(proof, publicInputs)
            │
            └── verifies Groth16/PLONK proof via Noir/RISC Zero
```

## Zero-Knowledge Proof Architecture

### Noir Circuits (`circuits/noir/`)

Three proof types:

1. **consent-age-proof** — Proves consent was valid at a target block height without revealing exact start/end times.
   - Public inputs: `consentId`, `targetBlock`, `merkleRoot`
   - Private inputs: `startBlock`, `endBlock`, `merkleProof`
   - Constraint: `startBlock <= targetBlock < endBlock`

2. **party-inclusion-proof** — Proves a specific address was a consent party without revealing other parties.
   - Public inputs: `consentId`, `partyAddress`, `merkleRoot`
   - Private inputs: `partiesMerkleProof`, `addressIndex`

3. **scope-inclusion-proof** — Proves a specific scope (activity type) was authorized.
   - Public inputs: `consentId`, `scope`, `merkleRoot`
   - Private inputs: `scopesMerkleProof`, `scopeIndex`

### RISC Zero zkVM (`circuits/risc-zero/`)

1. **Consent Workflow Proof** — Verifies multi-step consent workflow compliance (e.g., "content was captured during valid consent window and within authorized scope").
2. **Compliance Audit Proof** — Batch-audits consent records against policy rules without revealing individual records.

### Proof Flow

```
Client / Agent
    │
    ├── Request: POST /api/v1/consent/:id/proof
    │       │
    │       v
    │   Go API Gateway
    │       │
    │       v
    │   Rust ZK Service
    │       │
    │       ├── [Noir] compile circuit → generate witness → prove
    │       │       └── returns Groth16 proof + public inputs
    │       │
    │       ├── [RISC Zero] build zkVM → execute guest → prove
    │       │       └── returns receipt + journal
    │       │
    │       v
    │   Store proof in Qdrant (metadata) + return to client
    │
    └── Verify: POST /api/v1/consent/:id/verify
            │
            v
        On-chain: ConsentVerifier.verifyProof()
            │
            └── Returns valid/invalid
```

## Security Model

### Threat Model

| Threat | Mitigation |
|---|---|
| Unauthorized consent creation | EIP-712 signature verification; only signed parties |
| Consent replay across chains | Chain-specific `consentId` via CREATE2 + chainId |
| Metadata leakage | Encrypted payload in ConsentEscrow; access restricted |
| ZK proof forgery | Groth16 setup ceremony; on-chain verifier; Noir type system |
| Front-running | Commit-reveal scheme for revocation |
| Oracle manipulation | Time-based expiry uses block timestamps (not oracles) |
| Invalid party addition | Static party set at creation; cannot be modified |

### Access Control

```
ConsentRegistry
  ├── register()      → onlyEOA (via EIP-712)
  ├── revoke()        → any party or authorized operator
  ├── isConsentValid()→ public (permissionless)
  └── getConsent()    → public (permissionless)

ConsentEscrow
  ├── store()         → only ConsentRegistry
  ├── retrieve()      → only consent parties + authorized resolvers
  └── lock()          → only ConsentRegistry (on revoke/expire)

ConsentToken
  ├── mint()          → only ConsentRegistry
  └── burn()          → token holder or registry
```

## Data Storage

### On-Chain (minimal)

```
ConsentRegistry storage:
  mapping(bytes32 => Consent) consents;
    struct Consent {
      address[] parties;
      uint256 startTime;
      uint256 duration;
      bytes32 scopeHash;
      bytes32 metadataHash;
      bytes32 escrowId;
      ConsentStatus status;  // Draft, Active, Expired, Revoked, Completed
    }
```

### Off-Chain (encrypted, searchable)

- **Qdrant**: Vector embeddings of consent metadata (encrypted at write, decrypted at query with proper auth)
- **Redis**: Cached consent status for fast lookups
- **PostgreSQL**: Event log for indexing and analytics

## Multi-Chain Deployment Strategy

```
                        ┌──────────────────┐
                        │  ConsentFactory   │
                        │   (deterministic  │
                        │    CREATE2)       │
                        └────────┬─────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
    ┌────▼────┐            ┌────▼────┐            ┌────▼────┐
    │Ethereum │            │  BSC    │            │ Polygon │
    │ Sepolia │            │ Testnet │            │  Amoy   │
    └─────────┘            └─────────┘            └─────────┘
    ┌─────────┐            ┌─────────┐            ┌─────────┐
    │  Palm   │            │  Base   │            │ Solana  │
    │ Testnet │            │ Sepolia │            │ Devnet  │
    └─────────┘            └─────────┘            └─────────┘
```

Each chain gets its own `ConsentFactory` deployed at a deterministic address via CREATE2 (EVM) or Anchor upgradeable program (Solana). The Go API gateway routes chain-specific requests by reading `chain` parameter.

## Event Indexing

```
ConsentRegistry events
    │
    v
Event Indexer (Go)
    │
    ├── Parses events from all configured chains
    ├── Stores structured data in PostgreSQL
    ├── Generates vector embeddings → Qdrant
    └── Updates Redis cache
```

## Monitoring & Observability

- **Prometheus** metrics: request count, latency, proof generation time, chain health, cache hit rate
- **Grafana** dashboards: consent lifecycle overview, chain status, error rates
- **Structured logging**: JSON format, correlation IDs across services
- **Health endpoints**: `/health` and `/ready` on all services
