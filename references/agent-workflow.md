# Agent Workflow Guide

How an AI agent should approach a confidential-contract request — from natural language prompt to deployed dApp.

This file is meta-guidance: it tells the agent **how to think** about an FHEVM task.

---

## Step 1 — Classify the request

Listen for keywords and route to the right pattern:

| User says... | Pattern | Example file |
|---|---|---|
| "private balance", "encrypted token", "confidential ERC20" | ERC-7984 or custom encrypted ERC20 | `examples/ConfidentialToken.sol`, `examples/EncryptedERC20.sol` |
| "blind auction", "sealed bid", "private bidding" | encrypted max accumulator + oracle reveal | `examples/SealedBidAuction.sol`, `examples/BlindAuction.sol` |
| "private vote", "encrypted DAO", "anonymous voting" | encrypted counter increment + oracle tally | `examples/ConfidentialVoting.sol` |
| "encrypted lottery", "fair draw", "private raffle" | `FHE.randEuint*` + oracle reveal | `examples/EncryptedLottery.sol` |
| "private payroll", "encrypted salary" | ERC-7984 + transient ACL pattern | `examples/ConfidentialPayroll.sol` |
| "KYC", "encrypted identity", "age proof", "selective disclosure" | per-field encrypted struct + ACL gating | `examples/EncryptedIdentity.sol` |
| "encrypted counter", "private number" | store-and-grant pattern | `examples/ConfidentialCounter.sol` |

If it's something new, compose patterns from `references/patterns.md`.

---

## Step 2 — Pick the network

Default: **Sepolia** (canonical FHEVM testnet). Inherit `SepoliaConfig`. If user mentions "mainnet" — check for current network availability and warn that mainnet may not be live yet.

For tests: hardhat mock mode (free, instant). For demos: Sepolia.

---

## Step 3 — Sketch the data model

For every piece of state, ask:
- Plaintext or encrypted? (encrypt anything user-private)
- Which encrypted type? (smallest that fits)
- Who can decrypt? (the user themselves, the contract for processing, or publicly after a reveal)
- When do they get ACL? (in the producing function — never afterwards, ACL doesn't propagate retroactively cleanly)

Example, for a confidential auction:

| Field | Type | ACL |
|---|---|---|
| `bidder address` | plaintext | n/a |
| `bid amount` | `euint64` | bidder + contract; revealed publicly to winner only |
| `highest bid (running)` | `euint64` | contract only |
| `highest bidder (running)` | `eaddress` | contract only |
| `auction end time` | plaintext | n/a |
| `revealed winning bid` | plaintext (after oracle decrypt) | n/a |

---

## Step 4 — Write the contract following the rules

For every state-mutating function, follow the script:

```
1. Validate inputs:        FHE.fromExternal(handle, proof) for any external param
2. Compute:                FHE operations
3. Store:                  state[...] = computed_handle
4. ACL the contract:       FHE.allowThis(state[...])
5. ACL the user:           FHE.allow(state[...], msg.sender)
6. Emit event              (plaintext metadata only — never plaintext encrypted values)
```

Skip step 5 for purely-internal state (e.g. running max in an auction; the user shouldn't be able to decrypt it).

---

## Step 5 — Write the tests

Cover at minimum:
- ✅ Happy path (single user, expected behaviour)
- ✅ Multiple users (each must build their own input proof)
- ✅ Unauthorized decrypt rejected (user not on ACL)
- ✅ Oracle async callback (use `await fhevm.awaitDecryptionOracle()`)
- ✅ Wrong-signer input proof rejected
- ✅ State invariants after edge cases (insufficient balance, duplicate vote, etc.)

---

## Step 6 — Deploy

Use a deploy script (`hardhat-deploy` style or vanilla):

```ts
import { ethers } from "hardhat";

async function main() {
    const [deployer] = await ethers.getSigners();
    const c = await ethers.deployContract("MyContract", [/* args */], deployer);
    await c.waitForDeployment();
    console.log("Deployed:", await c.getAddress());
}
main().catch(e => { console.error(e); process.exit(1); });
```

```bash
npx hardhat --network sepolia run scripts/deploy.ts
```

---

## Step 7 — Build the frontend (when asked)

Pattern: `useFhevm` hook → `createEncryptedInput → encrypt → tx → user-decrypt`.

The skill's `examples/frontend.ts` is a drop-in template. Customize:
1. ABI matches contract
2. `add32`/`add64` matches the `externalEuintN` types
3. User-decrypt only handles the user has been granted `FHE.allow` for

---

## Step 8 — Verify the agent-generated code

Before declaring done, walk the **AI Development Checklist** from `references/core.md`:

- [ ] `is SepoliaConfig` on every contract
- [ ] Smallest encrypted type used
- [ ] Every external input validated via `FHE.fromExternal`
- [ ] Every state write followed by `FHE.allowThis`
- [ ] Every encrypted return preceded by `FHE.allow(_, msg.sender)`
- [ ] `FHE.select` instead of `if`/`require` on `ebool`
- [ ] Division has plaintext divisor
- [ ] Oracle callbacks start with `FHE.checkSignatures(id, sigs)`
- [ ] Oracle callbacks check `requestId == _pendingId`
- [ ] No `makePubliclyDecryptable` on user-private data

If any fail → fix before responding to the user.

---

## Step 9 — Common agent traps

1. **Defaulting to `euint256`** because "256 is bigger". Wrong — use the smallest type that fits.
2. **Treating `ebool` like `bool`**. It's a `uint256` handle. Always `FHE.select`.
3. **Trying to log encrypted values**. Logging the handle is fine; the plaintext requires user-decrypt off-chain.
4. **Forgetting `FHE.allowThis` on a re-assigned state var**. Every assignment is a new handle. Re-grant.
5. **Reading plaintext in the same tx as `requestDecryption`**. It's not there yet — split into two txs.
6. **Skipping `FHE.checkSignatures`**. Critical security bug — anyone can spoof the callback.
7. **Reusing input proof**. Each proof is `(contract, sender)`-bound. Per-user, per-contract.
8. **Using legacy `TFHE.sol`**. The current package is `@fhevm/solidity/lib/FHE.sol`. Old guides will lead you astray.

---

## Step 10 — Talk to the user

After implementing, briefly explain:
- What's encrypted, what isn't
- Who can decrypt what (the user via EIP-712; publicly after reveal; the contract via oracle async)
- How to test it
- The deploy command

Don't dump the entire SKILL.md back at them. Show working code.
