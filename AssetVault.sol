// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

interface IFractionFactory {
    function fractionsFor(uint256 assetId) external view returns (address);
}

interface IFractionToken {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function burnFrom(address account, uint256 amount) external;
    function assetId() external view returns (uint256);
    function vault() external view returns (address);
}

// AssetVault registers real-world assets as NFTs.
// After fractionalization, the NFT is locked inside this vault.
// If one wallet later owns 100% of the shares, they can redeem the NFT.
// [YL-EDIT] Original: contract AssetVault is ERC721 {
contract AssetVault is ERC721, ERC721Holder {
    uint256 public nextTokenId;
    address public admin;
    address public factory;
    // [YL-EDIT] Original: no canonical token binding existed in vault.
    mapping(uint256 => address) public fractionTokenFor;
    // [YL-EDIT] Original: no explicit lock state mapping existed.
    mapping(uint256 => bool) public isLocked;
    // [YL-EDIT] Original: factory could be updated at any time by admin.
    bool public factoryFrozen;

    struct Asset {
        string model;
        string operatorName;
        string location;
        uint256 registeredAt;
    }

    mapping(uint256 => Asset) public assets;

    event AssetRegistered(uint256 indexed tokenId, string model, address indexed owner);
    event FactoryUpdated(address indexed factory);
    event FractionTokenBound(uint256 indexed tokenId, address indexed tokenAddress);
    event AssetLocked(uint256 indexed tokenId);
    event AssetRedeemed(uint256 indexed tokenId, address indexed redeemer);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    constructor() ERC721("YieldLayer Asset", "YLA") {
        admin = msg.sender;
    }

    // Set the FractionFactory address (one-time before first lock)
    // [YL-EDIT] Original: function setFactory(address _factory) external onlyAdmin { ... }
    function setFactory(address _factory) external onlyAdmin {
        require(!factoryFrozen, "Factory frozen");
        // [YL-EDIT] Original: no one-time guard.
        require(factory == address(0), "Factory already set");
        require(_factory != address(0), "Invalid factory");
        factory = _factory;
        emit FactoryUpdated(_factory);
    }

    // Register a physical asset and mint its NFT to the operator
    function registerAsset(
        string memory model,
        string memory operatorName,
        string memory location
    ) external returns (uint256 tokenId) {
        tokenId = nextTokenId++;

        _mint(msg.sender, tokenId);

        assets[tokenId] = Asset({
            model: model,
            operatorName: operatorName,
            location: location,
            registeredAt: block.timestamp
        });

        emit AssetRegistered(tokenId, model, msg.sender);
    }

    function getAsset(uint256 tokenId) external view returns (Asset memory) {
        require(tokenId < nextTokenId, "Asset does not exist");
        return assets[tokenId];
    }

    // Called by FractionFactory during fractionalization
    function lockAsset(uint256 tokenId, address operator) external onlyFactory {
        // [YL-EDIT] Original: no explicit double-lock protection.
        require(!isLocked[tokenId], "Asset already locked");
        require(ownerOf(tokenId) == operator, "Operator not owner");
        // [YL-EDIT] Original: _transfer(operator, address(this), tokenId);
        _safeTransfer(operator, address(this), tokenId, "");
        isLocked[tokenId] = true;
        // Freeze factory changes after first locked lifecycle starts.
        factoryFrozen = true;
        emit AssetLocked(tokenId);
    }

    // [YL-EDIT] Original: no function to bind canonical token per asset.
    function bindFractionToken(uint256 tokenId, address tokenAddress) external onlyFactory {
        require(isLocked[tokenId], "Asset not locked");
        require(tokenAddress != address(0), "Invalid token");
        require(fractionTokenFor[tokenId] == address(0), "Token already bound");

        IFractionToken token = IFractionToken(tokenAddress);
        require(token.vault() == address(this), "Token vault mismatch");
        require(token.assetId() == tokenId, "Token asset mismatch");

        fractionTokenFor[tokenId] = tokenAddress;
        emit FractionTokenBound(tokenId, tokenAddress);
    }

    // Redeem the original NFT if caller owns 100% of the shares
    function redeemAsset(uint256 tokenId) external {
        require(factory != address(0), "Factory not set");
        require(isLocked[tokenId], "Asset not locked");
        require(ownerOf(tokenId) == address(this), "Asset not locked");

        // [YL-EDIT] Original:
        // address tokenAddress = IFractionFactory(factory).fractionsFor(tokenId);
        // require(tokenAddress != address(0), "Asset not fractionalized");
        address tokenAddress = fractionTokenFor[tokenId];
        require(tokenAddress != address(0), "Token not bound");

        IFractionToken token = IFractionToken(tokenAddress);
        // [YL-EDIT] Original: no token-vault or token-asset binding checks.
        require(token.vault() == address(this), "Token vault mismatch");
        require(token.assetId() == tokenId, "Token asset mismatch");

        uint256 totalShares = token.totalSupply();
        require(totalShares > 0, "No shares exist");
        require(token.balanceOf(msg.sender) == totalShares, "Must own 100% of shares");

        // User must approve the vault to burn their shares first
        token.burnFrom(msg.sender, totalShares);

        isLocked[tokenId] = false;
        // [YL-EDIT] Original: _transfer(address(this), msg.sender, tokenId);
        _safeTransfer(address(this), msg.sender, tokenId, "");

        emit AssetRedeemed(tokenId, msg.sender);
    }
}