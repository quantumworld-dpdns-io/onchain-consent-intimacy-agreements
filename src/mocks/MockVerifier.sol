// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IConsentVerifier} from "../interfaces/IConsentVerifier.sol";

contract MockVerifier is IConsentVerifier {
    mapping(bytes32 => bool) private usedProofHashes;
    mapping(bytes32 => bytes32[]) private consentProofs;

    function verifyConsentAgeProof(
        bytes32 _consentId,
        bytes calldata _proof,
        uint256[] calldata _publicInputs
    ) external override returns (bool) {
        if (_proof.length == 0) revert("MockVerifier: empty proof");
        if (_publicInputs.length == 0) revert("MockVerifier: empty public inputs");
        for (uint256 i = 0; i < _publicInputs.length; i++) {
            if (_publicInputs[i] == 0) revert("MockVerifier: zero public input");
        }
        bytes32 proofHash = keccak256(abi.encodePacked(_consentId, "age", _proof, _publicInputs));
        if (usedProofHashes[proofHash]) revert ProofAlreadyUsed(proofHash);
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
        if (_proof.length == 0) revert("MockVerifier: empty proof");
        if (_publicInputs.length == 0) revert("MockVerifier: empty public inputs");
        for (uint256 i = 0; i < _publicInputs.length; i++) {
            if (_publicInputs[i] == 0) revert("MockVerifier: zero public input");
        }
        bytes32 proofHash = keccak256(abi.encodePacked(_consentId, "party", _proof, _publicInputs));
        if (usedProofHashes[proofHash]) revert ProofAlreadyUsed(proofHash);
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
        if (_proof.length == 0) revert("MockVerifier: empty proof");
        if (_publicInputs.length == 0) revert("MockVerifier: empty public inputs");
        for (uint256 i = 0; i < _publicInputs.length; i++) {
            if (_publicInputs[i] == 0) revert("MockVerifier: zero public input");
        }
        bytes32 proofHash = keccak256(abi.encodePacked(_consentId, "scope", _proof, _publicInputs));
        if (usedProofHashes[proofHash]) revert ProofAlreadyUsed(proofHash);
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
}
