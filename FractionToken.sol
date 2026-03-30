// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// FractionToken is a standard ERC20 token representing fractional ownership
// of one specific asset registered in AssetVault.
// Each asset gets its own unique FractionToken deployment.
contract FractionToken is ERC20 {

    // The asset ID this token represents (from AssetVault)
    uint256 public assetId;

    // The AssetVault contract that holds the corresponding NFT
    address public vault;

    // Called by FractionFactory when an operator fractionalizes their asset.
    // All shares are minted immediately to the operator.
    // The operator can then sell/transfer shares to investors.
    constructor(
        string memory name,       // e.g. "YieldLayer EV Station 0"
        string memory symbol,     // e.g. "YLEV0"
        uint256 totalShares,      // e.g. 10000 shares
        uint256 _assetId,         // the NFT token ID in AssetVault
        address _vault,           // address of AssetVault contract
        address operator          // receives all shares on deployment
    ) ERC20(name, symbol) {
        assetId = _assetId;
        vault = _vault;

        // Mint all shares to the operator - they distribute from here
        _mint(operator, totalShares);
    }
}
