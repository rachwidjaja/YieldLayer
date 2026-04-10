// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AssetVault.sol";
import "./FractionToken.sol";
import "./YieldDistributor.sol";
import "./ShareSale.sol";

// FractionFactory lets an asset operator fractionalize their NFT into ERC20 shares.
// Only the NFT owner can fractionalize their own asset.
// Each asset can only be fractionalized once.

contract FractionFactory {

    // Reference to the AssetVault where NFTs live
    AssetVault public vault;

    // Maps each asset token ID to its FractionToken contract address
    // Returns address(0) if the asset has not been fractionalized yet
    mapping(uint256 => address) public fractionsFor;


    mapping(uint256 => address) public distributorFor;
  
    mapping(uint256 => address) public saleContractFor;

    event Fractionalized(
        uint256 indexed assetId,
        address indexed tokenAddress,
        uint256 totalShares
    );
    event DistributorDeployed(uint256 indexed assetId, address indexed distributor);
    event SaleContractDeployed(uint256 indexed assetId, address indexed saleContract, address indexed operator);

    /// @notice Creates a factory bound to an AssetVault instance.
    /// @param _vault AssetVault contract address.
    constructor(address _vault) {
        // Constructor guard avoids unusable factory deployment.
        require(_vault != address(0), "Invalid vault");
        vault = AssetVault(_vault);
        // AssetVault admin must call setFactory(factoryAddress) explicitly after deployment.
    }

    /// @notice Fractionalizes an asset NFT into ERC20 shares and deploys companion contracts.
    /// @dev Locks NFT in vault, deploys FractionToken, YieldDistributor, and ShareSale.
    /// @param assetId Asset NFT id in AssetVault.
    /// @param totalShares Number of ERC20 shares to mint.
    /// @param name ERC20 token name.
    /// @param symbol ERC20 token symbol.
    /// @return Address of newly deployed FractionToken.
    function fractionalize(
        uint256 assetId,          // token ID from AssetVault
        uint256 totalShares,      // how many ERC20 shares to create e.g. 10000
        string memory name,       // ERC20 name e.g. "YieldLayer EV Station 0"
        string memory symbol      // ERC20 symbol e.g. "YLEV0"
    ) external returns (address) {

        // Only current NFT owner can start fractionalization for this asset.
        // Only the NFT owner (the operator) can fractionalize their asset
        require(vault.ownerOf(assetId) == msg.sender, "Not the asset owner");

        // Each asset can only be fractionalized once
        require(fractionsFor[assetId] == address(0), "Already fractionalized");


        require(vault.factory() == address(this), "Factory not linked in vault");

        require(totalShares > 0, "Shares must be greater than zero");

    // Move NFT into vault escrow before deploying share token contracts.
        vault.lockAsset(assetId, msg.sender);

        // Deploy a brand new ERC20 contract for this specific asset
        FractionToken token = new FractionToken(
            name,
            symbol,
            totalShares,
            assetId,
            address(vault),
            msg.sender  // operator receives all shares
        );

        // Record the mapping so anyone can look up the token for a given asset
        fractionsFor[assetId] = address(token);


        vault.bindFractionToken(assetId, address(token));


        YieldDistributor distributor = new YieldDistributor(address(token), msg.sender);
        distributorFor[assetId] = address(distributor);

        // Wire checkpoint callbacks into token transfers.
        token.setDistributor(address(distributor));

    // Deploy dedicated primary sale contract for this asset token.
        ShareSale sale = new ShareSale(address(token), msg.sender, assetId);
        saleContractFor[assetId] = address(sale);

        emit Fractionalized(assetId, address(token), totalShares);
        emit DistributorDeployed(assetId, address(distributor));
        emit SaleContractDeployed(assetId, address(sale), msg.sender);

        return address(token);
    }
}
