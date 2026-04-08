// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

interface IAssetVaultForToken {
    function operatorOf(uint256 tokenId) external view returns (address);
}

interface IYieldDistributor {
    function checkpoint(address holder) external;
}

// FractionToken represents fractional ownership of one specific asset.
// It is burnable so 100% holders can redeem the underlying NFT later.
// When a distributor is set, every transfer auto-checkpoints both parties
// so accrued yield is never lost.
contract FractionToken is ERC20, ERC20Burnable {
    uint256 public assetId;
    address public vault;
    address public distributor;

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

    // Only the asset operator can link the distributor, and only once.
    function setDistributor(address _distributor) external {
        require(distributor == address(0), "Already set");
        require(_distributor != address(0), "Invalid distributor");
        require(
            IAssetVaultForToken(vault).operatorOf(assetId) == msg.sender,
            "Not the operator"
        );
        distributor = _distributor;
    }

    // Checkpoint both parties before any balance change so accrued yield is preserved.
    function _update(address from, address to, uint256 value) internal override {
        if (distributor != address(0)) {
            if (from != address(0)) IYieldDistributor(distributor).checkpoint(from);
            if (to != address(0)) IYieldDistributor(distributor).checkpoint(to);
        }
        super._update(from, to, value);
    }
}
