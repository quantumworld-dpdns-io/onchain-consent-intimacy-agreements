// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {ConsentToken} from "../../src/contracts/ConsentToken.sol";

contract ConsentTokenTest is Test {
    ConsentToken public token;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public charlie = address(0xC0C);

    bytes32 constant CONSENT_ID_1 = keccak256("consent-1");
    bytes32 constant CONSENT_ID_2 = keccak256("consent-2");

    string constant TEST_URI = "https://consent.protocol/metadata/1";

    event ConsentReceiptMinted(
        bytes32 indexed consentId, address[] parties, uint256 tokenId
    );
    event ConsentReceiptBurned(bytes32 indexed consentId, uint256 tokenId);

    function setUp() public {
        token = new ConsentToken();
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(charlie, 10 ether);
    }

    function _parties2() internal view returns (address[] memory) {
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;
        return parties;
    }

    function test_MintReceipt() public {
        address[] memory parties = _parties2();

        vm.expectEmit(true, true, true, true);
        emit ConsentReceiptMinted(CONSENT_ID_1, parties, 1);

        uint256 tokenId = token.mintConsentReceipt(parties, CONSENT_ID_1, TEST_URI);

        assertEq(tokenId, 1, "first token id should be 1");
        assertTrue(token.isReceiptActive(CONSENT_ID_1), "receipt should be active");
        assertEq(token.balanceOfParty(CONSENT_ID_1, alice), 1, "alice should have 1 token");
        assertEq(token.balanceOfParty(CONSENT_ID_1, bob), 1, "bob should have 1 token");
        assertEq(token.balanceOfParty(CONSENT_ID_1, charlie), 0, "charlie should have 0");
    }

    function test_BurnReceipt() public {
        address[] memory parties = _parties2();
        token.mintConsentReceipt(parties, CONSENT_ID_1, TEST_URI);

        vm.expectEmit(true, true, true, true);
        emit ConsentReceiptBurned(CONSENT_ID_1, 1);

        token.burnConsentReceipt(CONSENT_ID_1);

        assertFalse(token.isReceiptActive(CONSENT_ID_1), "receipt should be inactive after burn");
    }

    function test_BurnNonexistentReceipt_Reverts() public {
        vm.expectRevert("ConsentToken: no receipt minted");
        token.burnConsentReceipt(CONSENT_ID_1);
    }

    function test_DoubleMint_Reverts() public {
        address[] memory parties = _parties2();
        token.mintConsentReceipt(parties, CONSENT_ID_1, TEST_URI);

        vm.expectRevert("ConsentToken: receipt already minted");
        token.mintConsentReceipt(parties, CONSENT_ID_1, TEST_URI);
    }

    function test_TokenURIs() public {
        address[] memory parties = _parties2();
        string memory customUri = "https://example.com/metadata/token-42";

        token.mintConsentReceipt(parties, CONSENT_ID_1, customUri);

        string memory storedUri = token.getConsentTokenURI(CONSENT_ID_1);
        assertEq(storedUri, customUri, "URI should match");

        uint256 tokenId = token.getConsentTokenId(CONSENT_ID_1);
        assertEq(tokenId, 1, "token id should be 1");

        bytes32 consentId = token.getTokenConsentId(tokenId);
        assertEq(consentId, CONSENT_ID_1, "consent id should match");
    }

    function test_GetTokenConsentId_RevertsForNonexistent() public {
        vm.expectRevert("ConsentToken: no receipt minted");
        token.getConsentTokenId(CONSENT_ID_1);
    }

    function test_MultipleReceipts() public {
        address[] memory partiesA = new address[](1);
        partiesA[0] = alice;

        address[] memory partiesB = new address[](2);
        partiesB[0] = bob;
        partiesB[1] = charlie;

        token.mintConsentReceipt(partiesA, CONSENT_ID_1, "uri-1");
        token.mintConsentReceipt(partiesB, CONSENT_ID_2, "uri-2");

        assertEq(token.getNextTokenId(), 3, "next token id should be 3");
        assertEq(token.getTotalMinted(), 2, "total minted should be 2");

        assertEq(token.balanceOfParty(CONSENT_ID_1, alice), 1, "alice should have token 1");
        assertEq(token.balanceOfParty(CONSENT_ID_2, bob), 1, "bob should have token 2");
        assertEq(token.balanceOfParty(CONSENT_ID_2, charlie), 1, "charlie should have token 2");

        assertEq(token.getConsentTokenURI(CONSENT_ID_1), "uri-1");
        assertEq(token.getConsentTokenURI(CONSENT_ID_2), "uri-2");
    }

    function test_MintWithNoParties_Reverts() public {
        address[] memory noParties = new address[](0);
        vm.expectRevert("ConsentToken: no parties");
        token.mintConsentReceipt(noParties, CONSENT_ID_1, TEST_URI);
    }

    function test_BurnThenRemint() public {
        address[] memory parties = _parties2();
        token.mintConsentReceipt(parties, CONSENT_ID_1, TEST_URI);
        token.burnConsentReceipt(CONSENT_ID_1);

        token.mintConsentReceipt(parties, CONSENT_ID_1, "new-uri");

        assertTrue(token.isReceiptActive(CONSENT_ID_1), "receipt should be active after remint");
        assertEq(token.getConsentTokenURI(CONSENT_ID_1), "new-uri", "URI should be updated");
    }

    function test_NameAndSymbol() public {
        assertEq(token.name(), "ConsentReceiptToken", "name should match");
        assertEq(token.symbol(), "CRT", "symbol should match");
    }
}
