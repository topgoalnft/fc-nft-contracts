// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./IFcNFT.sol";

contract FcNFT is Initializable, ERC721Upgradeable, UUPSUpgradeable, OwnableUpgradeable, IFcNFT {

    event SetLogicAddrEvent(address addr);
    event SetDepositAddrEvent(address addr);
    event SetBaseURIEvent(string addr);
    event BurnEvent(uint256 _val);
    event MintFcNFT(
        address indexed owner,
        uint256 indexed tokenId,
        string itemId
    );
    event FcNFTDeposited(
        address indexed owner,
        address indexed depositAddress,
        uint256 tokenId
    );
    event FcNFTWithdrawn(
        address indexed owner,
        address indexed depositAddress,
        uint256 tokenId
    );
    event SetItemId(
        address indexed owner,
        address indexed operator,
        uint256 indexed tokenId,
        string fromItemId,
        string toItemId
    );

    string[] internal _itemIds;
    address internal logicContract;
    address internal depositAddress;
    string internal _baseTokenURI;
    mapping(uint256 => address) internal depositedFcNfts;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory name_, string memory symbol_) public initializer {
        __ERC721_init(name_, symbol_);
        __Ownable_init();
        __UUPSUpgradeable_init();
        depositAddress = _msgSender();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    modifier onlyLogic() {
        require(address(logicContract) != address(0), "Logic contract isn't set");
        require(logicContract == _msgSender(), "Only logic can call this function");
        _;
    }

    /**
     * @dev Set the address of the logic contract.
     */
    function setLogicContract(address addr) external onlyOwner {
        require(addr != address(0), "Logic address cannot be 0");
        logicContract = addr;
        emit SetLogicAddrEvent(addr);
    }

    function setDepositAddress(address addr) external onlyOwner {
        depositAddress = addr;
        emit SetDepositAddrEvent(addr);
    }

    function setBaseURI(string calldata value) external onlyOwner {
        _baseTokenURI = value;
        emit SetBaseURIEvent(value);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        string memory uri = super.tokenURI(tokenId);
        return string(abi.encodePacked(uri, "/", _itemIds[tokenId]));
    }

    function burnByLogic(uint256 tokenId) external onlyLogic {
        _burn(tokenId);
        emit BurnEvent(tokenId);
    }

    function burnByOwner(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
        emit BurnEvent(tokenId);
    }

    function _mintFcNFT(address owner, string memory itemId, bool safe) internal returns (uint256) {
        uint256 tokenId = _itemIds.length;
        require(tokenId == uint256(uint32(tokenId)), "Maximum token exceeded");
        _itemIds.push(itemId);
        if (safe) {
            _safeMint(owner, tokenId);
        } else {
            _mint(owner, tokenId);
        }
        emit MintFcNFT(owner, tokenId, itemId);
        return tokenId;
    }

    function exists(uint256 tokenId) external view override returns (bool) {
        return _exists(tokenId);
    }

    function getItemId(uint256 tokenId) external view returns (string memory) {
        return _itemIds[tokenId];
    }

    function mintFcNFTByLogic(address owner, string memory itemId, bool safe) external onlyLogic returns (uint256) {
        return _mintFcNFT(owner, itemId, safe);
    }

    function mintFcNFTByOwner(address owner, string memory itemId, bool safe) external onlyOwner returns (uint256) {
        return _mintFcNFT(owner, itemId, safe);
    }

    function _setItemId(uint256 tokenId, string memory itemId) internal {
        require(_exists(tokenId), "Token doesn't exist");
        string memory fromItemId = _itemIds[tokenId];
        _itemIds[tokenId] = itemId;
        emit SetItemId(ownerOf(tokenId), _msgSender(), tokenId, fromItemId, itemId);
    }

    function setItemIdByLogic(uint256 tokenId, string memory itemId) external onlyLogic {
        _setItemId(tokenId, itemId);
    }

    function setItemIdByOwner(uint256 tokenId, string memory itemId) external onlyOwner {
        _setItemId(tokenId, itemId);
    }

    function _afterTokenTransfer(address from, address to, uint256 firstTokenId, uint256) override internal {
        bool hasDeposited = depositedFcNfts[firstTokenId] != address(0);
        if (to == depositAddress) {
            if (!hasDeposited) {
                depositedFcNfts[firstTokenId] = from;
                emit FcNFTDeposited(from, depositAddress, firstTokenId);
            }
        } else if (hasDeposited) {
            delete depositedFcNfts[firstTokenId];
            emit FcNFTWithdrawn(to, from, firstTokenId);
        }
    }

    function getDepositAddress() external view returns (address) {
        return depositAddress;
    }

    function realOwnerOf(uint256 _tokenId) external view returns (address) {
        address owner = depositedFcNfts[_tokenId];
        if (owner != address(0)) {
            return owner;
        }
        return ownerOf(_tokenId);
    }

    function isDeposited(uint256 _tokenId) external view returns (bool) {
        return depositedFcNfts[_tokenId] != address(0);
    }
}