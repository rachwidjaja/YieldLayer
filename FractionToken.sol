// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

// FractionToken represents fractional ownership of one specific asset.
// It is burnable so 100% holders can redeem the underlying NFT later.
contract FractionToken is ERC20, ERC20Burnable {
    uint256 public assetId;
    address public vault;

    constructor(
        string memory name,
        string memory symbol,
        uint256 totalShares,
        uint256 _assetId,
        address _vault,
        address operator
    ) ERC20(name, symbol) {
        assetId = _assetId;
        vault = _vault;

        _mint(operator, totalShares);
    }
}