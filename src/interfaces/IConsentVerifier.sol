// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IConsentVerifier {
    event ProofVerified(bytes32 indexed consentId, string proofType, bytes32 proofHash);
    event ProofReplayAttempt(bytes32 indexed consentId, bytes32 proofHash);

    error ProofAlreadyUsed(bytes32 proofHash);
    error InvalidProof(bytes32 consentId, string reason);

    function verifyConsentAgeProof(
        bytes32 _consentId,
        bytes calldata _proof,
        uint256[] calldata _publicInputs
    ) external returns (bool);

    function verifyPartyInclusionProof(
        bytes32 _consentId,
        bytes calldata _proof,
        uint256[] calldata _publicInputs
    ) external returns (bool);

    function verifyScopeInclusionProof(
        bytes32 _consentId,
        bytes calldata _proof,
        uint256[] calldata _publicInputs
    ) external returns (bool);

    function isProofUsed(bytes32 _proofHash) external view returns (bool);

    function getUsedProofs(bytes32 _consentId) external view returns (bytes32[] memory);
}
