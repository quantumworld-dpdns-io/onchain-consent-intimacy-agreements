// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IConsentToken {
    event ConsentReceiptMinted(bytes32 indexed consentId, address[] parties, uint256 tokenId);
    event ConsentReceiptBurned(bytes32 indexed consentId, uint256 tokenId);

    function mintConsentReceipt(
        address[] calldata _parties,
        bytes32 _consentId,
        string calldata _uri
    ) external returns (uint256 tokenId);

    function burnConsentReceipt(bytes32 _consentId) external;

    function getConsentTokenId(bytes32 _consentId) external view returns (uint256);

    function getTokenConsentId(uint256 _tokenId) external view returns (bytes32);

    function getConsentTokenURI(bytes32 _consentId) external view returns (string memory);

    function balanceOfParty(bytes32 _consentId, address _party) external view returns (uint256);

    function isReceiptActive(bytes32 _consentId) external view returns (bool);
}
