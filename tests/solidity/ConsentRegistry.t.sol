// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {ConsentRegistry} from "../../src/contracts/ConsentRegistry.sol";
import {ConsentLib} from "../../src/libraries/ConsentLib.sol";

contract ConsentRegistryTest is Test {
    using ConsentLib for ConsentLib.Consent;

    bytes32 constant CONSENT_TYPEHASH = keccak256(
        "Consent(address[] parties,bytes32[] scopes,uint256 validFrom,uint256 validUntil,string encryptedMetadataUri)"
    );

    ConsentRegistry public registry;

    uint256 public alicePk = 0xA11CE;
    uint256 public bobPk = 0xB0B;
    uint256 public charliePk = 0xC0C;

    address public alice;
    address public bob;
    address public charlie;

    bytes32 constant SCOPE_1 = keccak256("intimacy");
    bytes32 constant SCOPE_2 = keccak256("photographs");

    event ConsentRegistered(
        bytes32 indexed consentId, address[] parties, uint256 validFrom, uint256 validUntil
    );
    event ConsentRevoked(bytes32 indexed consentId, address indexed revokedBy);
    event ConsentUpdated(bytes32 indexed consentId, uint256 newValidUntil, string newMetadataUri);

    function setUp() public {
        alice = vm.addr(alicePk);
        bob = vm.addr(bobPk);
        charlie = vm.addr(charliePk);

        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(charlie, 10 ether);

        registry = new ConsentRegistry();
    }

    function _buildConsent(
        address[] memory _parties,
        bytes32[] memory _scopes,
        uint256 _validFrom,
        uint256 _validUntil,
        string memory _uri
    ) internal pure returns (ConsentLib.Consent memory) {
        return ConsentLib.Consent({
            id: bytes32(0),
            parties: _parties,
            scopes: _scopes,
            validFrom: _validFrom,
            validUntil: _validUntil,
            revoked: false,
            encryptedMetadataUri: _uri,
            createdAt: 0
        });
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

    function _signConsentMulti(
        ConsentLib.Consent memory _consent,
        uint256[] memory _privateKeys,
        bytes32 _domainSeparator
    ) internal returns (bytes[] memory) {
        bytes[] memory sigs = new bytes[](_privateKeys.length);
        for (uint256 i = 0; i < _privateKeys.length; i++) {
            sigs[i] = _signConsent(_consent, _privateKeys[i], _domainSeparator);
        }
        return sigs;
    }

    function test_RegisterConsent_Success() public {
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes32[] memory scopes = new bytes32[](1);
        scopes[0] = SCOPE_1;

        uint256 validFrom = block.timestamp;
        uint256 validUntil = block.timestamp + 7 days;

        ConsentLib.Consent memory consent = _buildConsent(parties, scopes, validFrom, validUntil, "ipfs://test");

        uint256[] memory pks = new uint256[](2);
        pks[0] = alicePk;
        pks[1] = bobPk;

        bytes32 domainSep = registry.getDomainSeparator();
        bytes[] memory sigs = _signConsentMulti(consent, pks, domainSep);

        vm.expectEmit(true, true, true, true);
        emit ConsentRegistered(
            keccak256(abi.encode(parties, scopes, validFrom, validUntil, "ipfs://test")),
            parties,
            validFrom,
            validUntil
        );

        bytes32 consentId = registry.registerConsent(consent, sigs);

        assertTrue(consentId != bytes32(0), "consentId should not be zero");
        assertEq(registry.getConsentCount(), 1, "consent count should be 1");

        ConsentLib.Consent memory stored = registry.getConsent(consentId);
        assertEq(stored.parties.length, 2, "should have 2 parties");
        assertEq(stored.parties[0], alice, "party 0 should be alice");
        assertEq(stored.parties[1], bob, "party 1 should be bob");
        assertEq(stored.validFrom, validFrom, "validFrom should match");
        assertEq(stored.validUntil, validUntil, "validUntil should match");
        assertFalse(stored.revoked, "should not be revoked");
    }

    function test_RevokeConsent_Success() public {
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes32[] memory scopes = new bytes32[](1);
        scopes[0] = SCOPE_1;

        uint256 validFrom = block.timestamp;
        uint256 validUntil = block.timestamp + 7 days;

        ConsentLib.Consent memory consent = _buildConsent(parties, scopes, validFrom, validUntil, "ipfs://test");

        uint256[] memory pks = new uint256[](2);
        pks[0] = alicePk;
        pks[1] = bobPk;

        bytes32 domainSep = registry.getDomainSeparator();
        bytes[] memory sigs = _signConsentMulti(consent, pks, domainSep);

        bytes32 consentId = registry.registerConsent(consent, sigs);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ConsentRevoked(consentId, alice);
        registry.revokeConsent(consentId);

        ConsentLib.Consent memory stored = registry.getConsent(consentId);
        assertTrue(stored.revoked, "consent should be revoked");
    }

    function test_IsConsentValid_ReturnsTrueForActive() public {
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes32[] memory scopes = new bytes32[](1);
        scopes[0] = SCOPE_1;

        uint256 validFrom = block.timestamp;
        uint256 validUntil = block.timestamp + 7 days;

        ConsentLib.Consent memory consent = _buildConsent(parties, scopes, validFrom, validUntil, "ipfs://test");

        uint256[] memory pks = new uint256[](2);
        pks[0] = alicePk;
        pks[1] = bobPk;

        bytes32 domainSep = registry.getDomainSeparator();
        bytes[] memory sigs = _signConsentMulti(consent, pks, domainSep);

        bytes32 consentId = registry.registerConsent(consent, sigs);

        bool valid = registry.isConsentValid(consentId);
        assertTrue(valid, "active consent should be valid");
    }

    function test_IsConsentValid_ReturnsFalseAfterRevocation() public {
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes32[] memory scopes = new bytes32[](1);
        scopes[0] = SCOPE_1;

        uint256 validFrom = block.timestamp;
        uint256 validUntil = block.timestamp + 7 days;

        ConsentLib.Consent memory consent = _buildConsent(parties, scopes, validFrom, validUntil, "ipfs://test");

        uint256[] memory pks = new uint256[](2);
        pks[0] = alicePk;
        pks[1] = bobPk;

        bytes32 domainSep = registry.getDomainSeparator();
        bytes[] memory sigs = _signConsentMulti(consent, pks, domainSep);

        bytes32 consentId = registry.registerConsent(consent, sigs);

        vm.prank(alice);
        registry.revokeConsent(consentId);

        bool valid = registry.isConsentValid(consentId);
        assertFalse(valid, "revoked consent should be invalid");
    }

    function test_IsConsentValid_ReturnsFalseAfterExpiration() public {
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes32[] memory scopes = new bytes32[](1);
        scopes[0] = SCOPE_1;

        uint256 validFrom = block.timestamp;
        uint256 validUntil = block.timestamp + 7 days;

        ConsentLib.Consent memory consent = _buildConsent(parties, scopes, validFrom, validUntil, "ipfs://test");

        uint256[] memory pks = new uint256[](2);
        pks[0] = alicePk;
        pks[1] = bobPk;

        bytes32 domainSep = registry.getDomainSeparator();
        bytes[] memory sigs = _signConsentMulti(consent, pks, domainSep);

        bytes32 consentId = registry.registerConsent(consent, sigs);

        vm.warp(validUntil + 1);

        bool valid = registry.isConsentValid(consentId);
        assertFalse(valid, "expired consent should be invalid");
    }

    function test_UnauthorizedPartyCannotRevoke() public {
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes32[] memory scopes = new bytes32[](1);
        scopes[0] = SCOPE_1;

        uint256 validFrom = block.timestamp;
        uint256 validUntil = block.timestamp + 7 days;

        ConsentLib.Consent memory consent = _buildConsent(parties, scopes, validFrom, validUntil, "ipfs://test");

        uint256[] memory pks = new uint256[](2);
        pks[0] = alicePk;
        pks[1] = bobPk;

        bytes32 domainSep = registry.getDomainSeparator();
        bytes[] memory sigs = _signConsentMulti(consent, pks, domainSep);

        bytes32 consentId = registry.registerConsent(consent, sigs);

        vm.prank(charlie);
        vm.expectRevert("ConsentRegistry: not a party");
        registry.revokeConsent(consentId);
    }

    function test_DoubleRevocationFails() public {
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes32[] memory scopes = new bytes32[](1);
        scopes[0] = SCOPE_1;

        uint256 validFrom = block.timestamp;
        uint256 validUntil = block.timestamp + 7 days;

        ConsentLib.Consent memory consent = _buildConsent(parties, scopes, validFrom, validUntil, "ipfs://test");

        uint256[] memory pks = new uint256[](2);
        pks[0] = alicePk;
        pks[1] = bobPk;

        bytes32 domainSep = registry.getDomainSeparator();
        bytes[] memory sigs = _signConsentMulti(consent, pks, domainSep);

        bytes32 consentId = registry.registerConsent(consent, sigs);

        vm.prank(alice);
        registry.revokeConsent(consentId);

        vm.prank(alice);
        vm.expectRevert("ConsentRegistry: already revoked");
        registry.revokeConsent(consentId);
    }

    function test_GetPartyConsents_ReturnsCorrectList() public {
        address[] memory partiesAB = new address[](2);
        partiesAB[0] = alice;
        partiesAB[1] = bob;

        address[] memory partiesAC = new address[](2);
        partiesAC[0] = alice;
        partiesAC[1] = charlie;

        bytes32[] memory scopes = new bytes32[](1);
        scopes[0] = SCOPE_1;

        uint256 validFrom = block.timestamp;
        uint256 validUntil = block.timestamp + 7 days;

        ConsentLib.Consent memory consent1 =
            _buildConsent(partiesAB, scopes, validFrom, validUntil, "ipfs://1");
        ConsentLib.Consent memory consent2 =
            _buildConsent(partiesAC, scopes, validFrom, validUntil, "ipfs://2");

        uint256[] memory pksAB = new uint256[](2);
        pksAB[0] = alicePk;
        pksAB[1] = bobPk;

        uint256[] memory pksAC = new uint256[](2);
        pksAC[0] = alicePk;
        pksAC[1] = charliePk;

        bytes32 domainSep = registry.getDomainSeparator();

        bytes32 id1 = registry.registerConsent(consent1, _signConsentMulti(consent1, pksAB, domainSep));
        bytes32 id2 = registry.registerConsent(consent2, _signConsentMulti(consent2, pksAC, domainSep));

        bytes32[] memory aliceConsents = registry.getPartyConsents(alice);
        assertEq(aliceConsents.length, 2, "alice should have 2 consents");
        assertTrue(
            aliceConsents[0] == id1 || aliceConsents[0] == id2, "alice should have both consents"
        );
        assertTrue(
            aliceConsents[1] == id1 || aliceConsents[1] == id2, "alice should have both consents"
        );

        bytes32[] memory bobConsents = registry.getPartyConsents(bob);
        assertEq(bobConsents.length, 1, "bob should have 1 consent");
        assertEq(bobConsents[0], id1, "bob should have consent1");
    }

    function test_BatchQueriesWork() public {
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes32[] memory scopes = new bytes32[](1);
        scopes[0] = SCOPE_1;

        uint256 validFrom = block.timestamp;
        uint256 validUntil = block.timestamp + 7 days;

        ConsentLib.Consent memory consent =
            _buildConsent(parties, scopes, validFrom, validUntil, "ipfs://test");

        uint256[] memory pks = new uint256[](2);
        pks[0] = alicePk;
        pks[1] = bobPk;

        bytes32 domainSep = registry.getDomainSeparator();
        bytes[] memory sigs = _signConsentMulti(consent, pks, domainSep);

        bytes32 consentId = registry.registerConsent(consent, sigs);

        bytes32[] memory ids = new bytes32[](2);
        ids[0] = consentId;
        ids[1] = keccak256("nonexistent");

        ConsentLib.Consent[] memory batch = registry.getConsentsBatch(ids);
        assertEq(batch.length, 2, "batch should have 2 results");
        assertEq(batch[0].parties.length, 2, "first result should have parties");
        assertEq(batch[1].parties.length, 0, "nonexistent should have empty parties");

        bool[] memory validities = registry.areConsentsValid(ids);
        assertEq(validities.length, 2, "should have 2 validity results");
        assertTrue(validities[0], "registered consent should be valid");
        assertFalse(validities[1], "nonexistent consent should be invalid");
    }

    function test_RegisterConsent_Reverts_NoParties() public {
        address[] memory parties = new address[](0);
        bytes32[] memory scopes = new bytes32[](0);
        ConsentLib.Consent memory consent =
            _buildConsent(parties, scopes, block.timestamp, block.timestamp + 7 days, "ipfs://test");
        bytes[] memory sigs = new bytes[](0);

        vm.expectRevert("ConsentRegistry: no parties");
        registry.registerConsent(consent, sigs);
    }

    function test_RegisterConsent_Reverts_Duplicate() public {
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes32[] memory scopes = new bytes32[](1);
        scopes[0] = SCOPE_1;

        uint256 validFrom = block.timestamp;
        uint256 validUntil = block.timestamp + 7 days;

        ConsentLib.Consent memory consent =
            _buildConsent(parties, scopes, validFrom, validUntil, "ipfs://test");

        uint256[] memory pks = new uint256[](2);
        pks[0] = alicePk;
        pks[1] = bobPk;

        bytes32 domainSep = registry.getDomainSeparator();
        bytes[] memory sigs = _signConsentMulti(consent, pks, domainSep);

        registry.registerConsent(consent, sigs);

        ConsentLib.Consent memory consentDup =
            _buildConsent(parties, scopes, validFrom, validUntil, "ipfs://test");

        bytes[] memory sigsDup = _signConsentMulti(consentDup, pks, domainSep);

        vm.expectRevert("ConsentRegistry: consent already exists");
        registry.registerConsent(consentDup, sigsDup);
    }
}
