// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

interface IYieldDistributor {
    function checkpoint(address holder) external;
}

// FractionToken is a standard ERC20 token representing fractional ownership
// of one specific asset registered in AssetVault.
// Each asset gets its own unique FractionToken deployment.
// [YL-EDIT] Original: contract FractionToken is ERC20 {
contract FractionToken is ERC20, ERC20Burnable {

    // The asset ID this token represents (from AssetVault)
    uint256 public assetId;

    // The AssetVault contract that holds the corresponding NFT
    address public vault;

    // [YL-EDIT] Original: no factory/distributor state existed.
    address public factory;
    address public distributor;

    event DistributorSet(address indexed distributor);

    // [YL-EDIT] Original: no onlyFactory modifier existed.
    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

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
        // [YL-EDIT] Original: no factory assignment.
        factory = msg.sender;

        // Mint all shares to the operator - they distribute from here
        _mint(operator, totalShares);
    }

    // [YL-EDIT] Original: no distributor wiring function existed.
    function setDistributor(address _distributor) external onlyFactory {
        require(distributor == address(0), "Distributor already set");
        require(_distributor != address(0), "Invalid distributor");
        distributor = _distributor;
        emit DistributorSet(_distributor);
    }

    // [YL-EDIT] Original: transfer lifecycle had no yield checkpoint hooks.
    function _update(address from, address to, uint256 value) internal override {
        if (distributor != address(0)) {
            if (from != address(0)) {
                IYieldDistributor(distributor).checkpoint(from);
            }
            if (to != address(0) && to != from) {
                IYieldDistributor(distributor).checkpoint(to);
            }
        }

        super._update(from, to, value);
    }
}
