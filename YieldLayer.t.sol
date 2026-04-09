// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AssetVault.sol";
import "../src/FractionFactory.sol";
import "../src/FractionToken.sol";
import "../src/YieldDistributor.sol";
import "../src/ShareSale.sol";

contract YieldLayerTest is Test {
    AssetVault vault;
    FractionFactory factory;

    address admin = address(this);
    address operator = makeAddr("operator");
    address investorA = makeAddr("investorA");
    address investorB = makeAddr("investorB");
    address stranger = makeAddr("stranger");

    function setUp() public {
        vault = new AssetVault();
        factory = new FractionFactory(address(vault));
        vault.setFactory(address(factory));
    }

    // ---------------------------------------------------------------
    // HELPERS
    // ---------------------------------------------------------------

    function _registerAsset() internal returns (uint256 tokenId) {
        tokenId = vault.registerAsset("ABB Terra 184", "Charge Holdings", "Orchard Road SG", operator);
    }

    function _fractionalize(uint256 assetId, uint256 shares) internal returns (FractionToken token) {
        vm.prank(operator);
        address tokenAddr = factory.fractionalize(assetId, shares, "YieldLayer EV 0", "YLEV0");
        token = FractionToken(tokenAddr);
    }

    function _fullSetup() internal returns (FractionToken token, YieldDistributor dist) {
        uint256 id = _registerAsset();
        token = _fractionalize(id, 10000);
        dist = new YieldDistributor(address(token));
        vm.prank(operator);
        token.setDistributor(address(dist));
    }

    // ===============================================================
    //  1. ASSET REGISTRATION
    // ===============================================================

    function test_RegisterAsset() public {
        uint256 id = vault.registerAsset("ABB Terra 184", "Charge Holdings", "Orchard Road SG", operator);

        assertEq(id, 0);
        assertEq(vault.ownerOf(0), operator);
        assertEq(vault.operatorOf(0), operator);
        assertEq(vault.nextTokenId(), 1);

        AssetVault.Asset memory a = vault.getAsset(0);
        assertEq(a.model, "ABB Terra 184");
        assertEq(a.operatorName, "Charge Holdings");
        assertEq(a.location, "Orchard Road SG");
    }

    function test_RegisterAsset_OnlyAdmin() public {
        vm.prank(stranger);
        vm.expectRevert("Only admin");
        vault.registerAsset("Model A", "Op A", "Loc A", operator);
    }

    function test_RegisterMultipleAssets() public {
        uint256 id0 = vault.registerAsset("Model A", "Op A", "Loc A", operator);
        uint256 id1 = vault.registerAsset("Model B", "Op B", "Loc B", operator);

        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(vault.nextTokenId(), 2);
    }

    function test_GetAsset_RevertsForNonexistent() public {
        vm.expectRevert("Asset does not exist");
        vault.getAsset(0);
    }

    // ===============================================================
    //  2. ADMIN / FACTORY SETUP
    // ===============================================================

    function test_SetFactory_OnlyAdmin() public {
        vm.prank(stranger);
        vm.expectRevert("Only admin");
        vault.setFactory(address(1));
    }

    function test_SetFactory_RejectsZero() public {
        AssetVault freshVault = new AssetVault();
        vm.expectRevert("Invalid factory");
        freshVault.setFactory(address(0));
    }

    function test_SetFactory_OnlyOnce() public {
        vm.expectRevert("Factory already set");
        vault.setFactory(address(1));
    }

    function test_RenounceAdmin() public {
        vault.renounceAdmin();
        assertEq(vault.admin(), address(0));
    }

    function test_RenounceAdmin_OnlyAdmin() public {
        vm.prank(stranger);
        vm.expectRevert("Only admin");
        vault.renounceAdmin();
    }

    function test_RenounceAdmin_RequiresFactory() public {
        AssetVault freshVault = new AssetVault();
        vm.expectRevert("Set factory first");
        freshVault.renounceAdmin();
    }

    // ===============================================================
    //  3. FRACTIONALIZATION
    // ===============================================================

    function test_Fractionalize() public {
        uint256 id = _registerAsset();
        FractionToken token = _fractionalize(id, 10000);

        // NFT locked in vault
        assertEq(vault.ownerOf(id), address(vault));
        // Shares minted to operator
        assertEq(token.totalSupply(), 10000);
        assertEq(token.balanceOf(operator), 10000);
        // Factory records mapping
        assertEq(factory.fractionsFor(id), address(token));
    }

    function test_Fractionalize_OnlyOwner() public {
        _registerAsset();
        vm.prank(stranger);
        vm.expectRevert("Not the asset owner");
        factory.fractionalize(0, 10000, "X", "X");
    }

    function test_Fractionalize_OnlyOnce() public {
        uint256 id = _registerAsset();
        _fractionalize(id, 10000);

        // After fractionalization, NFT is in the vault so operator is no longer ownerOf.
        // The "Not the asset owner" check fires before "Already fractionalized".
        vm.prank(operator);
        vm.expectRevert("Not the asset owner");
        factory.fractionalize(id, 5000, "Y", "Y");
    }

    function test_Fractionalize_ZeroShares() public {
        _registerAsset();
        vm.prank(operator);
        vm.expectRevert("Shares must be greater than zero");
        factory.fractionalize(0, 0, "X", "X");
    }

    // ===============================================================
    //  4. FRACTION TOKEN
    // ===============================================================

    function test_SetDistributor_OnlyOperator() public {
        uint256 id = _registerAsset();
        FractionToken token = _fractionalize(id, 10000);
        YieldDistributor dist = new YieldDistributor(address(token));

        vm.prank(stranger);
        vm.expectRevert("Not the operator");
        token.setDistributor(address(dist));
    }

    function test_SetDistributor_OnlyOnce() public {
        (FractionToken token, YieldDistributor dist) = _fullSetup();

        vm.prank(operator);
        vm.expectRevert("Already set");
        token.setDistributor(address(dist));
    }

    function test_SetDistributor_RejectsZero() public {
        uint256 id = _registerAsset();
        FractionToken token = _fractionalize(id, 10000);

        vm.prank(operator);
        vm.expectRevert("Invalid distributor");
        token.setDistributor(address(0));
    }

    // ===============================================================
    //  5. YIELD DISTRIBUTION
    // ===============================================================

    function test_DepositYield() public {
        (FractionToken token, YieldDistributor dist) = _fullSetup();

        vm.deal(operator, 1 ether);
        vm.prank(operator);
        dist.depositYield{value: 1 ether}();

        assertEq(dist.yieldPerToken(), (1 ether * 1e18) / 10000);
    }

    function test_DepositYield_OnlyOperator() public {
        (, YieldDistributor dist) = _fullSetup();

        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        vm.expectRevert("Not the operator");
        dist.depositYield{value: 1 ether}();
    }

    function test_DepositYield_RequiresETH() public {
        (, YieldDistributor dist) = _fullSetup();

        vm.prank(operator);
        vm.expectRevert("Must send ETH to deposit yield");
        dist.depositYield();
    }

    function test_ClaimYield_ProRata() public {
        (FractionToken token, YieldDistributor dist) = _fullSetup();

        // Distribute shares: operator 5000, A 2500, B 2500
        vm.startPrank(operator);
        token.transfer(investorA, 2500);
        token.transfer(investorB, 2500);
        vm.stopPrank();

        // Deposit 1 ETH yield
        vm.deal(operator, 1 ether);
        vm.prank(operator);
        dist.depositYield{value: 1 ether}();

        // Check claimable amounts
        uint256 claimableOp = dist.claimable(operator);
        uint256 claimableA = dist.claimable(investorA);
        uint256 claimableB = dist.claimable(investorB);

        // 50%, 25%, 25% of 1 ether (allow small rounding)
        assertApproxEqAbs(claimableOp, 0.5 ether, 1);
        assertApproxEqAbs(claimableA, 0.25 ether, 1);
        assertApproxEqAbs(claimableB, 0.25 ether, 1);

        // Claim and verify balances
        uint256 balBefore = investorA.balance;
        vm.prank(investorA);
        dist.claim();
        assertApproxEqAbs(investorA.balance - balBefore, 0.25 ether, 1);
    }

    function test_ClaimYield_NothingToClaim() public {
        (, YieldDistributor dist) = _fullSetup();

        vm.prank(investorA);
        vm.expectRevert("No yield to claim");
        dist.claim();
    }

    function test_ClaimYield_DoubleClaim() public {
        (FractionToken token, YieldDistributor dist) = _fullSetup();

        vm.deal(operator, 1 ether);
        vm.prank(operator);
        dist.depositYield{value: 1 ether}();

        // Operator claims once
        vm.prank(operator);
        dist.claim();

        // Second claim should revert
        vm.prank(operator);
        vm.expectRevert("No yield to claim");
        dist.claim();
    }

    function test_MultipleDeposits() public {
        (FractionToken token, YieldDistributor dist) = _fullSetup();

        vm.prank(operator);
        token.transfer(investorA, 5000);

        // First deposit
        vm.deal(operator, 2 ether);
        vm.prank(operator);
        dist.depositYield{value: 1 ether}();

        // Second deposit
        vm.prank(operator);
        dist.depositYield{value: 1 ether}();

        // Each holds 50%, so 1 ETH each total
        assertApproxEqAbs(dist.claimable(operator), 1 ether, 1);
        assertApproxEqAbs(dist.claimable(investorA), 1 ether, 1);
    }

    function test_YieldPreservedAcrossTransfer() public {
        (FractionToken token, YieldDistributor dist) = _fullSetup();

        // Deposit yield while operator holds all shares
        vm.deal(operator, 1 ether);
        vm.prank(operator);
        dist.depositYield{value: 1 ether}();

        // Transfer shares to investorA — auto-checkpoint preserves operator's yield
        vm.prank(operator);
        token.transfer(investorA, 10000);

        // Operator should still have ~1 ETH claimable (earned before transfer)
        assertApproxEqAbs(dist.claimable(operator), 1 ether, 1);
        // InvestorA should have 0 (joined after deposit)
        assertEq(dist.claimable(investorA), 0);
    }

    // ===============================================================
    //  6. CHECKPOINT
    // ===============================================================

    function test_CheckpointMany() public {
        (FractionToken token, YieldDistributor dist) = _fullSetup();

        vm.startPrank(operator);
        token.transfer(investorA, 2500);
        token.transfer(investorB, 2500);
        vm.stopPrank();

        vm.deal(operator, 1 ether);
        vm.prank(operator);
        dist.depositYield{value: 1 ether}();

        address[] memory holders = new address[](2);
        holders[0] = investorA;
        holders[1] = investorB;
        dist.checkpointMany(holders);

        // After checkpoint, pending yield is snapshotted
        assertApproxEqAbs(dist.unclaimedYield(investorA), 0.25 ether, 1);
        assertApproxEqAbs(dist.unclaimedYield(investorB), 0.25 ether, 1);
    }

    function test_CheckpointMany_BatchLimit() public {
        (, YieldDistributor dist) = _fullSetup();

        address[] memory holders = new address[](201);
        for (uint256 i = 0; i < 201; i++) {
            holders[i] = address(uint160(i + 1000));
        }

        vm.expectRevert("Batch too large");
        dist.checkpointMany(holders);
    }

    // ===============================================================
    //  7. OPERATOR TRANSFER
    // ===============================================================

    function test_TransferOperator() public {
        _registerAsset();
        address newOp = makeAddr("newOperator");

        vm.prank(operator);
        vault.transferOperator(0, newOp);

        assertEq(vault.operatorOf(0), newOp);
    }

    function test_TransferOperator_OnlyCurrentOperator() public {
        _registerAsset();

        vm.prank(stranger);
        vm.expectRevert("Not the operator");
        vault.transferOperator(0, stranger);
    }

    function test_TransferOperator_RejectsZero() public {
        _registerAsset();

        vm.prank(operator);
        vm.expectRevert("Invalid operator");
        vault.transferOperator(0, address(0));
    }

    function test_NewOperatorCanDepositYield() public {
        (FractionToken token, YieldDistributor dist) = _fullSetup();
        address newOp = makeAddr("newOperator");

        vm.prank(operator);
        vault.transferOperator(0, newOp);

        // Old operator cannot deposit
        vm.deal(operator, 1 ether);
        vm.prank(operator);
        vm.expectRevert("Not the operator");
        dist.depositYield{value: 1 ether}();

        // New operator can deposit
        vm.deal(newOp, 1 ether);
        vm.prank(newOp);
        dist.depositYield{value: 1 ether}();
    }

    // ===============================================================
    //  8. REDEEM ASSET
    // ===============================================================

    function test_RedeemAsset() public {
        (FractionToken token,) = _fullSetup();

        // Operator holds 100% — approve vault to burn
        vm.startPrank(operator);
        token.approve(address(vault), 10000);
        vault.redeemAsset(0);
        vm.stopPrank();

        // NFT returned to operator
        assertEq(vault.ownerOf(0), operator);
        // Shares burned
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(operator), 0);
    }

    function test_RedeemAsset_MustOwn100Percent() public {
        (FractionToken token,) = _fullSetup();

        vm.prank(operator);
        token.transfer(investorA, 1);

        vm.prank(operator);
        vm.expectRevert("Must own 100% of shares");
        vault.redeemAsset(0);
    }

    function test_RedeemAsset_NotLocked() public {
        _registerAsset();
        // Asset not fractionalized, so not locked
        vm.prank(operator);
        vm.expectRevert("Asset not locked");
        vault.redeemAsset(0);
    }

    function test_RedeemAsset_AfterReaccumulation() public {
        (FractionToken token,) = _fullSetup();

        // Distribute shares then re-accumulate
        vm.prank(operator);
        token.transfer(investorA, 5000);

        vm.prank(investorA);
        token.transfer(operator, 5000);

        // Now operator has 100% again
        vm.startPrank(operator);
        token.approve(address(vault), 10000);
        vault.redeemAsset(0);
        vm.stopPrank();

        assertEq(vault.ownerOf(0), operator);
        assertEq(token.totalSupply(), 0);
    }

    // ===============================================================
    //  9. SHARE SALE
    // ===============================================================

    function test_ShareSale_FullFlow() public {
        (FractionToken token,) = _fullSetup();

        ShareSale sale = new ShareSale(address(token), operator, 0);

        // Operator approves sale contract and configures
        vm.startPrank(operator);
        token.approve(address(sale), 5000);
        sale.configureSale(0.01 ether, true);
        vm.stopPrank();

        // Investor buys 100 shares
        uint256 cost = sale.quote(100);
        assertEq(cost, 1 ether);

        vm.deal(investorA, 1 ether);
        vm.prank(investorA);
        sale.buyShares{value: 1 ether}(100);

        assertEq(token.balanceOf(investorA), 100);
        assertEq(sale.pendingProceeds(), 1 ether);

        // Operator withdraws proceeds
        uint256 balBefore = operator.balance;
        vm.prank(operator);
        sale.withdrawProceeds();
        assertEq(operator.balance - balBefore, 1 ether);
    }

    function test_ShareSale_OnlyOperatorConfigure() public {
        (FractionToken token,) = _fullSetup();
        ShareSale sale = new ShareSale(address(token), operator, 0);

        vm.prank(stranger);
        vm.expectRevert("Only operator");
        sale.configureSale(0.01 ether, true);
    }

    function test_ShareSale_InactiveSale() public {
        (FractionToken token,) = _fullSetup();
        ShareSale sale = new ShareSale(address(token), operator, 0);

        vm.deal(investorA, 1 ether);
        vm.prank(investorA);
        vm.expectRevert("Sale is not active");
        sale.buyShares{value: 1 ether}(100);
    }

    function test_ShareSale_IncorrectETH() public {
        (FractionToken token,) = _fullSetup();
        ShareSale sale = new ShareSale(address(token), operator, 0);

        vm.startPrank(operator);
        token.approve(address(sale), 5000);
        sale.configureSale(0.01 ether, true);
        vm.stopPrank();

        vm.deal(investorA, 2 ether);
        vm.prank(investorA);
        vm.expectRevert("Incorrect ETH amount");
        sale.buyShares{value: 0.5 ether}(100);
    }

    function test_ShareSale_NoProceeds() public {
        (FractionToken token,) = _fullSetup();
        ShareSale sale = new ShareSale(address(token), operator, 0);

        vm.prank(operator);
        vm.expectRevert("No proceeds");
        sale.withdrawProceeds();
    }

    // ===============================================================
    // 10. FULL LIFECYCLE (END-TO-END)
    // ===============================================================

    function test_FullLifecycle() public {
        // 1. Register asset (admin registers on behalf of operator)
        uint256 id = vault.registerAsset("ABB Terra 184", "Charge Holdings", "Orchard Road SG", operator);

        // 2. Fractionalize
        vm.prank(operator);
        address tokenAddr = factory.fractionalize(id, 10000, "YieldLayer EV 0", "YLEV0");
        FractionToken token = FractionToken(tokenAddr);

        // 3. Deploy distributor and link
        YieldDistributor dist = new YieldDistributor(tokenAddr);
        vm.prank(operator);
        token.setDistributor(address(dist));

        // 4. Transfer shares
        vm.startPrank(operator);
        token.transfer(investorA, 2500);
        token.transfer(investorB, 2500);
        vm.stopPrank();

        // 5. Deposit yield (1 ETH)
        vm.deal(operator, 1 ether);
        vm.prank(operator);
        dist.depositYield{value: 1 ether}();

        // 6. Verify claimable
        assertApproxEqAbs(dist.claimable(operator), 0.5 ether, 1);
        assertApproxEqAbs(dist.claimable(investorA), 0.25 ether, 1);
        assertApproxEqAbs(dist.claimable(investorB), 0.25 ether, 1);

        // 7. Everyone claims
        vm.prank(operator);
        dist.claim();
        vm.prank(investorA);
        dist.claim();
        vm.prank(investorB);
        dist.claim();

        // 8. Re-accumulate shares to operator
        vm.prank(investorA);
        token.transfer(operator, 2500);
        vm.prank(investorB);
        token.transfer(operator, 2500);

        assertEq(token.balanceOf(operator), 10000);

        // 9. Redeem NFT
        vm.startPrank(operator);
        token.approve(address(vault), 10000);
        vault.redeemAsset(id);
        vm.stopPrank();

        assertEq(vault.ownerOf(id), operator);
        assertEq(token.totalSupply(), 0);
    }

    // ===============================================================
    // 11. SECURITY: ACCESS CONTROL
    // ===============================================================

    function test_LockAsset_OnlyFactory() public {
        _registerAsset();

        vm.prank(stranger);
        vm.expectRevert("Only factory");
        vault.lockAsset(0, operator);
    }

    // ===============================================================
    // 12. SECURITY: REENTRANCY (via malicious receiver)
    // ===============================================================

    function test_Claim_ReentrancyBlocked() public {
        (FractionToken token, YieldDistributor dist) = _fullSetup();

        // Deploy attacker contract
        ReentrancyAttacker attacker = new ReentrancyAttacker(dist);

        // Give attacker some shares
        vm.prank(operator);
        token.transfer(address(attacker), 5000);

        // Deposit yield
        vm.deal(operator, 1 ether);
        vm.prank(operator);
        dist.depositYield{value: 1 ether}();

        // Attacker tries reentrancy — should revert
        vm.expectRevert();
        attacker.attack();
    }
}

// Malicious contract that tries to re-enter claim()
contract ReentrancyAttacker {
    YieldDistributor dist;
    uint256 count;

    constructor(YieldDistributor _dist) {
        dist = _dist;
    }

    function attack() external {
        dist.claim();
    }

    receive() external payable {
        if (count < 1) {
            count++;
            dist.claim();
        }
    }
}
