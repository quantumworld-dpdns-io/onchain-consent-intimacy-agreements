# API Documentation

## Authentication

All API requests require one of the following:

```
Authorization: Bearer <jwt-token>
X-API-Key: <api-key>
```

Requests without valid authentication receive a `401 Unauthorized` response.

## Endpoints

### Create Consent

Creates a new time-bound consent agreement on the specified blockchain.

```
POST /api/v1/consent
```

#### Request Body

```json
{
    "parties": ["0x...", "0x..."],
    "scopes": ["photography", "distribution"],
    "duration": 2592000,
    "chain": "sepolia",
    "metadata": {
        "contentHash": "0x...",
        "location": "studio-a"
    }
}
```

| Field | Type | Description |
|---|---|---|
| `parties` | `string[]` | Ethereum/Solana addresses of consent parties (min 2, max 10) |
| `scopes` | `string[]` | Authorized activity scopes |
| `duration` | `uint256` | Consent duration in seconds |
| `chain` | `string` | Target blockchain (`sepolia`, `bsc-testnet`, `amoy`, `palm-testnet`, `base-sepolia`, `solana-devnet`) |
| `metadata` | `object` | Optional encrypted metadata |

#### Response

```
201 Created
```

```json
{
    "consentId": "0xabc123...",
    "chain": "sepolia",
    "status": "draft",
    "parties": ["0x...", "0x..."],
    "expiresAt": 1717000000,
    "txHash": "0x..."
}
```

### Get Consent

Retrieves consent details by ID.

```
GET /api/v1/consent/:id
```

#### Query Parameters

| Parameter | Type | Description |
|---|---|---|
| `chain` | `string` | Blockchain to query (default: `sepolia`) |

#### Response

```
200 OK
```

```json
{
    "consentId": "0xabc123...",
    "chain": "sepolia",
    "status": "active",
    "parties": ["0x...", "0x..."],
    "scopes": ["photography"],
    "startTime": 1714410000,
    "duration": 2592000,
    "expiresAt": 1717002000,
    "metadataHash": "0x..."
}
```

### Verify Consent

Verifies consent validity on-chain, optionally with a ZK proof.

```
POST /api/v1/consent/:id/verify
```

#### Request Body

```json
{
    "chain": "sepolia",
    "proof": "0x..."  // optional ZK proof
}
```

#### Response

```
200 OK
```

```json
{
    "consentId": "0xabc123...",
    "valid": true,
    "status": "active",
    "verifiedAt": 1714500000,
    "method": "onchain"  // or "zk_proof" if proof provided
}
```

### Revoke Consent

Revokes an active consent agreement. Any party may revoke.

```
POST /api/v1/consent/:id/revoke
```

#### Request Body

```json
{
    "chain": "sepolia",
    "reason": "scope-completed"  // optional
}
```

#### Response

```
200 OK
```

```json
{
    "consentId": "0xabc123...",
    "chain": "sepolia",
    "status": "revoked",
    "revokedBy": "0x...",
    "revokedAt": 1714500100,
    "txHash": "0x..."
}
```

### Generate ZK Proof

Generates a zero-knowledge proof for a consent.

```
POST /api/v1/consent/:id/proof
```

#### Request Body

```json
{
    "chain": "sepolia",
    "proofType": "consent-age-proof",
    "publicInputs": {
        "targetBlock": 18500000
    }
}
```

| Field | Type | Description |
|---|---|---|
| `proofType` | `string` | One of: `consent-age-proof`, `party-inclusion-proof`, `scope-inclusion-proof` |
| `publicInputs` | `object` | Public inputs for the proof (varies by proof type) |

#### Response

```
200 OK
```

```json
{
    "consentId": "0xabc123...",
    "proofType": "consent-age-proof",
    "proof": "0x...",
    "publicInputs": {
        "consentId": "0xabc123...",
        "targetBlock": 18500000
    },
    "circuitId": "consent-age-proof-v1"
}
```

