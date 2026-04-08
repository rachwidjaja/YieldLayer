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

---

## Roles

### Admin
The deployer of `AssetVault`. Can set the factory address via `setFactory`.

### Operator
The address that called `registerAsset` for a given asset. Stored permanently in `operatorOf[tokenId]` and persists even after the NFT is locked.

Operator-gated functions:
- `AssetVault.transferOperator` — hand off the operator role to a new address
- `YieldDistributor.depositYield` — only the operator can deposit revenue
- `FractionToken.setDistributor` — only the operator can link the yield distributor

### Investor
Any address holding `FractionToken` shares. Can call `claim()` to withdraw accrued yield.

---

## Core flow

1. Operator registers an asset as an NFT
2. Operator fractionalizes the asset into ERC20 shares
3. Operator links the yield distributor to the fraction token
4. Investors receive shares (auto-checkpointed)
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
On `AssetVault`, call `registerAsset` with:

- `model` = `ABB Terra 184`
- `operatorName` = `Charge Holdings Pte Ltd`
- `location` = `Orchard Road Singapore`

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

## Transferring operator role

The operator can hand off their role to a new address at any time.

On `AssetVault`, call:

`transferOperator(0, newOperatorAddress)`

After this, only the new operator can deposit yield or link distributors for asset 0.

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

### Why `redeemAsset()` transfers the NFT before burning shares
This follows the checks-effects-interactions pattern: the internal state change (NFT transfer) happens before the external call (`burnFrom`). Reentry is blocked because `ownerOf(tokenId)` no longer returns the vault address after the transfer.

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

## Notes

- This is an MVP demo tested in Remix
- Share transfers are auto-checkpointed when a distributor is linked
- The full lifecycle works:
  - register
  - fractionalize
  - link distributor
  - transfer shares
  - deposit yield
  - claim yield
  - redeem asset
