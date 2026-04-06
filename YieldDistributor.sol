// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./FractionToken.sol";

// YieldDistributor handles yield deposits from operators and
// lets investors claim their proportional share of that yield.
//
// Important note for this MVP:
// Before any balance-changing action (transfer, burn, redeem), holders should
// be checkpointed first so their pending yield is preserved in unclaimedYield.
contract YieldDistributor {
    // The ERC20 fraction token whose holders receive yield
    FractionToken public token;

    // Global accumulator: total yield deposited per token (scaled by 1e18)
    uint256 public yieldPerToken;

    // Snapshot of yieldPerToken at the time each holder last claimed or checkpointed
    mapping(address => uint256) public lastYieldPerToken;

    // Yield that has already been snapshotted but not yet withdrawn
    mapping(address => uint256) public unclaimedYield;

    event YieldDeposited(address indexed operator, uint256 amount, uint256 newYieldPerToken);
    event YieldClaimed(address indexed investor, uint256 amount);
    event YieldCheckpointed(address indexed holder, uint256 totalUnclaimed, uint256 checkpointYieldPerToken);

    constructor(address _token) {
        token = FractionToken(_token);
    }

    // ---------------------------------------------------------------
    // OPERATOR FUNCTION
    // Operator sends ETH here representing the asset's revenue.
    // ---------------------------------------------------------------
    function depositYield() external payable {
        require(msg.value > 0, "Must send ETH to deposit yield");

        uint256 totalSupply = token.totalSupply();
        require(totalSupply > 0, "No shares have been issued yet");

        // Increase global yield-per-token accumulator
        yieldPerToken += (msg.value * 1e18) / totalSupply;

        emit YieldDeposited(msg.sender, msg.value, yieldPerToken);
    }

    // ---------------------------------------------------------------
    // INVESTOR FUNCTION
    // Investor calls this to withdraw all yield they are owed.
    // ---------------------------------------------------------------
    function claim() external {
        _updateYield(msg.sender);

        uint256 amount = unclaimedYield[msg.sender];
        require(amount > 0, "No yield to claim");

        unclaimedYield[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");

        emit YieldClaimed(msg.sender, amount);
    }

    // ---------------------------------------------------------------
    // CHECKPOINT FUNCTIONS
    // Call this before transfers, burns, or redemption so accrued yield is saved.
    // Anyone can checkpoint; this does not transfer funds, it only snapshots state.
    // ---------------------------------------------------------------
    function checkpoint(address holder) public {
        _updateYield(holder);
        emit YieldCheckpointed(holder, unclaimedYield[holder], yieldPerToken);
    }

    function checkpointMany(address[] calldata holders) external {
        for (uint256 i = 0; i < holders.length; i++) {
            _updateYield(holders[i]);
            emit YieldCheckpointed(holders[i], unclaimedYield[holders[i]], yieldPerToken);
        }
    }

    // ---------------------------------------------------------------
    // VIEW FUNCTION
    // Check how much yield a given address can currently claim.
    // ---------------------------------------------------------------
    function claimable(address holder) external view returns (uint256) {
        return unclaimedYield[holder] + _pendingYield(holder);
    }

    // ---------------------------------------------------------------
    // INTERNAL HELPERS
    // ---------------------------------------------------------------
    function _updateYield(address holder) internal {
        unclaimedYield[holder] += _pendingYield(holder);
        lastYieldPerToken[holder] = yieldPerToken;
    }

    function _pendingYield(address holder) internal view returns (uint256) {
        uint256 balance = token.balanceOf(holder);
        uint256 yieldDelta = yieldPerToken - lastYieldPerToken[holder];
        return (balance * yieldDelta) / 1e18;
    }
}