### List Party Consents

Lists all consents for a given party address.

```
GET /api/v1/parties/:addr/consents
```

#### Query Parameters

| Parameter | Type | Description |
|---|---|---|
| `chain` | `string` | Blockchain to query (default: `sepolia`) |
| `status` | `string` | Filter by status: `active`, `expired`, `revoked`, `all` (default: `all`) |
| `limit` | `uint` | Max results (default: 20, max: 100) |
| `offset` | `uint` | Pagination offset |

#### Response

```
200 OK
```

```json
{
    "party": "0x...",
    "chain": "sepolia",
    "consents": [
        {
            "consentId": "0xabc123...",
            "status": "active",
            "otherParties": ["0x..."],
            "expiresAt": 1717002000
        }
    ],
    "total": 1
}
```

### Semantic Search

Searches consent records using vector similarity (Qdrant).

```
GET /api/v1/search
```

#### Query Parameters

| Parameter | Type | Description |
|---|---|---|
| `q` | `string` | Search query text |
| `chain` | `string` | Filter by chain |
| `limit` | `uint` | Max results (default: 10) |
| `threshold` | `float` | Similarity threshold 0-1 (default: 0.7) |

#### Response

```
200 OK
```

```json
{
    "query": "photography consent studio a",
    "results": [
        {
            "consentId": "0xabc123...",
            "chain": "sepolia",
            "score": 0.92,
            "status": "active"
        }
    ],
    "total": 1
}
```

### Health Check

```
GET /health
```

#### Response

```
200 OK
```

```json
{
    "status": "ok",
    "version": "1.0.0",
    "chains": {
        "sepolia": "healthy",
        "bsc-testnet": "healthy",
        "amoy": "degraded",
        "palm-testnet": "healthy",
        "base-sepolia": "healthy",
        "solana-devnet": "healthy"
    },
    "services": {
        "qdrant": "connected",
        "redis": "connected",
        "postgres": "connected"
    }
}
```

## Error Responses

### 400 Bad Request

```json
{
    "error": "validation_error",
    "message": "parties must contain at least 2 addresses",
    "details": {
        "field": "parties",
        "constraint": "min_items"
    }
}
```

### 401 Unauthorized

```json
{
    "error": "unauthorized",
    "message": "Missing or invalid authentication token"
}
```

### 404 Not Found

```json
{
    "error": "not_found",
    "message": "Consent 0xabc123... not found on chain sepolia"
}
```

### 409 Conflict

```json
{
    "error": "conflict",
    "message": "Consent is already revoked"
}
```

### 429 Rate Limited

```json
{
    "error": "rate_limited",
    "message": "Too many requests. Retry after 30 seconds"
}
```

### 500 Internal Server Error

```json
{
    "error": "internal_error",
    "message": "An unexpected error occurred"
}
```

## Rate Limiting

| Tier | Limit |
|---|---|
| Free Tier | 100 req/min |
| Pro Tier | 1000 req/min |
| Enterprise | Custom |

Rate limit headers are returned with every response:
- `X-RateLimit-Limit`
- `X-RateLimit-Remaining`
- `X-RateLimit-Reset`

## WebSocket Events

Connect to `/ws` for real-time consent events:

```json
{
    "type": "consent_created",
    "data": {
        "consentId": "0x...",
        "chain": "sepolia",
        "parties": ["0x..."]
    }
}
```

Event types: `consent_created`, `consent_signed`, `consent_revoked`, `consent_expired`, `proof_generated`.

## OpenAPI Spec

The full OpenAPI 3.0 specification is available at:

- `backend/go-api/api/openapi.yaml` (in-repo)
- `https://api.consent.example.com/openapi.json` (hosted)

## SDK / Client Libraries

- **JavaScript**: `packages/sdk/js/`
- **Python**: `packages/sdk/python/`
- **Go**: `backend/go-api/client/`
