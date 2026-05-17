// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ConsentLib} from "../libraries/ConsentLib.sol";
import {IConsentRegistry} from "../interfaces/IConsentRegistry.sol";

contract ConsentEscrow is ReentrancyGuard {
    using ConsentLib for ConsentLib.Consent;

    event EncryptionStored(bytes32 indexed consentId, address indexed storedBy, uint256 timestamp);
    event EncryptionAccessed(bytes32 indexed consentId, address indexed accessedBy, uint256 timestamp);

    IConsentRegistry public immutable consentRegistry;

    mapping(bytes32 => bytes) private encryptedData;
    mapping(bytes32 => bool) private hasEncryptedData;

    constructor(address _consentRegistry) {
        if (_consentRegistry == address(0)) revert("ConsentEscrow: invalid registry address");
        consentRegistry = IConsentRegistry(_consentRegistry);
    }

    function storeEncryptedData(bytes32 _consentId, bytes calldata _encryptedData) external nonReentrant {
        if (_encryptedData.length == 0) revert("ConsentEscrow: empty data");
        if (hasEncryptedData[_consentId]) revert("ConsentEscrow: data already stored for this consent");

        ConsentLib.Consent memory storedConsent = consentRegistry.getConsent(_consentId);
        if (!storedConsent.containsParty(msg.sender)) revert("ConsentEscrow: not a consent party");

        encryptedData[_consentId] = _encryptedData;
        hasEncryptedData[_consentId] = true;

        emit EncryptionStored(_consentId, msg.sender, block.timestamp);
    }

    function getEncryptedData(bytes32 _consentId) external view returns (bytes memory) {
        if (!hasEncryptedData[_consentId]) revert("ConsentEscrow: no data stored");

        ConsentLib.Consent memory storedConsent = consentRegistry.getConsent(_consentId);
        if (!storedConsent.containsParty(msg.sender)) revert("ConsentEscrow: not a consent party");

        return encryptedData[_consentId];
    }

    function hasData(bytes32 _consentId) external view returns (bool) {
        return hasEncryptedData[_consentId];
    }

    function getConsentDataSize(bytes32 _consentId) external view returns (uint256) {
        if (!hasEncryptedData[_consentId]) revert("ConsentEscrow: no data stored");
        ConsentLib.Consent memory storedConsent = consentRegistry.getConsent(_consentId);
        if (!storedConsent.containsParty(msg.sender)) revert("ConsentEscrow: not a consent party");
        return encryptedData[_consentId].length;
    }
}
