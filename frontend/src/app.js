const API_BASE = process.env.API_URL || 'http://localhost:8080';

async function createConsent(parties, scopes, duration, chain) {
    const response = await fetch(`${API_BASE}/api/v1/consent`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ parties, scopes, duration, chain })
    });
    return response.json();
}

async function verifyConsent(consentId, chain) {
    const response = await fetch(`${API_BASE}/api/v1/consent/${consentId}/verify?chain=${chain}`);
    return response.json();
}

async function revokeConsent(consentId, chain) {
    const response = await fetch(`${API_BASE}/api/v1/consent/${consentId}/revoke`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ chain })
    });
    return response.json();
}

// Export for module bundler
if (typeof module !== 'undefined') {
    module.exports = { createConsent, verifyConsent, revokeConsent };
}
