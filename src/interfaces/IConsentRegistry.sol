// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ConsentLib} from "../libraries/ConsentLib.sol";

interface IConsentRegistry {
    event ConsentRegistered(bytes32 indexed consentId, address[] parties, uint256 validFrom, uint256 validUntil);
    event ConsentRevoked(bytes32 indexed consentId, address indexed revokedBy);
    event ConsentExpired(bytes32 indexed consentId);
    event ConsentUpdated(bytes32 indexed consentId, uint256 newValidUntil, string newMetadataUri);

    function registerConsent(
        ConsentLib.Consent calldata _consent,
        bytes[] calldata _signatures
    ) external returns (bytes32 consentId);

    function revokeConsent(bytes32 _consentId) external;

    function updateConsent(
        bytes32 _consentId,
        uint256 _newValidUntil,
        string calldata _newMetadataUri,
        bytes[] calldata _signatures
    ) external;

    function getConsent(bytes32 _consentId) external view returns (ConsentLib.Consent memory);

    function isConsentValid(bytes32 _consentId) external view returns (bool);

    function getPartyConsents(address _party) external view returns (bytes32[] memory);

    function getConsentsBatch(bytes32[] calldata _consentIds) external view returns (ConsentLib.Consent[] memory);

    function areConsentsValid(bytes32[] calldata _consentIds) external view returns (bool[] memory);

    function getActiveConsentsForParty(address _party) external view returns (bytes32[] memory);

    function getConsentCount() external view returns (uint256);
}
