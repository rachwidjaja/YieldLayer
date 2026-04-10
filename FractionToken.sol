// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IYieldDistributor {
    /// @notice Snapshots accrued yield for a holder before balance changes.
    /// @param holder Address whose pending yield is checkpointed.
    function checkpoint(address holder) external;
}

// FractionToken is a standard ERC20 token representing fractional ownership
// of one specific asset registered in AssetVault.
// Each asset gets its own unique FractionToken deployment.

contract FractionToken is ERC20 {


    // The asset ID this token represents (from AssetVault)
    uint256 public assetId;

    // The AssetVault contract that holds the corresponding NFT
    address public vault;


    address public factory;
    address public distributor;

    event DistributorSet(address indexed distributor);

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    /// @notice Deploys a fraction token tied to one asset and mints all shares to operator.
    /// @param name ERC20 name.
    /// @param symbol ERC20 symbol.
    /// @param totalShares Total shares to mint initially.
    /// @param _assetId Asset id represented by this token.
    /// @param _vault AssetVault address used for redemption burn.
    /// @param operator Initial recipient of all minted shares.
    constructor(
        string memory name,       // e.g. "YieldLayer EV Station 0"
        string memory symbol,     // e.g. "YLEV0"
        uint256 totalShares,      // e.g. 10000 shares
        uint256 _assetId,         // the NFT token ID in AssetVault
        address _vault,           // address of AssetVault contract
        address operator          // receives all shares on deployment
    ) ERC20(name, symbol) {
        // Persist immutable asset/vault context for redemption safety checks.
        assetId = _assetId;
        vault = _vault;

        factory = msg.sender;

        // Mint all shares to the operator - they distribute from here
        _mint(operator, totalShares);
    }

    /// @notice Sets the yield distributor used for transfer checkpoints.
    /// @dev Callable once by factory.
    /// @param _distributor YieldDistributor address.
    function setDistributor(address _distributor) external onlyFactory {
        // Distributor is wired once to avoid checkpoint target changes later.
        require(distributor == address(0), "Distributor already set");
        require(_distributor != address(0), "Invalid distributor");
        distributor = _distributor;
        emit DistributorSet(_distributor);
    }

    /// @notice Burns shares from an account during redemption.
    /// @dev Vault-only; spends allowance so holder approval is still required.
    /// @param account Holder address whose shares are burned.
    /// @param amount Share amount to burn.
    function burnFrom(address account, uint256 amount) external onlyVault {
        // Vault burns only after allowance, preserving holder consent on redeem.
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    /// @notice Overrides ERC20 transfer lifecycle to checkpoint yield before balance changes.
    /// @param from Sender address.
    /// @param to Receiver address.
    /// @param value Amount transferred.
    function _update(address from, address to, uint256 value) internal override {
        // Checkpoint both sides so yield accounting stays correct across transfers.
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
