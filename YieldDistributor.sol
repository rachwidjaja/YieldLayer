// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./FractionToken.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// YieldDistributor handles yield deposits from operators and
// lets investors claim their proportional share of that yield.
//
// How the math works:
// We track a global "yieldPerToken" value that increases every time
// the operator deposits yield. Each holder's claimable amount is
// (yieldPerToken - lastYieldPerToken[holder]) * balance / 1e18
//
// This pattern correctly handles investors who buy shares at different times:
// a late buyer cannot claim yield that was deposited before they owned shares.

contract YieldDistributor is ReentrancyGuard {

    // The ERC20 fraction token whose holders receive yield
    FractionToken public token;
    address public operator;

    // Global accumulator: total yield deposited per token (scaled by 1e18)
    // Increases with every depositYield() call
    uint256 public yieldPerToken;

    // Snapshot of yieldPerToken at the time each holder last claimed or updated
    // Used to calculate yield earned since their last interaction
    mapping(address => uint256) public lastYieldPerToken;

    // Yield that has been calculated but not yet withdrawn by each holder
    mapping(address => uint256) public unclaimedYield;

    event YieldDeposited(address indexed operator, uint256 amount, uint256 newYieldPerToken);
    event YieldClaimed(address indexed investor, uint256 amount);
    event YieldCheckpointed(address indexed holder, uint256 totalUnclaimed, uint256 checkpointYieldPerToken);

    /// @notice Creates a distributor for a given fraction token and operator.
    /// @param _token FractionToken address.
    /// @param _operator Authorized revenue depositor.
    constructor(address _token, address _operator) {
        // Constructor checks ensure distribution state is bound to valid contracts.
        require(_token != address(0), "Invalid token");
        require(_operator != address(0), "Invalid operator");
        token = FractionToken(_token);
        operator = _operator;
    }

    /// @notice Deposits operator revenue and updates global yield-per-token accumulator.
    function depositYield() external payable {
        // Only designated operator can feed revenue into distributor.
        require(msg.value > 0, "Must send ETH to deposit yield");
 
        require(msg.sender == operator, "Only operator can deposit");

        uint256 totalSupply = token.totalSupply();
        require(totalSupply > 0, "No shares have been issued yet");

        // Increase the global yield-per-token accumulator.
        // Scaled by 1e18 to preserve precision (Solidity has no decimals).
        yieldPerToken += (msg.value * 1e18) / totalSupply;

        emit YieldDeposited(msg.sender, msg.value, yieldPerToken);
    }

    /// @notice Claims all currently accrued yield for caller.
    function claim() external nonReentrant {
        // Snapshot first, then transfer, to prevent reentrancy and stale accounting.
        // First snapshot any pending yield into unclaimedYield
        _updateYield(msg.sender);

        uint256 amount = unclaimedYield[msg.sender];
        require(amount > 0, "No yield to claim");

        // Clear the balance BEFORE transferring (prevents reentrancy attacks)
        unclaimedYield[msg.sender] = 0;

        // Transfer ETH to the investor
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");

        emit YieldClaimed(msg.sender, amount);
    }

    /// @notice Returns total claimable yield for a holder at current state.
    /// @param holder Wallet to query.
    /// @return Claimable ETH amount in wei.
    function claimable(address holder) external view returns (uint256) {
        // Total claimable = stored unclaimed plus since-last-checkpoint accrual.
        return unclaimedYield[holder] + _pendingYield(holder);
    }

    /// @notice Snapshots pending yield for a holder into unclaimed balance.
    /// @param holder Wallet to checkpoint.
    function checkpoint(address holder) public {
        // Public checkpoint syncs holder accounting before balance-changing actions.
        _updateYield(holder);
        emit YieldCheckpointed(holder, unclaimedYield[holder], yieldPerToken);
    }

    /// @notice Batch checkpoint helper for multiple holders.
    /// @param holders Wallet list to checkpoint.
    function checkpointMany(address[] calldata holders) external {
        // Batch helper to sync multiple wallets in one transaction.
        for (uint256 i = 0; i < holders.length; i++) {
            _updateYield(holders[i]);
            emit YieldCheckpointed(holders[i], unclaimedYield[holders[i]], yieldPerToken);
        }
    }

    // ---------------------------------------------------------------
    // INTERNAL HELPERS
    // ---------------------------------------------------------------

    /// @notice Internal helper to accrue holder pending yield and refresh checkpoint.
    /// @param holder Wallet to update.
    function _updateYield(address holder) internal {
        // Materialize pending accrual into stored balance and advance checkpoint.
        unclaimedYield[holder] += _pendingYield(holder);
        lastYieldPerToken[holder] = yieldPerToken;
    }

    /// @notice Internal helper to compute yield accumulated since holder's last checkpoint.
    /// @param holder Wallet to evaluate.
    /// @return Pending ETH amount in wei.
    function _pendingYield(address holder) internal view returns (uint256) {
        // Pending yield is proportional to current balance and yield delta.
        uint256 balance = token.balanceOf(holder);
        uint256 yieldDelta = yieldPerToken - lastYieldPerToken[holder];
        return (balance * yieldDelta) / 1e18;
    }
}
