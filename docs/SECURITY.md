# Security

## Responsible Disclosure

We take the security of our smart contracts, ZK circuits, and backend infrastructure seriously. If you discover a security vulnerability, please follow these steps:

1. **Do not** disclose the vulnerability publicly or to third parties.
2. **Email** security details to the maintainers (refer to GitHub repository settings or open a security advisory).
3. **Include**:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)
4. **Allow** up to 72 hours for an initial response.
5. **Cooperate** to validate the issue and coordinate a fix timeline.

We commit to:
- Acknowledging receipt within 72 hours.
- Providing a timeline for fix and disclosure.
- Credit in our security advisories and documentation (if desired).

## OWASP Test Coverage

We maintain comprehensive Robot Framework test suites covering the OWASP Top 10 (2021) for API security testing:

| Category | Test Suite | Scope |
|---|---|---|
| A01: Broken Access Control | `tests/robot/owasp/A01-broken-access-control.robot` | Unauthorized consent revocation, party escalation |
| A02: Cryptographic Failures | `tests/robot/owasp/A02-cryptographic-failures.robot` | Weak encryption, exposed metadata |
| A03: Injection | `tests/robot/owasp/A03-injection.robot` | SQLi, NoSQLi, Solidity injection via calldata |
| A04: Insecure Design | `tests/robot/owasp/A04-insecure-design.robot` | Missing rate limits, unchecked expiry |
| A05: Security Misconfiguration | `tests/robot/owasp/A05-security-misconfig.robot` | Default configs, verbose errors |
| A06: Vulnerable Components | `tests/robot/owasp/A06-vulnerable-components.robot` | Dependency audit, outdated compiler |
| A07: Identification & Auth Failures | `tests/robot/owasp/A07-identification-auth.robot` | Weak signatures, replay attacks |
| A08: Software & Data Integrity | `tests/robot/owasp/A08-software-integrity.robot` | Unauthorized contract upgrades |
| A09: Security Logging Failures | `tests/robot/owasp/A09-logging-monitoring.robot` | Missing audit trails, log injection |
| A10: SSRF | `tests/robot/owasp/A10-ssrf.robot` | Server-side request forgery via metadata URLs |

### Running OWASP Tests

```bash
# Start services
docker compose -f infra/docker-compose.yml up -d

# Run all OWASP tests
robot tests/robot/owasp/

# Run single category
robot tests/robot/owasp/A01-broken-access-control.robot
```

## Auditing

### Automated Auditing

#### Smart Contract Static Analysis

```bash
# Slither (Solidity)
slither src/contracts/ --filter-path node_modules --exclude-dependencies

# Mythril (symbolic execution)
myth analyze src/contracts/ConsentRegistry.sol --solc-json mythril-config.json

# Echidna (property-based fuzz)
echidna-test src/contracts/ --config tests/fuzz/echidna.yaml
```

#### ZK Circuit Analysis

- Noir circuits are type-checked at compile time via `nargo check`.
- Barretenberg proving system is used for production Groth16 proofs.
- RISC Zero guest programs are executed and proven inside the zkVM sandbox.

### Scheduled Audits

| Frequency | Type | Tool / Method |
|---|---|---|
| Per PR | Slither scan | GitHub Actions CI |
| Per PR | Dependency scan | `npm audit`, `cargo audit`, `dependabot` |
| Weekly | Full Mythril scan | GitHub Actions scheduled workflow |
| Weekly | OWASP ZAP DAST | GitHub Actions scheduled workflow |
| Monthly | Echidna fuzz campaign | Manual trigger |
| Quarterly | Manual code review | External security firm |
| Pre-release | Third-party audit | External security firm |

## Secrets Management

- **No secrets in code**: Private keys, API keys, and mnemonics are never committed.
- **Environment variables**: All secrets are loaded from `.env` (gitignored) or secrets manager.
- **CI/CD**: Secrets injected via GitHub Actions secrets; never logged.
- **Local dev**: See `.env.example` for required variables.

## Smart Contract Security

### Known Considerations

1. **Reentrancy**: All state-changing functions follow checks-effects-interactions pattern.
2. **Timestamp manipulation**: Consent expiry uses `block.timestamp`; maximum drift of ~12 seconds (acceptable for consent use case).
3. **Signature replay**: EIP-712 signatures include `chainId`, `contract address`, and a nonce.
4. **Front-running**: Revocation uses a commit-reveal scheme to prevent MEV attacks.
5. **Gas griefing**: Bounded loops; `parties` array limited to `MAX_PARTIES` constant.

### Upgrade Path

Contracts are deployed via `ConsentFactory` (CREATE2) and are **not upgradeable** by design — this ensures immutability and trust. If protocol changes are required, a new factory is deployed and users migrate.

## Reporting

Security-related test results are published in CI run logs. Critical findings are tracked as GitHub Issues with the `security` label and have a 7-day fix SLA.
