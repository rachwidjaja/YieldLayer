# YieldLayer

YieldLayer is a smart contract MVP for fractional ownership of productive real-world assets.

In this demo, an EV charging station is:
1. registered on-chain as an ERC721 NFT,
2. fractionalized into ERC20 share tokens,
3. used to distribute ETH yield to investors pro-rata, and
4. redeemable once one wallet re-accumulates 100% of the shares.

---

## Contracts

### `AssetVault.sol`
Registers physical assets as ERC721 NFTs.

After fractionalization, the NFT is locked in the vault. If a wallet later owns 100% of the fractional shares, it can redeem the original NFT.

### `FractionFactory.sol`
Creates a new `FractionToken` for an asset and locks the original NFT in the vault.

### `FractionToken.sol`
ERC20 token representing fractional ownership of one specific asset.

### `YieldDistributor.sol`
Accepts ETH revenue deposits and lets token holders claim yield based on share ownership.

---

## Core flow

1. Operator registers an asset as an NFT
2. Operator fractionalizes the asset into ERC20 shares
3. Investors receive shares
4. Operator deposits revenue as ETH
5. Investors claim yield pro-rata
6. A wallet holding 100% of shares can redeem the original NFT

---

## Remix demo guide

### 1. Deploy `AssetVault.sol`
No constructor arguments.

Save the deployed address as:

`VAULT_ADDRESS`

---

### 2. Deploy `FractionFactory.sol`
Constructor:

- `_vault` = `VAULT_ADDRESS`

Save the deployed address as:

`FACTORY_ADDRESS`

---

### 3. Link the vault to the factory
On `AssetVault`, call:

`setFactory(FACTORY_ADDRESS)`

---

### 4. Register an EV charging station
On `AssetVault`, call `registerAsset` with:

- `model` = `ABB Terra 184`
- `operatorName` = `Charge Holdings Pte Ltd`
- `location` = `Orchard Road Singapore`

Checks:
- `nextTokenId()` → `1`
- `ownerOf(0)` → operator address
- `getAsset(0)` → stored metadata

---

### 5. Fractionalize the asset
On `FractionFactory`, call `fractionalize` with:

- `assetId` = `0`
- `totalShares` = `10000`
- `name` = `YieldLayer EV Station 0`
- `symbol` = `YLEV0`

What happens:
- the NFT is locked in `AssetVault`
- a new `FractionToken` is deployed
- all 10,000 shares are minted to the operator

Checks:
- `AssetVault.ownerOf(0)` → `VAULT_ADDRESS`
- `FractionFactory.fractionsFor(0)` → token address

Save the returned token address as:

`TOKEN_ADDRESS`

---

### 6. Load the deployed `FractionToken`
Do **not** deploy `FractionToken` manually.

In Remix:
- select `FractionToken`
- use **At Address** / **Add Contract**
- paste `TOKEN_ADDRESS`

Checks:
- `totalSupply()` → `10000`
- `balanceOf(operator)` → `10000`

---

### 7. Deploy `YieldDistributor.sol`
Constructor:

- `_token` = `TOKEN_ADDRESS`

Save the deployed address as:

`DISTRIBUTOR_ADDRESS`

---

### 8. Transfer shares to investors
Use extra Remix VM accounts as investors.

Before transfers, call on `YieldDistributor`:
- `checkpoint(operator)`
- `checkpoint(investorAddress)`

Then on `FractionToken`, call `transfer(...)`.

Example:
- Investor A receives `2500`
- Investor B receives `2500`

After this:
- Operator holds `5000`
- Investor A holds `2500`
- Investor B holds `2500`

---

### 9. Deposit yield
On `YieldDistributor`:
- set **Value** = `1 ether`
- call `depositYield()`

This represents asset revenue.

---

### 10. Check claimable yield
On `YieldDistributor`, call:

- `claimable(operator)` → about `0.5 ETH`
- `claimable(investorA)` → about `0.25 ETH`
- `claimable(investorB)` → about `0.25 ETH`

---

### 11. Claim yield
Switch accounts and call `claim()` from each wallet.

---

## Redeeming the asset

If one wallet later owns 100% of the shares, it can redeem the original NFT.

### 12. Re-accumulate 100% of shares
Transfer all shares back to one wallet.

Check:
- `balanceOf(redeemer)` → `10000`

### 13. Preserve any remaining yield
Before redeeming, on `YieldDistributor` either:
- call `claim()`, or
- call `checkpoint(redeemer)`

### 14. Approve the vault to burn shares
On `FractionToken`, call:

`approve(VAULT_ADDRESS, 10000)`

Check:
- `allowance(redeemer, VAULT_ADDRESS)` → `10000`

### 15. Redeem the NFT
On `AssetVault`, call:

`redeemAsset(0)`

Expected result:
- all shares are burned
- the NFT is transferred from the vault back to the redeemer

Checks:
- `FractionToken.totalSupply()` → `0`
- `FractionToken.balanceOf(redeemer)` → `0`
- `AssetVault.ownerOf(0)` → redeemer address

---

## Design decisions

### Why ERC721 + ERC20 instead of ERC-404
We separated the asset NFT and the share token for clarity and modularity.

This makes the system:
- easier to explain,
- easier to test in Remix,
- and less dependent on an experimental token standard.

### Why `yieldPerToken` uses `1e18`
Solidity does not support floating point arithmetic.

Scaling by `1e18` preserves precision when calculating yield per share.

### Why `claim()` clears state before sending ETH
This follows the checks-effects-interactions pattern and reduces reentrancy risk.

### Why `checkpoint()` exists
Yield depends on current token balances.

Before balances change through transfers, burns, or redemption, `checkpoint()` snapshots accrued rewards into `unclaimedYield` so they are not lost.

### Why redeemed assets are not fractionalized again under the same token ID
Once redeemed, that fractionalization cycle is considered closed.

If an operator wants to fractionalize again later, the asset should be registered again as a new NFT with a new lifecycle.

---

## Notes

- This is an MVP demo tested in Remix
- Share transfers are manual in this version
- Yield checkpointing before balance changes is manual in this version
- The full lifecycle works:
  - register
  - fractionalize
  - transfer shares
  - deposit yield
  - claim yield
  - redeem asset sent ETH first, a malicious contract could
  call claim() again before the balance is zeroed.
