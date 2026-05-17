import secrets
import time
import hashlib
from typing import List, Optional, Tuple


def generate_test_parties(count: int = 2) -> List[str]:
    """Generate test Ethereum addresses."""
    return [f'0x{secrets.token_hex(20)}' for _ in range(count)]


def generate_test_scopes() -> List[str]:
    """Return the standard set of test scopes."""
    return ['photo', 'video', 'audio', 'metadata', 'distribution']


def generate_consent_hash(parties: List[str], scopes: List[str],
                          valid_until: int) -> str:
    """Generate deterministic consent hash for test assertions."""
    data = ''.join(sorted(parties)) + ''.join(sorted(scopes)) + str(valid_until)
    return '0x' + hashlib.sha256(data.encode()).hexdigest()


def generate_invalid_signature() -> str:
    """Generate a random 65-byte invalid signature."""
    return '0x' + secrets.token_hex(65)


def generate_invalid_v_signature() -> str:
    """Generate signature with invalid v value (26, not 27 or 28)."""
    sig = bytearray(secrets.token_bytes(65))
    sig[64] = 26
    return '0x' + bytes(sig).hex()


def tamper_signature(signature: str) -> str:
    """Flip bits in s-value to test signature malleability resistance."""
    sig_bytes = bytes.fromhex(signature.replace('0x', ''))
    if len(sig_bytes) != 65:
        return signature
    sig_list = list(sig_bytes)
    sig_list[32] = (sig_list[32] ^ 0xFF) & 0xFF
    return '0x' + bytes(sig_list).hex()


class test_data:
    """Robot Framework library for generating test data."""

    def generate_test_parties(self, count: int = 2) -> List[str]:
        return generate_test_parties(count)

    def generate_test_scopes(self) -> List[str]:
        return generate_test_scopes()

    def generate_consent_hash(self, parties: List[str], scopes: List[str],
                              valid_until: int) -> str:
        return generate_consent_hash(parties, scopes, valid_until)

    def generate_invalid_signature(self) -> str:
        return generate_invalid_signature()

    def generate_invalid_v_signature(self) -> str:
        return generate_invalid_v_signature()

    def tamper_signature(self, signature: str) -> str:
        return tamper_signature(signature)

    def generate_consent_payload(self, party_a: str, party_b: str,
                                  scopes: Optional[List[str]] = None,
                                  duration: int = 86400) -> dict:
        """Generate a complete consent payload with timestamps."""
        if scopes is None:
            scopes = ['photo']
        now = int(time.time())
        return {
            'parties': [party_a, party_b],
            'scopes': scopes,
            'validFrom': now + 10,
            'validUntil': now + duration,
            'encryptedMetadataUri': '',
        }

    def generate_duplicate_payload(self, payload: dict) -> dict:
        """Generate an identical payload for replay testing."""
        return dict(payload)
