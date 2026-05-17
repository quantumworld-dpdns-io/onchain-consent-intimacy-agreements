// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {ConsentRegistry} from "../../../src/contracts/ConsentRegistry.sol";
import {ConsentToken} from "../../../src/contracts/ConsentToken.sol";
import {ConsentLib} from "../../../src/libraries/ConsentLib.sol";

contract ConsentFuzzTest is Test {
    using ConsentLib for ConsentLib.Consent;

    bytes32 constant CONSENT_TYPEHASH = keccak256(
        "Consent(address[] parties,bytes32[] scopes,uint256 validFrom,uint256 validUntil,string encryptedMetadataUri)"
    );

    ConsentRegistry public registry;
    ConsentToken public token;

    uint256 public alicePk = 0xA11CE;
    uint256 public bobPk = 0xB0B;
    address public alice;
    address public bob;

    function setUp() public {
        alice = vm.addr(alicePk);
        bob = vm.addr(bobPk);
        registry = new ConsentRegistry();
        token = new ConsentToken();
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function _hashConsent(ConsentLib.Consent memory _consent) internal pure returns (bytes32) {
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

    function _buildDigest(
        ConsentLib.Consent memory _consent,
        bytes32 _domainSeparator
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator, _hashConsent(_consent)));
    }

    function _signConsent(
        ConsentLib.Consent memory _consent,
        uint256 _privateKey,
        bytes32 _domainSeparator
    ) internal returns (bytes memory) {
        bytes32 digest = _buildDigest(_consent, _domainSeparator);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _buildConsent(
        address[] memory _parties,
        bytes32[] memory _scopes,
        uint256 _validFrom,
        uint256 _validUntil
    ) internal pure returns (ConsentLib.Consent memory) {
        return ConsentLib.Consent({
            id: bytes32(0),
            parties: _parties,
            scopes: _scopes,
            validFrom: _validFrom,
            validUntil: _validUntil,
            revoked: false,
            encryptedMetadataUri: "ipfs://fuzz-test",
            createdAt: 0
        });
    }

    function testFuzz_RegisterConsent(uint256 blockNumber, bytes32 salt) public {
        vm.assume(blockNumber > 0 && blockNumber < 1_000_000_000);
        vm.roll(blockNumber);

        bytes32 consentId = keccak256(abi.encodePacked(salt, blockNumber, alice, bob));
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes32[] memory scopes = new bytes32[](1);
        scopes[0] = keccak256(abi.encodePacked(salt));

        uint256 validFrom = block.timestamp;
        uint256 validUntil = block.timestamp + 7 days + (uint256(salt) % 365 days);

        vm.assume(validUntil > validFrom);

        ConsentLib.Consent memory consent =
            _buildConsent(parties, scopes, validFrom, validUntil);

        bytes32 domainSep = registry.getDomainSeparator();
        bytes memory sigA = _signConsent(consent, alicePk, domainSep);
        bytes memory sigB = _signConsent(consent, bobPk, domainSep);

        bytes[] memory sigs = new bytes[](2);
        sigs[0] = sigA;
        sigs[1] = sigB;

        bytes32 registeredId = registry.registerConsent(consent, sigs);

        ConsentLib.Consent memory stored = registry.getConsent(registeredId);
        assertTrue(registeredId != bytes32(0), "consent id should not be zero");
        assertEq(stored.parties.length, 2, "should have 2 parties");
        assertEq(stored.validFrom, validFrom, "validFrom should match");
        assertEq(stored.validUntil, validUntil, "validUntil should match");
        assertFalse(stored.revoked, "should not be revoked initially");

        bool valid = registry.isConsentValid(registeredId);
        assertTrue(valid, "freshly registered consent should be valid");
    }

    function testFuzz_RevokeConsent(address caller) public {
        vm.assume(caller != address(0));
        vm.assume(caller != address(registry));

        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes32[] memory scopes = new bytes32[](1);
        scopes[0] = keccak256("test-scope");

        uint256 validFrom = block.timestamp;
        uint256 validUntil = block.timestamp + 30 days;

        ConsentLib.Consent memory consent =
            _buildConsent(parties, scopes, validFrom, validUntil);

        bytes32 domainSep = registry.getDomainSeparator();
        bytes memory sigA = _signConsent(consent, alicePk, domainSep);
        bytes memory sigB = _signConsent(consent, bobPk, domainSep);

        bytes[] memory sigs = new bytes[](2);
        sigs[0] = sigA;
        sigs[1] = sigB;

        bytes32 consentId = registry.registerConsent(consent, sigs);

        bool callerIsParty = (caller == alice || caller == bob);

        vm.prank(caller);
        if (callerIsParty) {
            registry.revokeConsent(consentId);
            ConsentLib.Consent memory stored = registry.getConsent(consentId);
            assertTrue(stored.revoked, "consent should be revoked");
            assertFalse(registry.isConsentValid(consentId), "revoked consent should not be valid");
        } else {
            vm.expectRevert("ConsentRegistry: not a party");
            registry.revokeConsent(consentId);
        }
    }

    function testFuzz_ConsentExpiry(uint256 validDuration, uint256 timePassed) public {
        vm.assume(validDuration > 1 days && validDuration < 365 days);
        vm.assume(timePassed >= 0);

        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes32[] memory scopes = new bytes32[](1);
        scopes[0] = keccak256("expiry-test");

        uint256 validFrom = block.timestamp;
        uint256 validUntil = validFrom + validDuration;

        ConsentLib.Consent memory consent =
            _buildConsent(parties, scopes, validFrom, validUntil);

        bytes32 domainSep = registry.getDomainSeparator();
        bytes memory sigA = _signConsent(consent, alicePk, domainSep);
        bytes memory sigB = _signConsent(consent, bobPk, domainSep);

        bytes[] memory sigs = new bytes[](2);
        sigs[0] = sigA;
        sigs[1] = sigB;

        bytes32 consentId = registry.registerConsent(consent, sigs);

        vm.warp(block.timestamp + timePassed);

        bool shouldBeExpired = block.timestamp >= validUntil;
        bool isValid = registry.isConsentValid(consentId);

        if (shouldBeExpired) {
            assertFalse(isValid, "consent should be expired");
        } else {
            assertTrue(isValid, "consent should still be valid");
        }
    }

    function testFuzz_TokenLifecycle(uint256 salt) public {
        bytes32 consentId = keccak256(abi.encodePacked("fuzz-token", salt));

        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        string memory uri = string(abi.encodePacked("ipfs://fuzz-", vm.toString(salt)));

        uint256 tokenId = token.mintConsentReceipt(parties, consentId, uri);

        assertTrue(token.isReceiptActive(consentId), "receipt should be active");
        assertEq(token.balanceOfParty(consentId, alice), 1, "alice should have token");
        assertEq(token.balanceOfParty(consentId, bob), 1, "bob should have token");

        string memory storedUri = token.getConsentTokenURI(consentId);
        assertEq(storedUri, uri, "URI should match");

        token.burnConsentReceipt(consentId);
        assertFalse(token.isReceiptActive(consentId), "receipt should be inactive after burn");
    }
}
