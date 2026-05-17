# On-Chain Consent & Intimacy Agreements

> Encrypted, time-bound, revocable signed agreements for professional content production — secured by blockchain, zero-knowledge proofs, and multi-chain infrastructure.

## Overview

[Project logo/architecture diagram placeholder]

On-chain consent for intimacy agreements enables parties to create, manage, verify, and revoke consent agreements across multiple blockchains. Key innovations:

- **Privacy-first**: Zero-knowledge proofs (Noir + RISC Zero) enable consent verification without revealing personal details
- **Multi-chain**: Deployed on Ethereum, BSC, Polygon, Palm, and Base (EVM) + Solana (native)
- **Time-bound**: Consent automatically expires after configured duration
- **Revocable**: Any party can revoke consent at any time
- **Searchable**: Encrypted consent metadata indexed in Qdrant vector database for semantic search
- **AI-ready**: MCP server exposes consent operations as AI-agent tools

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Frontend / AI Agents                     │
├─────────────────────────────────────────────────────────────┤
│                    API Gateway (Go)                         │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │
│  │ Consent  │ │  Proof   │ │  MCP     │ │  Event       │  │
│  │  API     │ │  API     │ │  Server  │ │  Indexer     │  │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └──────┬───────┘  │
├───────┴────────────┴────────────┴──────────────┴──────────┤
│                    ZK Proof Service (Rust)                  │
│  ┌──────────────────┐ ┌──────────────────┐                │
│  │   Noir Prover    │ │  RISC Zero zkVM  │                │
│  └──────────────────┘ └──────────────────┘                │
├───────────────────────────────────────────────────────────┤
│                  Smart Contracts Layer                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐ │
│  │Consent   │ │Consent   │ │Consent   │ │Consent       │ │
│  │Registry  │ │Escrow    │ │Token     │ │Verifier      │ │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └──────┬───────┘ │
├───────┴────────────┴────────────┴──────────────┴──────────┤
│                     Blockchains                            │
│  Ethereum │ BSC │ Polygon │ Palm │ Base │ Solana          │
└───────────────────────────────────────────────────────────┘
│                    Data Layer                               │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │
│  │  Qdrant  │ │  Redis   │ │PostgreSQL│ │  Prometheus  │  │
│  │ (Vectors)│ │ (Cache)  │ │(Events)  │ │  (Metrics)   │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │
└───────────────────────────────────────────────────────────┘
```

## Tech Stack

| Layer | Technology |
|---|---|
| **Smart Contracts (EVM)** | Solidity 0.8.27, Foundry, Hardhat |
| **Smart Contracts (Solana)** | Rust, Anchor Framework |
| **Zero-Knowledge Proofs** | Noir, RISC Zero, Barretenberg |
| **ZK Proof Service** | Rust, Actix-web |
| **API Gateway** | Go, Gin, go-ethereum |
| **Vector Database** | Qdrant (self-hosted or cloud) |
| **Cache** | Redis |
| **Event Store** | PostgreSQL |
| **Testing** | Robot Framework, Foundry fuzz, Echidna |
| **Security** | Slither, Mythril, OWASP ZAP |
| **CI/CD** | GitHub Actions |
| **Infrastructure** | Docker, Kubernetes, Terraform |
| **Monitoring** | Prometheus, Grafana |

## Quick Start

### Prerequisites
- Foundry, Node.js 20+, Go 1.22+, Rust 1.77+, Python 3.12+
- Docker & Docker Compose (for local services)
- Qdrant (Docker or cloud)

### Local Development

```bash
# Clone the repo
git clone https://github.com/quantumworld-dpdns-io/onchain-consent-intimacy-agreements.git
cd onchain-consent-intimacy-agreements

# Install dependencies
npm install
pip install -r requirements.txt

# Start local services
docker compose -f infra/docker-compose.yml up -d

# Compile smart contracts
forge build
npx hardhat compile

# Run EVM tests
forge test -vvv
npx hardhat test

# Run Solana tests
cd solana-programs && anchor test && cd ..

# Run ZK circuit tests
cd circuits/noir && nargo test --workspace && cd ../..

# Deploy to local Anvil
forge script scripts/deploy/anvil.s.sol --broadcast --rpc-url http://localhost:8545

