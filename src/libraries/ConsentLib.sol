// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

library ConsentLib {
    struct Consent {
        bytes32 id;
        address[] parties;
        bytes32[] scopes;
        uint256 validFrom;
        uint256 validUntil;
        bool revoked;
        string encryptedMetadataUri;
        uint256 createdAt;
    }

    bytes32 public constant CONSENT_TYPEHASH = keccak256(
        "Consent(address[] parties,bytes32[] scopes,uint256 validFrom,uint256 validUntil,string encryptedMetadataUri)"
    );

    function hashConsent(Consent memory _consent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CONSENT_TYPEHASH,
                keccak256(abi.encodePacked(_consent.parties)),
                keccak256(abi.encodePacked(_consent.scopes)),
                _consent.validFrom,
                _consent.validUntil,
                keccak256(bytes(_consent.encryptedMetadataUri))
            )
        );
    }

    function computeConsentId(Consent memory _consent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _consent.parties,
                _consent.scopes,
                _consent.validFrom,
                _consent.validUntil,
                _consent.encryptedMetadataUri
            )
        );
    }

    function validateConsent(Consent memory _consent) internal pure returns (bool) {
        if (_consent.parties.length < 1) return false;
        if (_consent.validFrom == 0) return false;
        if (_consent.validUntil <= _consent.validFrom) return false;
        if (_consent.validUntil <= block.timestamp) return false;
        return true;
    }

    function isConsentActive(Consent memory _consent) internal view returns (bool) {
        if (_consent.revoked) return false;
        if (block.timestamp < _consent.validFrom) return false;
        if (block.timestamp >= _consent.validUntil) return false;
        return true;
    }

    function containsParty(Consent memory _consent, address _party) internal pure returns (bool) {
        for (uint256 i = 0; i < _consent.parties.length; i++) {
            if (_consent.parties[i] == _party) return true;
        }
        return false;
    }

    function containsScope(Consent memory _consent, bytes32 _scope) internal pure returns (bool) {
        for (uint256 i = 0; i < _consent.scopes.length; i++) {
            if (_consent.scopes[i] == _scope) return true;
        }
        return false;
    }
}
