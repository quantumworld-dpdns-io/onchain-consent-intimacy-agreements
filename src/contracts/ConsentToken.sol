// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IConsentToken} from "../interfaces/IConsentToken.sol";

contract ConsentToken is IConsentToken, ERC1155URIStorage, ReentrancyGuard {
    string private constant BASE_URI = "https://consent.protocol/metadata/";

    uint256 private nextTokenId;
    uint256 private totalMinted;

    mapping(bytes32 => uint256) private consentTokenIds;
    mapping(uint256 => bytes32) private tokenConsentIds;
    mapping(bytes32 => bool) private consentHasToken;
    mapping(bytes32 => string) private consentURIs;

    constructor() ERC1155(BASE_URI) {
        nextTokenId = 1;
    }

    function mintConsentReceipt(
        address[] calldata _parties,
        bytes32 _consentId,
        string calldata _uri
    ) external nonReentrant override returns (uint256 tokenId) {
        if (_parties.length == 0) revert("ConsentToken: no parties");
        if (consentHasToken[_consentId]) revert("ConsentToken: receipt already minted");

        tokenId = nextTokenId;
        nextTokenId++;
        totalMinted++;

        consentTokenIds[_consentId] = tokenId;
        tokenConsentIds[tokenId] = _consentId;
        consentHasToken[_consentId] = true;
        consentURIs[_consentId] = _uri;

        _setURI(tokenId, _uri);

        uint256[] memory ids = new uint256[](_parties.length);
        uint256[] amounts = new uint256[](_parties.length);

        for (uint256 i = 0; i < _parties.length; i++) {
            ids[i] = tokenId;
            amounts[i] = 1;
        }

        _mintBatch(_parties, ids, amounts, "");

        emit ConsentReceiptMinted(_consentId, _parties, tokenId);
    }

    function burnConsentReceipt(bytes32 _consentId) external nonReentrant override {
        if (!consentHasToken[_consentId]) revert("ConsentToken: no receipt minted");

        uint256 tokenId = consentTokenIds[_consentId];

        _burn(address(this), tokenId, 0);

        delete consentTokenIds[_consentId];
        delete tokenConsentIds[tokenId];
        delete consentHasToken[_consentId];
        delete consentURIs[_consentId];

        emit ConsentReceiptBurned(_consentId, tokenId);
    }

    function getConsentTokenId(bytes32 _consentId) external view override returns (uint256) {
        if (!consentHasToken[_consentId]) revert("ConsentToken: no receipt minted");
        return consentTokenIds[_consentId];
    }

    function getTokenConsentId(uint256 _tokenId) external view override returns (bytes32) {
        bytes32 consentId = tokenConsentIds[_tokenId];
        if (consentId == bytes32(0)) revert("ConsentToken: token does not exist");
        return consentId;
    }

    function getConsentTokenURI(bytes32 _consentId) external view override returns (string memory) {
        if (!consentHasToken[_consentId]) revert("ConsentToken: no receipt minted");
        return consentURIs[_consentId];
    }

    function balanceOfParty(bytes32 _consentId, address _party) external view override returns (uint256) {
        if (!consentHasToken[_consentId]) return 0;
        uint256 tokenId = consentTokenIds[_consentId];
        return balanceOf(_party, tokenId);
    }

    function isReceiptActive(bytes32 _consentId) external view override returns (bool) {
        return consentHasToken[_consentId];
    }

    function name() public pure returns (string memory) {
        return "ConsentReceiptToken";
    }

    function symbol() public pure returns (string memory) {
        return "CRT";
    }

    function getNextTokenId() external view returns (uint256) {
        return nextTokenId;
    }

    function getTotalMinted() external view returns (uint256) {
        return totalMinted;
    }
}