# Start Go API
cd backend/go-api && go run ./cmd/server &
```

### Docker Compose (all services)

```bash
docker compose -f infra/docker-compose.yml up --build
```

## Project Structure

```
├── src/contracts/         # Solidity smart contracts (5 chains)
├── solana-programs/       # Rust Anchor programs (Solana)
├── circuits/              # Zero-knowledge circuits
│   ├── noir/              # Noir ZK circuits (3 proof types)
│   └── risc-zero/         # RISC Zero zkVM guest programs
├── backend/               # Backend services
│   ├── go-api/            # Go API gateway + MCP server
│   ├── rust-zk-service/   # Rust ZK proof service
│   └── event-indexer/     # On-chain event indexer
├── tests/                 # All test suites
│   ├── solidity/          # Foundry Solidity tests
│   ├── hardhat/           # Hardhat TypeScript tests
│   ├── robot/             # Robot Framework (OWASP Top 10)
│   ├── fuzz/              # Echidna fuzz config
│   └── qdrant/            # Qdrant vector search tests
├── scripts/               # Deployment & utility scripts
├── infra/                 # Docker, K8s, Terraform
├── .github/workflows/     # CI/CD pipelines
└── docs/                  # Documentation
```

## Security

### OWASP Top 10 Coverage

| Category | Test Suite | Status |
|---|---|---|
| A01: Broken Access Control | `tests/robot/owasp/A01-broken-access-control.robot` | ✅ |
| A02: Cryptographic Failures | `tests/robot/owasp/A02-cryptographic-failures.robot` | ✅ |
| A03: Injection | `tests/robot/owasp/A03-injection.robot` | ✅ |
| A04: Insecure Design | `tests/robot/owasp/A04-insecure-design.robot` | ✅ |
| A05: Security Misconfiguration | `tests/robot/owasp/A05-security-misconfig.robot` | ✅ |
| A06: Vulnerable Components | `tests/robot/owasp/A06-vulnerable-components.robot` | ✅ |
| A07: Identification & Auth Failures | `tests/robot/owasp/A07-identification-auth.robot` | ✅ |
| A08: Software & Data Integrity | `tests/robot/owasp/A08-software-integrity.robot` | ✅ |
| A09: Security Logging Failures | `tests/robot/owasp/A09-logging-monitoring.robot` | ✅ |
| A10: SSRF | `tests/robot/owasp/A10-ssrf.robot` | ✅ |

### Static Analysis
- **Slither**: Solidity static analysis (CI job + weekly scheduled scan)
- **Mythril**: Solidity symbolic execution security analysis
- **Echidna**: Property-based fuzz testing for Solidity contracts

### Dynamic Analysis
- **OWASP ZAP**: Automated API security scanning (DAST)
- **Robot Framework**: Full OWASP Top 10 test suites

## Smart Contracts

### EVM Contracts (Solidity)

| Contract | Description | Address |
|---|---|---|
| ConsentRegistry.sol | Register, revoke, query time-bound consent agreements | Deployed per-chain |
| ConsentEscrow.sol | Encrypted consent storage with access control | Deployed per-chain |
| ConsentToken.sol | ERC-1155 consent receipt tokens | Deployed per-chain |
| ConsentVerifier.sol | ZK proof verification interface | Deployed per-chain |
| ConsentFactory.sol | CREATE2 factory for deterministic deployment | Deployed per-chain |

### Solana Programs (Rust)

| Program | Description | Address |
|---|---|---|
| consent-registry | Consent registration and management | Devnet |
| consent-verifier | ZK proof verification on Solana | Devnet |
| consent-token | SPL token consent receipts | Devnet |

## Zero-Knowledge Proofs

### Noir Circuits
- **Consent Age Proof**: Prove consent was valid at a given block without revealing exact dates
- **Party Inclusion Proof**: Prove a specific party is in the consent set
- **Scope Inclusion Proof**: Prove a specific scope was authorized

### RISC Zero zkVM
- **Consent Workflow**: Verify multi-step consent workflow compliance
- **Compliance Audit**: Batch audit consent records against rules

## Deployment

### Testnets
```bash
# Deploy to all chains
npx hardhat run scripts/deploy/all-chains.ts

# Deploy single chain
npm run deploy:sepolia
npm run deploy:bsc-testnet
npm run deploy:amoy
npm run deploy:palm-testnet
npm run deploy:base-sepolia

# Deploy Solana
cd solana-programs && anchor deploy --provider.cluster devnet
```

### Deployed Addresses
| Chain | Registry | Escrow | Token | Verifier | Factory |
|---|---|---|---|---|---|
| Sepolia | TBD | TBD | TBD | TBD | TBD |
| BSC Testnet | TBD | TBD | TBD | TBD | TBD |
| Amoy | TBD | TBD | TBD | TBD | TBD |
| Palm Testnet | TBD | TBD | TBD | TBD | TBD |
| Base Sepolia | TBD | TBD | TBD | TBD | TBD |
| Solana Devnet | TBD | - | TBD | TBD | - |

## API Reference

Consent management endpoints:

| Method | Endpoint | Description |
|---|---|---|
| POST | /api/v1/consent | Create consent agreement |
| GET | /api/v1/consent/:id | Get consent details |
| POST | /api/v1/consent/:id/verify | Verify with ZK proof |
| POST | /api/v1/consent/:id/revoke | Revoke consent |
| POST | /api/v1/consent/:id/proof | Generate ZK proof |
| GET | /api/v1/parties/:addr/consents | List party consents |
| GET | /api/v1/search | Semantic search |

Full OpenAPI spec: `backend/go-api/api/openapi.yaml`

## MCP Integration

Model Context Protocol server exposes consent operations as AI-agent tools:

- `consent_create` - Create new consent on any supported chain
- `consent_verify` - Verify consent validity
- `consent_revoke` - Revoke consent
- `consent_query` - Query consent details
- `consent_search` - Semantic search via Qdrant
- `proof_generate` - Generate ZK proof
- `chain_status` - Check chain health

## License

MIT © [quantumworld-dpdns-io](https://github.com/quantumworld-dpdns-io)
