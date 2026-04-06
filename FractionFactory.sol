// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AssetVault.sol";
import "./FractionToken.sol";

// FractionFactory lets an asset operator fractionalize their NFT into ERC20 shares.
// Only the NFT owner can fractionalize their own asset.
// Each asset can only be fractionalized once.
contract FractionFactory {
    // Reference to the AssetVault where NFTs live
    AssetVault public vault;

    // Maps each asset token ID to its FractionToken contract address
    // Returns address(0) if the asset has not been fractionalized yet
    mapping(uint256 => address) public fractionsFor;

    event Fractionalized(
        uint256 indexed assetId,
        address indexed tokenAddress,
        uint256 totalShares
    );

    constructor(address _vault) {
        vault = AssetVault(_vault);
    }

    // Operator calls this after registering their asset in AssetVault.
    // Locks the NFT in the vault, then deploys a new ERC20 and mints all shares to the operator.
    // Returns the address of the newly deployed FractionToken.
    function fractionalize(
        uint256 assetId,          // token ID from AssetVault
        uint256 totalShares,      // how many ERC20 shares to create e.g. 10000
        string memory name,       // ERC20 name e.g. "YieldLayer EV Station 0"
        string memory symbol      // ERC20 symbol e.g. "YLEV0"
    ) external returns (address) {
        // Only the NFT owner (the operator) can fractionalize their asset
        require(vault.ownerOf(assetId) == msg.sender, "Not the asset owner");

        // Each asset can only be fractionalized once
        require(fractionsFor[assetId] == address(0), "Already fractionalized");

        require(totalShares > 0, "Shares must be greater than zero");

        // Lock the NFT inside the AssetVault before issuing shares
        vault.lockAsset(assetId, msg.sender);

        // Deploy a brand new ERC20 contract for this specific asset
        FractionToken token = new FractionToken(
            name,
            symbol,
            totalShares,
            assetId,
            address(vault),
            msg.sender // operator receives all shares
        );

        // Record the mapping so anyone can look up the token for a given asset
        fractionsFor[assetId] = address(token);

        emit Fractionalized(assetId, address(token), totalShares);

        return address(token);
    }
}