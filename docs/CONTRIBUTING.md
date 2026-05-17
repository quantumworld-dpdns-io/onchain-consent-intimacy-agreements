# Contributing

## Development Setup

### Prerequisites

- **Foundry** (forge, cast, anvil)
- **Node.js** 20+ with npm
- **Go** 1.22+
- **Rust** 1.77+ (with `wasm32-unknown-unknown` target for RISC Zero)
- **Python** 3.12+ with pip
- **Docker** & Docker Compose
- **Qdrant** (Docker or cloud instance)
- **Anchor CLI** (for Solana)
- **Noir CLI** (`nargo`) for ZK circuit compilation

### Install Dependencies

```bash
# Node.js dependencies
npm install

# Python dependencies
pip install -r requirements.txt

# Solana program dependencies
cd solana-programs && npm install && cd ..
```

## Coding Standards

### Solidity
- Target Solidity 0.8.27
- Follow [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- All public/external functions must include NatSpec documentation
- Use Foundry's `forge fmt` before committing
- Run `forge build` — no warnings allowed

### Rust
- Format with `rustfmt` (`cargo fmt`)
- Lint with `clippy` (`cargo clippy -- -D warnings`)
- Follow the [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/)

### Go
- Format with `gofumpt` or `gofmt -s`
- Lint with `golangci-lint`
- Follow [Go Conventions](https://go.dev/doc/effective_go)

### JavaScript / TypeScript
- Use TypeScript for all new code
- Format with Prettier
- Lint with ESLint

### Python
- Format with Ruff (`ruff format .`)
- Lint with Ruff (`ruff check .`)

## Branching Strategy

- `main` — production-ready, protected. Only merge via PR with passing CI and approval.
- `dev` — integration branch for feature work. PRs target `dev` first, then `dev` → `main`.
- `feat/<name>` — feature branches branched from `dev`.
- `fix/<name>` — bugfix branches branched from `dev`.
- `chore/<name>` — maintenance, dependencies, tooling.

## Pull Request Process

1. Create a feature/fix branch from `dev`.
2. Write tests for all new functionality.
3. Ensure all existing tests pass locally:
   ```bash
   forge test -vvv
   npx hardhat test
   cd solana-programs && anchor test && cd ..
   cd circuits/noir && nargo test --workspace && cd ../..
   ```
4. Run static analysis:
   ```bash
   forge build  # Solidity
   cargo clippy -- -D warnings  # Rust
   golangci-lint run  # Go
   ```
5. Run security scanners (if applicable):
   ```bash
   slither . --filter-path node_modules
   ```
6. Push your branch and open a PR against `dev`.
   - Title format: `type(scope): brief description`
     - e.g. `feat(consent): add batch revocation`
     - e.g. `fix(verifier): correct nullifier check`
     - e.g. `docs(readme): update deployment table`
   - Include a description of what changed and why.
   - Reference any related issues.
7. Ensure all CI checks pass (lint, test, build, security scan).
8. Request review from at least one maintainer.

## Testing Philosophy

- **Unit tests** cover individual contract/function behavior.
- **Integration tests** (Hardhat) cover multi-contract workflows.
- **Fuzz tests** (Echidna, Foundry) cover edge cases and invariants.
- **Robot Framework** tests cover OWASP Top 10 security scenarios.
- **Qdrant tests** cover vector search indexing and query paths.
- No PR merges without passing CI tests.

## Security Considerations

- Never commit private keys, mnemonics, or API secrets.
- Use `.env` files for local secrets (`.env` is gitignored).
- Report security vulnerabilities per `SECURITY.md`.
- All smart contract changes must pass Slither + Mythril analysis.

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description

[optional body]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.

## Code Review

- Reviewers should verify test coverage, security implications, gas optimizations, and adherence to standards.
- All review comments must be addressed before merge.
- Maintainers squash-merge PRs into `dev`.

## Getting Help

- Open a GitHub Discussion for questions.
- Tag maintainers on PRs for review.
- Check the `docs/` folder for architecture and API guides.
