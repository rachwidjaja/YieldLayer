# YieldLayer - Simple Remix Demo

This is a short happy-path demo focused on one message:
An operator tokenizes one asset, sells ownership as shares, deposits revenue, and investors claim yield.

## Quick Story (30 seconds)
1. Register one EV charger as an NFT.
2. Fractionalize into 10,000 ERC20 shares.
3. Sell shares on-chain via ShareSale.
4. Deposit 1 ETH revenue.
5. Investors claim yield instantly on-chain.

## Minimal Setup

- Account 1: Admin and Operator
- Account 2: Investor A
- Account 3: Investor B
- Account 4: Redeemer
- Use totalShares = 10000
- Sell 2500 shares to A and 2500 shares to B via ShareSale
- Deposit 1 ETH as yield

## Fast Demo Steps

### Step 1 - Deploy AssetVault
- Deploy AssetVault with no arguments.
- Save as vaultAddress.
- What happens:
  A new ERC721 vault contract is created. This will be the canonical registry for real-world assets.
- Why we do it:
  Every later step depends on this vault as the source of truth for asset ownership.

### Step 2 - Register asset
- On AssetVault call:
  - registerAsset("ABB Terra 184", "Charge Holdings Pte Ltd", "Orchard Road, Singapore")
- Result should be tokenId 0.
- What happens:
  The operator mints one NFT representing the physical EV charger and stores metadata on-chain.
- Why we do it:
  We need an asset NFT first before we can fractionalize ownership.

### Step 3 - Deploy FractionFactory
- Deploy FractionFactory with vaultAddress.
- Save as factoryAddress.
- What happens:
  A factory contract is deployed that can lock NFTs and spawn token, distributor, and sale contracts.
- Why we do it:
  It automates fractionalization so each asset gets its own coordinated contract set.

### Step 4 - Link vault and factory
- On AssetVault call:
  - setFactory(factoryAddress)
- What happens:
  The vault authorizes this factory as the only contract allowed to lock assets and bind fraction tokens.
- Why we do it:
  This is an access-control safety check so arbitrary contracts cannot manipulate vault lifecycle actions.

### Step 5 - Fractionalize
- On FractionFactory call:
  - fractionalize(0, 10000, "YieldLayer EV Station 0", "YLEV0")
- Then read:
  - fractionsFor(0)
  - distributorFor(0)
  - saleContractFor(0)
- Save these addresses.
- What happens:
  The NFT is moved into vault custody, a new ERC20 share token is minted, and matching YieldDistributor plus ShareSale contracts are deployed.
- Why we do it:
  This turns one illiquid asset NFT into investable shares and creates the contracts needed for sales and payouts.

### Step 6 - Load child contracts
- In Remix At Address:
  - Load FractionToken at fractionsFor(0)
  - Load YieldDistributor at distributorFor(0)
  - Load ShareSale at saleContractFor(0)
- What happens:
  Remix attaches to already-deployed contracts so you can call their functions directly.
- Why we do it:
  These contracts were created by the factory, so loading by address is required for interaction.

### Step 7 - Configure sale once
- From operator on ShareSale:
  - configureSale(100000000000000, true)
- From operator on FractionToken:
  - approve(shareSaleAddress, 5000)
- What happens:
  The operator sets a fixed share price and opens the sale, then grants ShareSale permission to transfer 5000 operator-held shares.
- Why we do it:
  Buyers need a price and transfer allowance, otherwise purchases will revert.

### Step 8 - Investors buy shares
- from either Investor A or B, call quote (2500). output is the amount to be put in VALUE
- Investor A on ShareSale:
  - buyShares(2500) with VALUE = quote(2500)
- Investor B on ShareSale:
  - buyShares(2500) with VALUE = quote(2500)
- What happens:
  Investors pay ETH to ShareSale and receive shares transferred from operator inventory.
- Why we do it:
  This demonstrates on-chain primary issuance and creates actual investor balances for yield distribution.

### Step 9 - Deposit revenue
- From operator on YieldDistributor:
  - depositYield() with VALUE = 1 ETH
- What happens:
  1 ETH is added to the distributor, and global yieldPerToken is updated based on total share supply.
- Why we do it:
  This simulates real operating revenue and funds investor claims.

### Step 10 - Show claimable amounts
- claimable(investorA) should be about 0.25 ETH
- claimable(investorB) should be about 0.25 ETH
- What happens:
  The contract calculates each holder's pro-rata entitlement from deposited yield.
- Why we do it:
  It proves payout math is transparent and directly tied to token ownership.

### Step 11 - Claim yield
- Investor A calls claim(0)
- Investor B calls claim(0)
- What happens:
  Each investor withdraws their accrued ETH from YieldDistributor to their wallet.
- Why we do it:
  This is the core value proposition: trustless, on-demand revenue distribution.

## Step 12 - Redeem the original NFT (redeemAsset demo)
- Goal:
  Prove end-to-end closure: one wallet can recover the original NFT by owning all shares.

- Exact precondition:
  Redeemer must hold 10000 out of 10000 shares (100%).

- Substep 12.1 - Consolidate shares into Redeemer
  Do these 3 transfers in Remix (switch account before each call):
  
  1) Switch to Investor A account.
    On FractionToken call:
    - transfer(redeemerAddress, 2500)
  2) Switch to Investor B account.
    On FractionToken call:
    - transfer(redeemerAddress, 2500)
  3) Switch to Operator account.
    On FractionToken call:
    - transfer(redeemerAddress, remainingOperatorShares)

  In this demo, remainingOperatorShares is usually 5000.
  If it is not 5000 in your run, first check balanceOf(operator), then transfer that exact value.

- Substep 12.2 - Confirm Redeemer has 100%
  On FractionToken, check:
  - balanceOf(redeemer) should be 10000
  - totalSupply() should be 10000
  If these are not equal, do not redeem yet.

- Substep 12.3 - Approve vault to burn shares
  Switch to Redeemer account.
  On FractionToken call:
  - approve(vaultAddress, 10000)

- Substep 12.4 - Execute redemption
  Still on Redeemer account.
  On AssetVault call:
  - redeemAsset(0)
  Send 0 ETH value for this call.

- Substep 12.5 - Verify success
  - AssetVault.ownerOf(0) == redeemer
  - FractionToken.totalSupply() == 0
  - AssetVault.isLocked(0) == false

- Common redeem errors and fixes
  - "Must own 100% of shares": Redeemer still does not hold all shares.
  - "ERC20: insufficient allowance": approve(vaultAddress, 10000) was not done or too low.
  - "Asset not locked": the asset was not fractionalized/locked correctly before redeem.

- What happens:
  Vault burns all Redeemer shares, unlocks NFT custody, and transfers NFT tokenId 0 to Redeemer.

- Why we do it:
  Demonstrates that fractional ownership can reconverge into single full ownership on-chain.


