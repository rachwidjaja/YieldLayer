// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IFractionFactory {
    function fractionsFor(uint256 assetId) external view returns (address);
}

interface IFractionToken {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function burnFrom(address account, uint256 amount) external;
}

// AssetVault registers real-world assets as NFTs.
// After fractionalization, the NFT is locked inside this vault.
// If one wallet later owns 100% of the shares, they can redeem the NFT.
contract AssetVault is ERC721, ReentrancyGuard {
    uint256 public nextTokenId;
    address public admin;
    address public factory;

    struct Asset {
        string model;
        string operatorName;
        string location;
        uint256 registeredAt;
    }

    mapping(uint256 => Asset) public assets;
    mapping(uint256 => address) public operatorOf;

    event AssetRegistered(uint256 indexed tokenId, string model, address indexed owner);
    event FactoryUpdated(address indexed factory);
    event AssetLocked(uint256 indexed tokenId);
    event AssetRedeemed(uint256 indexed tokenId, address indexed redeemer);
    event OperatorTransferred(uint256 indexed tokenId, address indexed oldOperator, address indexed newOperator);
    event AdminRenounced(address indexed oldAdmin);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    modifier onlyOperator(uint256 tokenId) {
        require(msg.sender == operatorOf[tokenId], "Not the operator");
        _;
    }

    constructor() ERC721("YieldLayer Asset", "YLA") {
        admin = msg.sender;
    }

    // Set the FractionFactory address (one-time only, immutable once set)
    function setFactory(address _factory) external onlyAdmin {
        require(factory == address(0), "Factory already set");
        require(_factory != address(0), "Invalid factory");
        factory = _factory;
        emit FactoryUpdated(_factory);
    }

    // Renounce admin role — irreversible. Only callable after factory is set.
    function renounceAdmin() external onlyAdmin {
        require(factory != address(0), "Set factory first");
        emit AdminRenounced(admin);
        admin = address(0);
    }

    // Register a physical asset and mint its NFT to the operator (admin-gated)
    function registerAsset(
        string memory model,
        string memory operatorName,
        string memory location,
        address operator
    ) external onlyAdmin returns (uint256 tokenId) {
        require(operator != address(0), "Invalid operator");
        tokenId = nextTokenId++;

        _mint(operator, tokenId);

        assets[tokenId] = Asset({
            model: model,
            operatorName: operatorName,
            location: location,
            registeredAt: block.timestamp
        });

        operatorOf[tokenId] = operator;

        emit AssetRegistered(tokenId, model, operator);
    }

    function transferOperator(uint256 tokenId, address newOperator) external onlyOperator(tokenId) {
        require(newOperator != address(0), "Invalid operator");
        operatorOf[tokenId] = newOperator;
        emit OperatorTransferred(tokenId, msg.sender, newOperator);
    }

    function getAsset(uint256 tokenId) external view returns (Asset memory) {
        require(tokenId < nextTokenId, "Asset does not exist");
        return assets[tokenId];
    }

    // Called by FractionFactory during fractionalization
    function lockAsset(uint256 tokenId, address operator) external onlyFactory {
        require(ownerOf(tokenId) == operator, "Operator not owner");
        _transfer(operator, address(this), tokenId);
        emit AssetLocked(tokenId);
    }

    // Redeem the original NFT if caller owns 100% of the shares
    function redeemAsset(uint256 tokenId) external nonReentrant {
        require(factory != address(0), "Factory not set");
        require(ownerOf(tokenId) == address(this), "Asset not locked");

        address tokenAddress = IFractionFactory(factory).fractionsFor(tokenId);
        require(tokenAddress != address(0), "Asset not fractionalized");

        IFractionToken token = IFractionToken(tokenAddress);

        uint256 totalShares = token.totalSupply();
        require(totalShares > 0, "No shares exist");
        require(token.balanceOf(msg.sender) == totalShares, "Must own 100% of shares");

        // Burn shares first (checks-effects-interactions)
        token.burnFrom(msg.sender, totalShares);

        _transfer(address(this), msg.sender, tokenId);

        emit AssetRedeemed(tokenId, msg.sender);
    }
}