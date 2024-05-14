// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./IFcNFT.sol";

contract FcNFTLogic is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    event SetSignerEvent(address signer);
    event SetAdminEvent(address admin);
    event EmergencyWithdrawn(address indexed to, address indexed token, uint256 amount);
    event OrderPaymentEvent(
        address indexed tokenAddress,
        uint256 indexed orderId,
        address indexed userAddress,
        uint256 amount
    );
    event FcNFTMintEvent(
        uint256 orderId,
        uint256[] tokenIds
    );
    event FcNFTSetItemIdEvent(
        uint256 orderId
    );
    event FcNFTWithdrawnEvent(
        uint256 orderId
    );
    event FusionPayEvent(
        uint256 orderId
    );
    event FusionFcNFTEvent(
        uint256 orderId,
        uint256[] tokenIds
    );

    struct PayInfo {
        address tokenAddress;
        uint256 amount;
        uint256 orderId;
    }
    struct TokenReward {
        address token;
        uint256 amount;
    }
    struct BatchMintFcNFT {
        address nft;
        string itemId;
        address owner;
        uint32 count;
        bool safe;
    }
    struct FusionNFT {
        address nft;
        uint256 tokenId;
    }
    struct FusionMintItem {
        address nft;
        string itemId;
    }

    address internal signer;
    address internal admin;
    mapping(bytes => bool) internal signUsed;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        signer = _msgSender();
    }

    modifier onlyOwnerOrAdmin() {
        require(
            (owner() == _msgSender() || admin == _msgSender()),
            "Caller is not the owner or admins"
        );
        _;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function setSigner(address addr) external onlyOwner {
        signer = addr;
        emit SetSignerEvent(addr);
    }

    function setAdmin(address addr) external onlyOwner {
        require(addr != address(0), "admin address should not be 0");
        admin = addr;
        emit SetAdminEvent(addr);
    }

    function _transferToken(address token, address to, uint256 amount) internal {
        require(to != address(0), "To address should not be 0");
        if (token == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    // Emergency withdrawal
    function emergencyWithdraw(address token, address to,  uint256 amount) external onlyOwner {
        _transferToken(token, to, amount);
        emit EmergencyWithdrawn(to, token, amount);
    }

    function payToken(address tokenAddr, uint256 amount, uint256 orderId) public payable virtual {
        require(amount > 0, "You need pay some token");
        if (tokenAddr == address(0)) {
            payMainToken(amount, orderId);
        } else {
            payErc20Token(tokenAddr, amount, orderId);
        }
    }

    function payMainToken(uint256 amount, uint256 orderId) public payable virtual {
        require(msg.value >= amount, "You don't pay enough main token");
        emit OrderPaymentEvent(address(0), orderId, _msgSender(), amount);
    }

    function payErc20Token(address tokenAddr, uint256 amount, uint256 orderId) internal virtual {
        IERC20 tokenContract = IERC20(tokenAddr);
        uint256 allowance = tokenContract.allowance(_msgSender(), address(this));
        require(allowance >= amount, "Check the token allowance");
        tokenContract.safeTransferFrom(_msgSender(), address(this), amount);
        emit OrderPaymentEvent(tokenAddr, orderId, _msgSender(), amount);
    }

    function encodePayInfo(PayInfo calldata payInfo) internal pure returns (bytes memory) {
        return abi.encodePacked(
            payInfo.tokenAddress,
            payInfo.amount,
            payInfo.orderId
        );
    }

    function encodeTokenRewards(TokenReward[] calldata rewards) internal pure returns (bytes memory) {
        return abi.encode(rewards);
    }

    function verifySign(bytes memory sign, bytes32 msgHash) internal {
        address recoveredSigner = ECDSA.recover(msgHash, sign);
        require(
            recoveredSigner != address(0) && recoveredSigner == signer,
            "Invalid Signer!"
        );
        signUsed[sign] = true;
    }

    function mintFcNft(
        address nft,
        string memory itemId,
        uint32 count,
        address owner,
        TokenReward[] calldata rewards,
        bool safe,
        PayInfo calldata payInfo,
        bytes memory sign) external payable {
        require(signUsed[sign] != true, "This signature already be used");
        bytes32 msgHash = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    nft,
                    itemId,
                    count,
                    owner,
                    encodeTokenRewards(rewards),
                    encodePayInfo(payInfo),
                    block.chainid,
                    address(this)
                )
            )
        );
        verifySign(sign, msgHash);
        if (payInfo.amount > 0) {
            payToken(payInfo.tokenAddress, payInfo.amount, payInfo.orderId);
        }
        uint256[] memory tokenIds = new uint256[](count);
        for (uint32 i = 0; i < count; i++) {
            tokenIds[i] = IFcNFT(nft).mintFcNFTByLogic(owner, itemId, safe);
        }
        if (rewards.length > 0) {
            for (uint32 i = 0; i < rewards.length; i++) {
                _transferToken(rewards[i].token, owner, rewards[i].amount);
            }
        }
        emit FcNFTMintEvent(payInfo.orderId, tokenIds);
    }

    function batchMintFcNft(BatchMintFcNFT[] calldata nfts) external onlyOwnerOrAdmin {
        for (uint32 i = 0; i < nfts.length; i++) {
            if (nfts[i].count > 0) {
                for (uint32 j = 0; j < nfts[i].count; j++) {
                    IFcNFT(nfts[i].nft).mintFcNFTByLogic(nfts[i].owner, nfts[i].itemId, nfts[i].safe);
                }
            }
        }
    }

    function withdrawFcNft(
        address nft,
        uint256 tokenId,
        address to,
        bytes32 txId,
        PayInfo calldata payInfo,
        bytes memory sign) external payable {
        require(signUsed[sign] != true, "This signature already be used");
        require(IFcNFT(nft).isDeposited(tokenId), "This NFT is not deposited");
        bytes32 msgHash = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    nft,
                    tokenId,
                    to,
                    txId,
                    encodePayInfo(payInfo),
                    block.chainid,
                    address(this)
                )
            )
        );
        verifySign(sign, msgHash);
        if (payInfo.amount > 0) {
            payToken(payInfo.tokenAddress, payInfo.amount, payInfo.orderId);
        }
        address from = IERC721(address(nft)).ownerOf(tokenId);
        IERC721(address(nft)).transferFrom(from, to, tokenId);
        emit FcNFTWithdrawnEvent(payInfo.orderId);
    }

    function setFcNftItemId(
        address nft,
        uint256 tokenId,
        string memory itemId,
        PayInfo calldata payInfo,
        bytes memory sign) external payable {
        require(signUsed[sign] != true, "This signature already be used");
        require(IERC721(nft).ownerOf(tokenId) == _msgSender(), "You are not the owner of this NFT");
        bytes32 msgHash = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    nft,
                    tokenId,
                    itemId,
                    encodePayInfo(payInfo),
                    block.chainid,
                    address(this)
                )
            )
        );
        verifySign(sign, msgHash);
        if (payInfo.amount > 0) {
            payToken(payInfo.tokenAddress, payInfo.amount, payInfo.orderId);
        }
        IFcNFT(nft).setItemIdByLogic(tokenId, itemId);
        emit FcNFTSetItemIdEvent(payInfo.orderId);
    }

    function ownerOf(address nft, uint256 tokenId) external view returns (address) {
        return IFcNFT(nft).realOwnerOf(tokenId);
    }

    function isDeposited(address nft, uint256 tokenId) external view returns (bool) {
        return IFcNFT(nft).isDeposited(tokenId);
    }

    function fusionBurnOrTransfer(
        FusionNFT[] calldata fusionNfts,
        address fusionTo) internal {
        bool isBurn = fusionTo == address(0);
        for (uint32 i = 0; i < fusionNfts.length; i++) {
            if (isBurn) {
                IFcNFT(fusionNfts[i].nft).burnByLogic(fusionNfts[i].tokenId);
            } else {
                IERC721(fusionNfts[i].nft).transferFrom(_msgSender(), fusionTo, fusionNfts[i].tokenId);
            }
        }
    }

    function fusionRevert(
        FusionNFT[] calldata fusionNfts,
        address revertFrom,
        address revertTo) internal {
        for (uint32 i = 0; i < fusionNfts.length; i++) {
            IERC721(fusionNfts[i].nft).transferFrom(revertFrom, revertTo, fusionNfts[i].tokenId);
        }
    }

    function encodeFusionNfts(FusionNFT[] calldata fusionNfts) internal pure returns (bytes memory) {
        return abi.encode(fusionNfts);
    }

    function fusionPay(
        FusionNFT[] calldata fusionNfts,
        address fusionAddress,
        PayInfo calldata payInfo,
        bytes memory sign
    ) external payable {
        require(signUsed[sign] != true, "This signature already be used");
        bytes32 msgHash = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    encodeFusionNfts(fusionNfts),
                    fusionAddress,
                    encodePayInfo(payInfo),
                    block.chainid,
                    address(this)
                )
            )
        );
        verifySign(sign, msgHash);
        if (payInfo.amount > 0) {
            payToken(payInfo.tokenAddress, payInfo.amount, payInfo.orderId);
        }
        if (fusionNfts.length > 0) {
            fusionBurnOrTransfer(fusionNfts, fusionAddress);
        }
        emit FusionPayEvent(payInfo.orderId);
    }

    function funsionFcNft(
        address owner,
        FusionNFT[] calldata fusionNfts,
        address fusionAddress,
        FusionNFT[] calldata revertNfts,
        address revertFrom,
        address revertTo,
        FusionMintItem[] calldata items,
        TokenReward[] calldata rewards,
        bool safe,
        PayInfo calldata payInfo,
        bytes memory sign
    ) external payable {
        require(signUsed[sign] != true, "This signature already be used");
        bytes memory encodedItems = abi.encode(items);
        bytes32 msgHash = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    owner,
                    encodeFusionNfts(fusionNfts),
                    fusionAddress,
                    encodeFusionNfts(revertNfts),
                    revertFrom,
                    revertTo,
                    encodedItems,
                    encodeTokenRewards(rewards),
                    encodePayInfo(payInfo),
                    block.chainid,
                    address(this)
                )
            )
        );
        verifySign(sign, msgHash);
        if (payInfo.amount > 0) {
            payToken(payInfo.tokenAddress, payInfo.amount, payInfo.orderId);
        }
        if (fusionNfts.length > 0) {
            fusionBurnOrTransfer(fusionNfts, fusionAddress);
        }
        if (revertNfts.length > 0)
        {
            fusionRevert(revertNfts, revertFrom, revertTo);
        }
        uint256[] memory tokenIds = new uint256[](items.length);
        if (items.length > 0) {
            for (uint32 i = 0; i < items.length; i++) {
                address nft = items[i].nft;
                string memory itemId = items[i].itemId;
                if (bytes(itemId).length > 0) {
                    tokenIds[i] = IFcNFT(nft).mintFcNFTByLogic(owner, itemId, safe);
                } else {
                    tokenIds[i] = 0;
                }
            }
        }
        if (rewards.length > 0) {
            for (uint32 i = 0; i < rewards.length; i++) {
                _transferToken(rewards[i].token, owner, rewards[i].amount);
            }
        }
        emit FusionFcNFTEvent(payInfo.orderId, tokenIds);
    }
}