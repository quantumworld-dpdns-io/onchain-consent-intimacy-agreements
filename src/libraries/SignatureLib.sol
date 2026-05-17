// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ConsentLib} from "./ConsentLib.sol";

library SignatureLib {
    using ConsentLib for ConsentLib.Consent;

    bytes32 public constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    struct EIP712Domain {
        string name;
        string version;
        uint256 chainId;
        address verifyingContract;
    }

    function buildDomainSeparator(EIP712Domain memory _domain) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(_domain.name)),
                keccak256(bytes(_domain.version)),
                _domain.chainId,
                _domain.verifyingContract
            )
        );
    }

    function buildConsentDigest(
        bytes32 _domainSeparator,
        ConsentLib.Consent memory _consent
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparator,
                ConsentLib.hashConsent(_consent)
            )
        );
    }

    function verifyConsentSignature(
        bytes32 _domainSeparator,
        ConsentLib.Consent memory _consent,
        bytes memory _signature,
        address _expectedSigner
    ) internal pure returns (bool) {
        bytes32 digest = buildConsentDigest(_domainSeparator, _consent);
        address recovered = recoverSigner(digest, _signature);
        return recovered == _expectedSigner;
    }

    function verifyMultiSig(
        bytes32 _domainSeparator,
        ConsentLib.Consent memory _consent,
        bytes[] memory _signatures,
        address[] memory _expectedSigners
    ) internal pure returns (bool) {
        if (_signatures.length != _expectedSigners.length) return false;
        bytes32 digest = buildConsentDigest(_domainSeparator, _consent);
        for (uint256 i = 0; i < _signatures.length; i++) {
            address recovered = recoverSigner(digest, _signatures[i]);
            if (recovered != _expectedSigners[i]) return false;
        }
        return true;
    }

    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature) internal pure returns (address) {
        if (_signature.length != 65) revert("SignatureLib: invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(_signature, 0x20))
            s := mload(add(_signature, 0x40))
            v := byte(0, mload(add(_signature, 0x60)))
        }
        if (v < 27) v += 27;
        if (v != 27 && v != 28) revert("SignatureLib: invalid v value");
        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function aggregateSignatures(bytes[] memory _signatures) internal pure returns (bytes memory) {
        uint256 totalLength = 0;
        for (uint256 i = 0; i < _signatures.length; i++) {
            totalLength += _signatures[i].length;
        }
        bytes memory result = new bytes(totalLength);
        uint256 offset = 0;
        for (uint256 i = 0; i < _signatures.length; i++) {
            bytes memory sig = _signatures[i];
            for (uint256 j = 0; j < sig.length; j++) {
                result[offset + j] = sig[j];
            }
            offset += sig.length;
        }
        return result;
    }
}
