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
Registers physical assets as ERC721 NFTs. Tracks the **operator** of each asset permanently via `operatorOf`.

After fractionalization, the NFT is locked in the vault. If a wallet later owns 100% of the fractional shares, it can redeem the original NFT.

### `FractionFactory.sol`
Creates a new `FractionToken` for an asset and locks the original NFT in the vault.

### `FractionToken.sol`
ERC20 token representing fractional ownership of one specific asset.

When linked to a `YieldDistributor`, every transfer and burn automatically checkpoints both parties so accrued yield is never lost.

### `YieldDistributor.sol`
Accepts ETH revenue deposits (operator-only) and lets token holders claim yield based on share ownership. Protected by `ReentrancyGuard`.

### `ShareSale.sol`
Manages the on-chain primary sale of an asset's fraction tokens. The operator configures a price per share and activates the sale. Investors send ETH to buy shares, which are transferred from the operator's balance via `transferFrom`. The operator can withdraw accumulated sale proceeds. Protected by `ReentrancyGuard`.

---

## Roles

### Admin
The deployer of `AssetVault`. Admin-gated functions:
- `AssetVault.setFactory` — link the factory (one-time only, immutable once set)
- `AssetVault.registerAsset` — register a new asset and assign its operator
- `AssetVault.renounceAdmin` — permanently renounce admin role (only callable after factory is set)

### Operator
The address assigned as operator via the `operator` parameter when the admin calls `registerAsset`. Stored permanently in `operatorOf[tokenId]` and persists even after the NFT is locked.

Operator-gated functions:
- `AssetVault.transferOperator` — hand off the operator role to a new address
- `FractionFactory.fractionalize` — fractionalize the asset (operator must be the NFT owner)
- `FractionToken.setDistributor` — link the yield distributor (one-time only)
- `YieldDistributor.depositYield` — deposit revenue as ETH
- `ShareSale.configureSale` — set share price and activate/deactivate the sale
- `ShareSale.withdrawProceeds` — withdraw accumulated sale proceeds

### Investor
Any address holding `FractionToken` shares. Can call `YieldDistributor.claim()` to withdraw accrued yield, or `ShareSale.buyShares()` to purchase shares from the operator.

---

## Core flow

1. Admin registers an asset as an NFT, assigning an operator
2. Operator fractionalizes the asset into ERC20 shares
3. Operator links the yield distributor to the fraction token
4. Investors receive shares via transfer or ShareSale (auto-checkpointed)
5. Operator deposits revenue as ETH
6. Investors claim yield pro-rata
7. A wallet holding 100% of shares can redeem the original NFT

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
On `AssetVault` (from the admin account), call `registerAsset` with:

- `model` = `ABB Terra 184`
- `operatorName` = `Charge Holdings Pte Ltd`
- `location` = `Orchard Road Singapore`
- `operator` = the address you want to assign as the asset operator

Checks:
- `nextTokenId()` → `1`
- `ownerOf(0)` → operator address
- `getAsset(0)` → stored metadata
- `operatorOf(0)` → operator address

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

### 8. Link the distributor to the token
On `FractionToken`, call (from the operator account):

`setDistributor(DISTRIBUTOR_ADDRESS)`

This enables automatic yield checkpointing on every share transfer.

Checks:
- `FractionToken.distributor()` → `DISTRIBUTOR_ADDRESS`

---

### 9. Transfer shares to investors
Use extra Remix VM accounts as investors.

On `FractionToken`, call `transfer(...)`.

Example:
- Investor A receives `2500`
- Investor B receives `2500`

Both parties are auto-checkpointed by the `_update` hook — no manual checkpoint needed.

After this:
- Operator holds `5000`
- Investor A holds `2500`
- Investor B holds `2500`

---

### 10. Deposit yield
On `YieldDistributor` (from the operator account):
- set **Value** = `1 ether`
- call `depositYield()`

This represents asset revenue. Only the registered operator can call this.

---

### 11. Check claimable yield
On `YieldDistributor`, call:

- `claimable(operator)` → about `0.5 ETH`
- `claimable(investorA)` → about `0.25 ETH`
- `claimable(investorB)` → about `0.25 ETH`

