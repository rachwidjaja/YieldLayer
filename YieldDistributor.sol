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
// [YL-EDIT] Original: contract YieldDistributor {
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

    // [YL-EDIT] Original: constructor(address _token) { token = FractionToken(_token); }
    constructor(address _token, address _operator) {
        token = FractionToken(_token);
        operator = _operator;
    }

    // ---------------------------------------------------------------
    // OPERATOR FUNCTION
    // Operator sends ETH here representing the asset's revenue.
    // e.g. "This week's EV charging station revenue was 0.5 ETH"
    // ---------------------------------------------------------------
    function depositYield() external payable {
        require(msg.value > 0, "Must send ETH to deposit yield");
        // [YL-EDIT] Original: no operator gate.
        require(msg.sender == operator, "Only operator can deposit");

        uint256 totalSupply = token.totalSupply();
        require(totalSupply > 0, "No shares have been issued yet");

        // Increase the global yield-per-token accumulator.
        // Scaled by 1e18 to preserve precision (Solidity has no decimals).
        yieldPerToken += (msg.value * 1e18) / totalSupply;

        emit YieldDeposited(msg.sender, msg.value, yieldPerToken);
    }

    // ---------------------------------------------------------------
    // INVESTOR FUNCTION
    // Investor calls this to withdraw all yield they are owed.
    // ---------------------------------------------------------------
    function claim() external nonReentrant {
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

    // ---------------------------------------------------------------
    // VIEW FUNCTION
    // Check how much yield a given address can currently claim.
    // ---------------------------------------------------------------
    function claimable(address holder) external view returns (uint256) {
        return unclaimedYield[holder] + _pendingYield(holder);
    }

    // [YL-EDIT] Original: no public checkpoint functions existed.
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
    // INTERNAL HELPERS
    // ---------------------------------------------------------------

    // Snapshot pending yield into unclaimedYield and update the checkpoint.
    // Must be called before any balance-changing operation.
    function _updateYield(address holder) internal {
        unclaimedYield[holder] += _pendingYield(holder);
        lastYieldPerToken[holder] = yieldPerToken;
    }

    // Calculate yield earned by a holder since their last checkpoint.
    // Uses current token balance and the gap in yieldPerToken.
    function _pendingYield(address holder) internal view returns (uint256) {
        uint256 balance = token.balanceOf(holder);
        uint256 yieldDelta = yieldPerToken - lastYieldPerToken[holder];
        return (balance * yieldDelta) / 1e18;
    }
}
