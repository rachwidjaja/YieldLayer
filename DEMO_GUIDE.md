# YieldLayer - Remix Demo Guide

## Contract deployment order
Always deploy in this order. Each contract depends on the one before it.

---

## Step 1 - Deploy AssetVault.sol
- No constructor arguments needed
- Copy the deployed contract address (you will need it for Step 3)

## Step 2 - Register an EV charging station (Operator)
- Call: `registerAsset`
- Arguments:
  - model: "ABB Terra 184"
  - operatorName: "Charge Holdings Pte Ltd"
  - location: "Orchard Road, Singapore"
- Returns: token ID 0
- Check: call `getAsset(0)` to confirm metadata stored correctly

---

## Step 3 - Deploy FractionFactory.sol
- Constructor argument: paste the AssetVault address from Step 1

## Step 4 - Fractionalize the asset (Operator)
- Call: `fractionalize`
- Arguments:
  - assetId: 0
  - totalShares: 10000
  - name: "YieldLayer EV Station 0"
  - symbol: "YLEV0"
- Returns: address of the new FractionToken contract
- Copy this FractionToken address (you need it for Steps 5 and 6)

---

## Step 5 - Deploy FractionToken (already deployed - just load it)
- In Remix: select FractionToken.sol, paste the address from Step 4 into "At Address"
- This loads the existing contract so you can call it

## Step 6 - Sell shares to investors (Operator transfers tokens)
- Switch to a second account in Remix (Investor A)
- In FractionToken: call `transfer` from the operator account
  - to: Investor A address
  - amount: 2500 (25% of 10000 shares)
- Repeat for Investor B: transfer 2500 more shares to a third account

---

## Step 7 - Deploy YieldDistributor.sol
- Constructor argument: paste the FractionToken address from Step 4

## Step 8 - Deposit yield (Operator)
- Switch back to the operator account
- Call: `depositYield`
- Set VALUE to 1 ETH (use the value field at the top of Remix)
- This represents one week of EV charging revenue

## Step 9 - Check claimable yield (Investors)
- Call: `claimable(investorA_address)` - should show 0.25 ETH (25% of 1 ETH)
- Call: `claimable(investorB_address)` - should show 0.25 ETH

## Step 10 - Claim yield (Investors)
- Switch to Investor A account
- Call: `claim`
- Check Investor A balance in Remix - ETH increased by 0.25
- Repeat for Investor B

---

## Demo narrative (say this out loud during presentation)

1. "The operator registers their EV charging station on-chain as an NFT"
2. "They fractionalize it into 10,000 shares - democratizing ownership"
3. "Investors buy shares by receiving ERC20 tokens from the operator"
4. "Every week, the operator deposits the station's revenue into the distributor"
5. "Investors claim their proportional share trustlessly - no bank, no broker"

---

## Key design decisions to explain in Q&A

- Why ERC721 + ERC20 separately instead of ERC-404:
  ERC-404 is unofficial and unaudited. Separation of concerns is cleaner
  and matches how production protocols like Fractional.art work.

- Why yieldPerToken scaling by 1e18:
  Solidity has no floating point. Without scaling, small deposits divided
  by large share counts would round to zero. 1e18 preserves precision.

- Why state is cleared before ETH transfer in claim():
  Reentrancy protection. If we sent ETH first, a malicious contract could
  call claim() again before the balance is zeroed.
