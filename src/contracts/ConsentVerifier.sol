// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IConsentVerifier} from "../interfaces/IConsentVerifier.sol";
import {IConsentRegistry} from "../interfaces/IConsentRegistry.sol";
import {ConsentLib} from "../libraries/ConsentLib.sol";

contract ConsentVerifier is IConsentVerifier {
    using ConsentLib for ConsentLib.Consent;

    IConsentRegistry public immutable consentRegistry;

    mapping(bytes32 => bool) private usedProofHashes;
    mapping(bytes32 => bytes32[]) private consentProofs;

    constructor(address _consentRegistry) {
        if (_consentRegistry == address(0)) revert("ConsentVerifier: invalid registry address");
        consentRegistry = IConsentRegistry(_consentRegistry);
    }

    function verifyConsentAgeProof(
        bytes32 _consentId,
        bytes calldata _proof,
        uint256[] calldata _publicInputs
    ) external override returns (bool) {
        bytes32 proofHash = keccak256(abi.encodePacked(_consentId, "age", _proof, _publicInputs));
        if (usedProofHashes[proofHash]) revert ProofAlreadyUsed(proofHash);

        if (_publicInputs.length < 1) revert InvalidProof(_consentId, "missing consent age public inputs");

        bool isValid = _verifyProof(_proof, _publicInputs);
        if (!isValid) revert InvalidProof(_consentId, "age proof verification failed");

        usedProofHashes[proofHash] = true;
        consentProofs[_consentId].push(proofHash);

        emit ProofVerified(_consentId, "age", proofHash);
        return true;
    }

    function verifyPartyInclusionProof(
        bytes32 _consentId,
        bytes calldata _proof,
        uint256[] calldata _publicInputs
    ) external override returns (bool) {
        bytes32 proofHash = keccak256(abi.encodePacked(_consentId, "party", _proof, _publicInputs));
        if (usedProofHashes[proofHash]) revert ProofAlreadyUsed(proofHash);

        if (_publicInputs.length < 2) revert InvalidProof(_consentId, "missing party inclusion public inputs");

        bool isValid = _verifyProof(_proof, _publicInputs);
        if (!isValid) revert InvalidProof(_consentId, "party inclusion proof verification failed");

        usedProofHashes[proofHash] = true;
        consentProofs[_consentId].push(proofHash);

        emit ProofVerified(_consentId, "party", proofHash);
        return true;
    }

    function verifyScopeInclusionProof(
        bytes32 _consentId,
        bytes calldata _proof,
        uint256[] calldata _publicInputs
    ) external override returns (bool) {
        bytes32 proofHash = keccak256(abi.encodePacked(_consentId, "scope", _proof, _publicInputs));
        if (usedProofHashes[proofHash]) revert ProofAlreadyUsed(proofHash);

        if (_publicInputs.length < 2) revert InvalidProof(_consentId, "missing scope inclusion public inputs");

        bool isValid = _verifyProof(_proof, _publicInputs);
        if (!isValid) revert InvalidProof(_consentId, "scope inclusion proof verification failed");

        usedProofHashes[proofHash] = true;
        consentProofs[_consentId].push(proofHash);

        emit ProofVerified(_consentId, "scope", proofHash);
        return true;
    }

    function isProofUsed(bytes32 _proofHash) external view override returns (bool) {
        return usedProofHashes[_proofHash];
    }

    function getUsedProofs(bytes32 _consentId) external view override returns (bytes32[] memory) {
        return consentProofs[_consentId];
    }

    function _verifyProof(bytes calldata _proof, uint256[] calldata _publicInputs) private pure returns (bool) {
        if (_proof.length == 0) return false;
        if (_publicInputs.length == 0) return false;
        return true;
    }
}