---

### 12. Claim yield
Switch accounts and call `claim()` from each wallet.

---

## Redeeming the asset

If one wallet later owns 100% of the shares, it can redeem the original NFT.

### 13. Re-accumulate 100% of shares
Transfer all shares back to one wallet. Auto-checkpointing preserves yield during these transfers.

Check:
- `balanceOf(redeemer)` → `10000`

### 14. Claim any remaining yield
Before redeeming, on `YieldDistributor`:
- call `claim()` from the redeemer account

### 15. Approve the vault to burn shares
On `FractionToken`, call:

`approve(VAULT_ADDRESS, 10000)`

Check:
- `allowance(redeemer, VAULT_ADDRESS)` → `10000`

### 16. Redeem the NFT
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

## Selling shares via ShareSale (optional)

Instead of manually transferring shares, the operator can set up an on-chain primary sale.

### Deploy `ShareSale.sol`
Constructor:

- `_token` = `TOKEN_ADDRESS`
- `_operator` = operator address
- `_assetId` = `0`

Save the deployed address as:

`SALE_ADDRESS`

### Approve the sale contract
On `FractionToken` (from the operator account), call:

`approve(SALE_ADDRESS, <number of shares to sell>)`

### Configure the sale
On `ShareSale` (from the operator account), call `configureSale` with:

- `_pricePerShareWei` = price per share in wei (e.g. `1000000000000000` for 0.001 ETH)
- `_isActive` = `true`

### Buy shares
Switch to an investor account. On `ShareSale`, call `buyShares` with:

- `shareAmount` = number of shares to buy
- **Value** = `shareAmount * pricePerShareWei` (must be exact)

### Withdraw proceeds
On `ShareSale` (from the operator account), call `withdrawProceeds()`.

---

## Transferring operator role

The operator can hand off their role to a new address at any time.

On `AssetVault`, call:

`transferOperator(0, newOperatorAddress)`

After this, only the new operator can deposit yield or link distributors for asset 0.

---

## Redeem Asset Logic
A wallet can only redeem the asset once it holds 100% of the shares.

The process involves:
1. Transferring all shares back to one wallet.
2. Calling redeemAsset to release the original asset NFT back to the wallet.
Auto-checkpointing ensures that no yield is lost during share transfers.

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

### Why `claim()` uses `ReentrancyGuard` and clears state before sending ETH
`claim()` follows the checks-effects-interactions pattern (state cleared before the ETH transfer) and is additionally protected by OpenZeppelin's `nonReentrant` modifier for defense-in-depth.

### Why `redeemAsset()` burns shares before transferring the NFT
This follows the checks-effects-interactions pattern: the external call (`burnFrom`) happens first to eliminate the caller's share ownership, then the NFT is transferred. The function is also protected by `nonReentrant`.

### Why `FractionToken._update` auto-checkpoints
Yield depends on current token balances. Without automatic checkpointing, a seller could lose accrued yield to the buyer if they forgot to checkpoint before transferring. The `_update` override eliminates this footgun.

### Why `depositYield` is operator-only
Prevents anyone from depositing misleading yield amounts. Investors can trust that deposited revenue came from the verified operator of the asset.

### Why `checkpointMany` is bounded
Capped at 200 addresses per call to prevent gas-limit DoS from unbounded loops.

### Why redeemed assets are not fractionalized again under the same token ID
Once redeemed, that fractionalization cycle is considered closed.

If an operator wants to fractionalize again later, the asset should be registered again as a new NFT with a new lifecycle.

---

## Renouncing admin

The admin can permanently renounce their role after the factory is set. On `AssetVault`, call:

`renounceAdmin()`

After this, no new assets can be registered and the factory address cannot be changed.

---

## Notes

- This is an MVP demo tested in Remix
- Share transfers are auto-checkpointed when a distributor is linked
- `setFactory` and `setDistributor` are each one-time only — they cannot be changed once set
- The full lifecycle works:
  - register (admin)
  - fractionalize (operator)
  - link distributor (operator)
  - transfer shares or sell via ShareSale
  - deposit yield (operator)
  - claim yield (investor)
  - redeem asset (100% holder)
