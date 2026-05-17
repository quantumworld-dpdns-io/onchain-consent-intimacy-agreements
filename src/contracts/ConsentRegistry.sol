// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ConsentLib} from "../libraries/ConsentLib.sol";
import {SignatureLib} from "../libraries/SignatureLib.sol";
import {IConsentRegistry} from "../interfaces/IConsentRegistry.sol";

contract ConsentRegistry is IConsentRegistry, ReentrancyGuard {
    using ConsentLib for ConsentLib.Consent;
    using SignatureLib for SignatureLib.EIP712Domain;

    bytes32 private constant VERSION_HASH = keccak256(bytes("1"));

    bytes32 private immutable DOMAIN_SEPARATOR;

    uint256 private consentCount;

    mapping(bytes32 => ConsentLib.Consent) private consents;
    mapping(bytes32 => bool) private consentExists;
    mapping(address => bytes32[]) private partyConsents;
    mapping(address => mapping(bytes32 => bool)) private partyConsentIndex;

    constructor() {
        DOMAIN_SEPARATOR = SignatureLib.buildDomainSeparator(
            SignatureLib.EIP712Domain({
                name: "ConsentRegistry",
                version: "1",
                chainId: block.chainid,
                verifyingContract: address(this)
            })
        );
    }

    function registerConsent(
        ConsentLib.Consent calldata _consent,
        bytes[] calldata _signatures
    ) external nonReentrant override returns (bytes32 consentId) {
        if (_consent.parties.length == 0) revert("ConsentRegistry: no parties");
        if (_signatures.length != _consent.parties.length) revert("ConsentRegistry: signature count mismatch");

        consentId = ConsentLib.computeConsentId(_consent);
        if (consentExists[consentId]) revert("ConsentRegistry: consent already exists");

        bool valid = SignatureLib.verifyMultiSig(
            DOMAIN_SEPARATOR,
            _consent,
            _signatures,
            _consent.parties
        );
        if (!valid) revert("ConsentRegistry: invalid signature(s)");

        ConsentLib.Consent memory storedConsent = ConsentLib.Consent({
            id: consentId,
            parties: _consent.parties,
            scopes: _consent.scopes,
            validFrom: _consent.validFrom,
            validUntil: _consent.validUntil,
            revoked: false,
            encryptedMetadataUri: _consent.encryptedMetadataUri,
            createdAt: block.timestamp
        });

        consents[consentId] = storedConsent;
        consentExists[consentId] = true;
        consentCount++;

        for (uint256 i = 0; i < _consent.parties.length; i++) {
            if (!partyConsentIndex[_consent.parties[i]][consentId]) {
                partyConsents[_consent.parties[i]].push(consentId);
                partyConsentIndex[_consent.parties[i]][consentId] = true;
            }
        }

        emit ConsentRegistered(consentId, _consent.parties, _consent.validFrom, _consent.validUntil);
    }

    function revokeConsent(bytes32 _consentId) external nonReentrant override {
        if (!consentExists[_consentId]) revert("ConsentRegistry: consent does not exist");
        ConsentLib.Consent storage storedConsent = consents[_consentId];
        if (storedConsent.revoked) revert("ConsentRegistry: already revoked");

        bool isParty = false;
        for (uint256 i = 0; i < storedConsent.parties.length; i++) {
            if (storedConsent.parties[i] == msg.sender) {
                isParty = true;
                break;
            }
        }
        if (!isParty) revert("ConsentRegistry: not a party");

        storedConsent.revoked = true;
        emit ConsentRevoked(_consentId, msg.sender);
    }

    function updateConsent(
        bytes32 _consentId,
        uint256 _newValidUntil,
        string calldata _newMetadataUri,
        bytes[] calldata _signatures
    ) external nonReentrant override {
        if (!consentExists[_consentId]) revert("ConsentRegistry: consent does not exist");
        ConsentLib.Consent storage storedConsent = consents[_consentId];
        ConsentLib.Consent memory currentConsent = storedConsent;

        ConsentLib.Consent memory updatedConsent = ConsentLib.Consent({
            id: currentConsent.id,
            parties: currentConsent.parties,
            scopes: currentConsent.scopes,
            validFrom: currentConsent.validFrom,
            validUntil: _newValidUntil,
            revoked: currentConsent.revoked,
            encryptedMetadataUri: _newMetadataUri,
            createdAt: currentConsent.createdAt
        });

        if (!updatedConsent.validateConsent()) revert("ConsentRegistry: invalid consent parameters");

        if (_signatures.length != currentConsent.parties.length) revert("ConsentRegistry: signature count mismatch");

        bool valid = SignatureLib.verifyMultiSig(
            DOMAIN_SEPARATOR,
            updatedConsent,
            _signatures,
            currentConsent.parties
        );
        if (!valid) revert("ConsentRegistry: invalid signature(s)");

        storedConsent.validUntil = _newValidUntil;
        storedConsent.encryptedMetadataUri = _newMetadataUri;

        emit ConsentUpdated(_consentId, _newValidUntil, _newMetadataUri);
    }

    function getConsent(bytes32 _consentId) external view override returns (ConsentLib.Consent memory) {
        if (!consentExists[_consentId]) revert("ConsentRegistry: consent does not exist");
        return consents[_consentId];
    }

    function isConsentValid(bytes32 _consentId) external view override returns (bool) {
        if (!consentExists[_consentId]) return false;
        ConsentLib.Consent memory storedConsent = consents[_consentId];
        if (storedConsent.revoked) return false;
        if (block.timestamp < storedConsent.validFrom) return false;
        if (block.timestamp >= storedConsent.validUntil) {
            return false;
        }
        return true;
    }

    function getPartyConsents(address _party) external view override returns (bytes32[] memory) {
        return partyConsents[_party];
    }

    function getConsentsBatch(bytes32[] calldata _consentIds) external view override returns (ConsentLib.Consent[] memory) {
        ConsentLib.Consent[] memory results = new ConsentLib.Consent[](_consentIds.length);
        for (uint256 i = 0; i < _consentIds.length; i++) {
            if (consentExists[_consentIds[i]]) {
                results[i] = consents[_consentIds[i]];
            }
        }
        return results;
    }

    function areConsentsValid(bytes32[] calldata _consentIds) external view override returns (bool[] memory) {
        bool[] memory results = new bool[](_consentIds.length);
        for (uint256 i = 0; i < _consentIds.length; i++) {
            results[i] = _isConsentValid(_consentIds[i]);
        }
        return results;
    }

    function getActiveConsentsForParty(address _party) external view override returns (bytes32[] memory) {
        bytes32[] memory allConsents = partyConsents[_party];
        uint256 activeCount = 0;
        for (uint256 i = 0; i < allConsents.length; i++) {
            if (_isConsentValid(allConsents[i])) {
                activeCount++;
            }
        }
        bytes32[] memory active = new bytes32[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allConsents.length; i++) {
            if (_isConsentValid(allConsents[i])) {
                active[index] = allConsents[i];
                index++;
            }
        }
        return active;
    }

    function getConsentCount() external view override returns (uint256) {
        return consentCount;
    }

    function _isConsentValid(bytes32 _consentId) private view returns (bool) {
        if (!consentExists[_consentId]) return false;
        ConsentLib.Consent memory storedConsent = consents[_consentId];
        if (storedConsent.revoked) return false;
        if (block.timestamp < storedConsent.validFrom) return false;
        if (block.timestamp >= storedConsent.validUntil) return false;
        return true;
    }

    function getDomainSeparator() external view returns (bytes32) {
        return DOMAIN_SEPARATOR;
    }
}
