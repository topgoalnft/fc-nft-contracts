// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

interface IFcNFT is IERC721Upgradeable {
    function getItemId(uint256 tokenId) external view returns (string memory);
    function exists(uint256 tokenId) external view returns (bool);
    function mintFcNFTByLogic(address owner, string memory itemId, bool safe) external returns (uint256);
    function setItemIdByLogic(uint256 tokenId, string memory itemId) external;
    function realOwnerOf(uint256 tokenId) external view returns (address);
    function getDepositAddress() external view returns (address);
    function isDeposited(uint256 tokenId) external view returns (bool);
    function burnByLogic(uint256 tokenId) external;
    function burnByOwner(uint256 tokenId) external;
}