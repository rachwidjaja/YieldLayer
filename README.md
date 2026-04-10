# YieldLayer

## Overview

YieldLayer is a smart contract system that enables the tokenization of real-world productive assets into fractional on-chain ownership. Each asset is represented as an ERC-721 NFT and can be fractionalized into ERC-20 tokens, allowing investors to purchase shares and earn yield from the asset’s revenue.

This project demonstrates how illiquid real-world assets (e.g. EV charging stations) can be transformed into accessible, investable instruments with transparent, on-chain revenue distribution.

---

## Core Features

* **Asset Tokenization (ERC-721)**

  * Real-world assets are registered as NFTs in `AssetVault`.

* **Fractional Ownership (ERC-20)**

  * Assets can be fractionalized into ERC-20 tokens representing ownership shares.

* **On-chain Share Sale**

  * `ShareSale` contract enables operators to sell shares directly to investors.

* **Yield Distribution**

  * `YieldDistributor` distributes ETH revenue proportionally to token holders.

* **Full Redemption Mechanism**

  * If one wallet acquires 100% of shares, they can redeem the original NFT.

---

## Architecture

The system consists of the following core contracts:

* `AssetVault`: Registers and locks asset NFTs
* `FractionFactory`: Handles fractionalization and deploys related contracts
* `FractionToken`: ERC-20 token representing fractional ownership
* `ShareSale`: Handles primary sale of shares
* `YieldDistributor`: Distributes ETH yield to investors

---

## Setup Instructions

---
## Quick Start (Run in Remix)

1. Open https://remix.ethereum.org/
2. Upload all `.sol` contract files
3. Compile all contracts using the Solidity Compiler
4. Go to **Deploy & Run Transactions**
5. Select **JavaScript VM (London)** as the environment

### Minimal Run Flow

1. Deploy `AssetVault`
2. Register an asset using `registerAsset(...)`
3. Deploy `FractionFactory` with `vaultAddress`
4. Link vault using `setFactory(factoryAddress)`
5. Call `fractionalize(...)` on `FractionFactory`
6. Retrieve deployed contract addresses using:

   * `fractionsFor(assetId)`
   * `distributorFor(assetId)`
   * `saleContractFor(assetId)`
7. Use **Add Contract** in Remix to load these contracts
8. Configure sale and simulate investors buying shares
9. Deposit yield and call `claim()` as investors

For a full detailed walkthrough, refer to:
👉 `DEMO_readme.md`

---

## Design Choice: Minimal UI

This project intentionally does not include a frontend interface.
All interactions are performed via Remix to ensure:

* Focus on core smart contract logic
* Reliable end-to-end execution
* Simpler reproducibility for grading


---

## Security & Best Practices

* No private keys or secrets are committed
* Environment variables should be stored in `.env` (if used)
* `.env.example` can be used as a template
* Access control enforced (e.g. `onlyAdmin`, `onlyFactory`)
* Contracts follow checks-effects-interactions pattern where applicable

---

## Assumptions & Scope

* This project demonstrates a **happy-path flow**
* Edge cases and production optimizations are intentionally de-scoped
* The focus is on correctness of the core mechanism

---

## Limitations

* No frontend UI (Remix-based interaction only)
* No KYC / compliance layer (future extension)
* No secondary market trading implemented
* No protocol fee mechanism

In the current MVP, all deposited yield is distributed pro-rata to token holders. Protocol-level fees (e.g. platform fees, operator commissions, or treasury allocations) are intentionally excluded and reserved as a future extension.

---

## Future Improvements

ComplianceAndLifecycleManager (Future Extension)

A planned module to enforce participant eligibility and manage asset lifecycle policies in a real-world regulatory context.

This component would introduce:

* **KYC / Allowlist Enforcement**: Restrict share purchases to verified participants
* **Jurisdiction Controls**: Enforce geographic or regulatory constraints on investors
* **Post-Redemption Policies**: Define what happens after full ownership is reconsolidated, such as:

  * Whether the asset can be re-fractionalized
  * Whether ownership becomes permanently private
  * Whether additional compliance checks are required before reuse

This extension addresses current limitations where:

* Any address can participate in share purchases during an active sale
* No explicit lifecycle rules exist after redemption

By introducing this module, the system would better align with real-world regulatory requirements and provide clearer governance over the full lifecycle of tokenized assets.

---

## Conclusion

YieldLayer demonstrates how blockchain can enable transparent, efficient, and accessible investment in real-world assets through tokenization and smart contracts. The system prioritizes correctness and clarity of core functionality over UI complexity, ensuring a reliable and demonstrable end-to-end workflow.
