// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

interface IFractionFactory {

    /// @notice Returns the canonical fraction token for a given asset id.
    /// @param assetId Asset NFT id in the vault.
    /// @return Fraction token contract address, or zero address if not set.

    function fractionsFor(uint256 assetId) external view returns (address);
}

interface IFractionToken {

    /// @notice Returns total outstanding fraction shares.
    /// @return Current ERC20 total supply.
    function totalSupply() external view returns (uint256);

    /// @notice Returns the share balance held by an account.
    /// @param account Wallet to query.
    /// @return Share balance for the account.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Burns shares from an account using allowance-based authorization.
    /// @param account Share holder address.
    /// @param amount Number of shares to burn.
    function burnFrom(address account, uint256 amount) external;

    /// @notice Returns which asset id this fraction token represents.
    /// @return Asset NFT id.
    function assetId() external view returns (uint256);

    /// @notice Returns the vault contract associated with this token.
    /// @return Vault contract address.
    function vault() external view returns (address);
}

// AssetVault registers real-world assets as NFTs.
// After fractionalization, the NFT is locked inside this vault.
// If one wallet later owns 100% of the shares, they can redeem the NFT.

contract AssetVault is ERC721, ERC721Holder {
    uint256 public nextTokenId;
    address public admin;
    address public factory;

    mapping(uint256 => address) public fractionTokenFor;

    mapping(uint256 => bool) public isLocked;

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

    /// @notice Deploys the AssetVault ERC721 and sets deployer as admin.
    constructor() ERC721("YieldLayer Asset", "YLA") {
        // Deployer is the governance/admin for factory linkage setup.
        admin = msg.sender;
    }

    /// @notice Sets the factory address used to manage lock/bind lifecycle actions.
    /// @dev Can be called once by admin before the first asset lock.
    /// @param _factory FractionFactory contract address.
    function setFactory(address _factory) external onlyAdmin {
        // Factory can only be linked before lifecycle is frozen.
        require(!factoryFrozen, "Factory frozen");
   


        // One-time trusted factory registration.
        require(factory == address(0), "Factory already set");
        require(_factory != address(0), "Invalid factory");
        factory = _factory;
        emit FactoryUpdated(_factory);
    }


    /// @notice Registers a physical asset and mints its NFT to caller.
    /// @param model Asset model name.
    /// @param operatorName Legal or display name of the asset operator.
    /// @param location Human-readable asset location.
    /// @return tokenId Newly minted asset token id.

    function registerAsset(
        string memory model,
        string memory operatorName,
        string memory location
    ) external returns (uint256 tokenId) {
        // Allocate next NFT id and mint ownership to operator.
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


    /// @notice Returns metadata for a registered asset.
    /// @param tokenId Asset token id.
    /// @return Stored asset struct.
    function getAsset(uint256 tokenId) external view returns (Asset memory) {
        // Guard against reads for unregistered token ids.
        require(tokenId < nextTokenId, "Asset does not exist");
        return assets[tokenId];
    }


    /// @notice Locks an asset NFT in vault custody during fractionalization.
    /// @dev Factory-only; called from FractionFactory.
    /// @param tokenId Asset token id to lock.
    /// @param operator Current operator/owner expected to transfer the NFT.
    function lockAsset(uint256 tokenId, address operator) external onlyFactory {
        // Factory escrows the NFT in vault before share issuance.
      
        require(!isLocked[tokenId], "Asset already locked");
        require(ownerOf(tokenId) == operator, "Operator not owner");
        _safeTransfer(operator, address(this), tokenId, "");
        isLocked[tokenId] = true;

        factoryFrozen = true;
        emit AssetLocked(tokenId);
    }



    /// @notice Binds the canonical fraction token for a locked asset.
    /// @dev Factory-only; ensures token metadata matches this vault and asset id.
    /// @param tokenId Asset token id.
    /// @param tokenAddress FractionToken contract address.
    function bindFractionToken(uint256 tokenId, address tokenAddress) external onlyFactory {
        // Persist canonical token mapping used later by redemption logic.
        require(isLocked[tokenId], "Asset not locked");
        require(tokenAddress != address(0), "Invalid token");
        require(fractionTokenFor[tokenId] == address(0), "Token already bound");

        IFractionToken token = IFractionToken(tokenAddress);
        require(token.vault() == address(this), "Token vault mismatch");
        require(token.assetId() == tokenId, "Token asset mismatch");

        fractionTokenFor[tokenId] = tokenAddress;
        emit FractionTokenBound(tokenId, tokenAddress);
    }

    /// @notice Redeems a locked asset NFT by burning all corresponding shares.
    /// @dev Caller must hold 100% of outstanding shares and approve vault burn.
    /// @param tokenId Asset token id to redeem.
    function redeemAsset(uint256 tokenId) external {
        // Redemption requires locked NFT and exact token binding for this asset.
        require(factory != address(0), "Factory not set");
        require(isLocked[tokenId], "Asset not locked");
        require(ownerOf(tokenId) == address(this), "Asset not locked");

        address tokenAddress = fractionTokenFor[tokenId];
        require(tokenAddress != address(0), "Token not bound");

        IFractionToken token = IFractionToken(tokenAddress);

        require(token.vault() == address(this), "Token vault mismatch");
        require(token.assetId() == tokenId, "Token asset mismatch");

        uint256 totalShares = token.totalSupply();
        require(totalShares > 0, "No shares exist");
        // Caller must own the full share supply before reclaiming the NFT.
        require(token.balanceOf(msg.sender) == totalShares, "Must own 100% of shares");


        token.burnFrom(msg.sender, totalShares);

        isLocked[tokenId] = false;

        _safeTransfer(address(this), msg.sender, tokenId, "");

        emit AssetRedeemed(tokenId, msg.sender);
    }
}