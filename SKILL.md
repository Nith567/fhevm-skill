---
name: fhevm-skill
description: >
  Write, test, and deploy confidential smart contracts on the Zama Protocol
  (FHEVM) using @fhevm/solidity, @fhevm/hardhat-plugin, and @zama-fhe/relayer-sdk.
  Use this skill whenever the user mentions Zama, FHEVM, Zama Protocol, fhevm,
  fully homomorphic encryption (FHE) on Ethereum, encrypted smart contracts,
  confidential ERC-20 / ERC-7984, ConfidentialFungibleToken, encrypted types
  (euint8/16/32/64/128/256, ebool, eaddress), externalEuint*, FHE.fromExternal,
  FHE.allow / FHE.allowThis / FHE.allowTransient / FHE.makePubliclyDecryptable,
  input proofs, ZK proofs of knowledge, user decryption with EIP-712, public
  decryption, oracle async decryption with FHE.requestDecryption + callback +
  FHE.checkSignatures, the Hardhat fhevm template, fhevmjs / relayer-sdk,
  SepoliaConfig, KMS, blind auctions, encrypted voting, confidential DAOs,
  private balances, or wants to debug FHEVM access-denied / handle-mismatch /
  view-function-revert errors. Also trigger on phrases like "encrypted ERC20",
  "private transfer onchain", "homomorphic Solidity", or "build a confidential
  dApp". Covers the full workflow: setup → encrypted types → FHE ops → ACL →
  input proofs → decryption → frontend → testing → anti-patterns → ERC-7984.
license: MIT
metadata:
  author: fhevm-skill
  version: "1.0.0"
  homepage: "https://github.com/Nith567/fhevm-skill"
---

# Zama FHEVM — Confidential Smart Contracts

Production-ready agent skill for writing **confidential smart contracts** on the **Zama Protocol** (FHEVM) — the EVM with native Fully Homomorphic Encryption. Encrypted state. Encrypted inputs. Encrypted computation. Selective decryption.

**This file is the index.** Load it first; jump to `references/` for depth.

---

## 1. How FHEVM Works (60-second model)

The Zama Protocol adds an **FHE coprocessor** to the EVM. Encrypted values are not stored on-chain as ciphertexts — they live as **handles** (`bytes32` / `uint256`-shaped) that point to ciphertexts held by the coprocessor. The Solidity contract orchestrates operations on handles; the coprocessor performs FHE math; the **KMS** (key management service) controls who can decrypt what; the **Gateway / Relayer** ferries inputs and decryption requests between the user, the chain, and the KMS.

```
┌──────────┐  encrypted input + ZK proof   ┌──────────────┐
│  User /  │ ────────────────────────────▶│  Smart       │
│ frontend │                              │  contract    │──┐
└──────────┘                              └──────┬───────┘  │ FHE.add / mul / select
     ▲                                           │ handle    │ on handles
     │ EIP-712 user-decrypt        FHE.request  ▼           ▼
┌──────────┐  ◀─────────────────  ┌────────────────────────────┐
│  KMS     │     decrypt result   │    FHE Coprocessor         │
└──────────┘                      └────────────────────────────┘
```

Three things only happen in plaintext:
1. **Encrypted inputs** generated client-side with a **ZK proof of knowledge** of the plaintext (`inputProof`).
2. **Public decryption** when the contract explicitly marks a handle publicly decryptable.
3. **User decryption** when the user signs an EIP-712 reencryption request to the KMS.

Everything else stays encrypted forever.

---

## 2. Critical Rules (memorize these — every violation produces broken code)

1. **Inherit `SepoliaConfig`** (or the matching network config) on every confidential contract. Without it the FHE precompile addresses are unset and every op reverts.
2. **Import from `@fhevm/solidity/lib/FHE.sol`** — *not* `tfhe-solidity`, *not* `fhevm/lib/TFHE.sol` (the old v0.5 API). Current package is `@fhevm/solidity`.
3. **Always grant ACL after every write or compute.** A new handle has no ACL. Call `FHE.allowThis(h)` so the contract can reuse it; `FHE.allow(h, msg.sender)` (or `FHE.allow(h, recipient)`) so a user can decrypt it.
4. **Never branch on an `ebool`.** `if (eFlag)` does not compile (it's a `uint256` handle, not a bool). Use `FHE.select(eFlag, ifTrue, ifFalse)` — both branches always execute.
5. **Decryption is async + multi-tx.** `FHE.requestDecryption(...)` returns a `requestId`. The KMS later calls your callback in a *separate transaction*. You **cannot** read a plaintext in the same tx that requested it.
6. **`view`/`pure` cannot return useful encrypted values to a frontend.** They can return the handle, but the frontend must do **user-decrypt** (EIP-712 → KMS) to see the plaintext. Do not try to decrypt inside a `view`.
7. **Validate every external input with `FHE.fromExternal(handle, inputProof)`** before using it. Skipping this lets an attacker pass arbitrary handles.
8. **Pick the smallest type.** `euint8` for flags/small counters, `euint32` for typical balances, `euint64` for large balances, `euint128`/`256` only when needed. FHE ops cost more for larger types.
9. **Division/remainder require a plaintext divisor.** `FHE.div(eA, eB)` panics. `FHE.div(eA, plainUint)` is fine.
10. **Arithmetic wraps silently.** No overflow revert. Test for it with bounds (`vm.assume`, encrypted comparisons + `FHE.select`).

---

## 3. Project Setup (Hardhat template)

### 3.0 Auto-bootstrap rule (READ BEFORE WRITING ANY CONTRACT)

Before writing a contract, **inspect the working directory**:

| State | Required action |
|---|---|
| `hardhat.config.ts` does NOT exist | Run the bootstrap commands below first |
| `hardhat.config.ts` exists but `@fhevm/solidity` is missing from `package.json` | Run `npm install @fhevm/solidity @fhevm/hardhat-plugin @zama-fhe/relayer-sdk @openzeppelin/confidential-contracts` |
| `hardhat.config.ts` exists AND `@fhevm/solidity` is in `package.json` | Skip bootstrap, write the contract directly |

**Bootstrap commands** (only when missing):

```bash
git clone https://github.com/zama-ai/fhevm-hardhat-template .
npm install
```

This is silent setup. Don't ask the user — just check, bootstrap if needed, then proceed to the actual task.

### 3.1 Standard development loop

```bash
npx hardhat compile
npx hardhat test                       # mock mode, instant, NO RPC or key needed
npx hardhat test --network sepolia     # real coprocessor (requires .env, see 3.3)
npx hardhat --network sepolia deploy   # deploy (requires .env)
```

### 3.2 `hardhat.config.ts` (default = Sepolia testnet, override via `.env`)

The skill ships with **Sepolia testnet as the default network** and a public RPC baked in — mock tests + Sepolia tests work out of the box with zero setup. Mainnet is available too but never default; the user must explicitly target it.

```ts
import "@fhevm/hardhat-plugin";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";
dotenv.config();

const SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL ?? "https://rpc2.sepolia.org";
const MAINNET_RPC_URL = process.env.MAINNET_RPC_URL ?? "https://eth.drpc.org";
const PRIVATE_KEY     = process.env.PRIVATE_KEY;

export default {
    solidity: {
        version: "0.8.27",
        settings: { optimizer: { enabled: true, runs: 800 } },
    },
    defaultNetwork: "sepolia",
    networks: {
        hardhat: { chainId: 31337 },
        sepolia: {
            url: SEPOLIA_RPC_URL,
            accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
            chainId: 11155111,
        },
        mainnet: {
            url: MAINNET_RPC_URL,
            accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
            chainId: 1,
        },
    },
};
```

> Backup public Sepolia RPCs (use any if `rpc2.sepolia.org` is rate-limited):
> `https://ethereum-sepolia.publicnode.com`, `https://eth-sepolia.public.blastapi.io`

### 3.3 `.env` (optional — only for live deploy / live test)

Mock tests need NOTHING. Live deploy needs a funded private key. RPC overrides are optional.

```
PRIVATE_KEY=0xyourtestkey...

SEPOLIA_RPC_URL=https://rpc2.sepolia.org

MAINNET_RPC_URL=https://eth.drpc.org
```

**Default behaviour:** unless the user explicitly says "deploy to mainnet" or passes `--network mainnet`, always target Sepolia testnet.

### 3.4 Key dependencies

| Package | Purpose |
|---|---|
| `@fhevm/solidity` | Solidity library (`FHE`, encrypted types, `SepoliaConfig`) |
| `@fhevm/hardhat-plugin` | Hardhat task integration + mock coprocessor for tests |
| `@zama-fhe/relayer-sdk` | Browser/Node SDK: encrypt inputs, user-decrypt, public-decrypt |
| `@openzeppelin/confidential-contracts` | ERC-7984 confidential token + ERC-20 wrapper |

> See `references/setup.md` for from-scratch setup without the template.

---

## 4. Encrypted Types

| Type | Width | Typical use |
|---|---|---|
| `ebool` | 1 bit (handle) | flags, conditional masks |
| `euint8` | 8 | small counters, age |
| `euint16` | 16 | small balances |
| `euint32` | 32 | balances, prices |
| `euint64` | 64 | large balances, timestamps |
| `euint128` | 128 | high-precision values |
| `euint256` | 256 | hashes, large math |
| `eaddress` | 160 | encrypted addresses (alias for `euint160`) |

External (calldata-only) counterparts: `externalEbool`, `externalEuint8` … `externalEuint256`, `externalEaddress`. These are opaque indices into an `inputProof`.

```solidity
import {FHE, euint32, externalEuint32, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract Counter is SepoliaConfig {
    euint32 private count;
}
```

> Cheat-sheet of operations and casting rules: `references/core.md`.

---

## 5. FHE Operations

```solidity
// Arithmetic (encrypted op encrypted, or encrypted op plaintext)
FHE.add(a, b)   FHE.sub(a, b)   FHE.mul(a, b)   FHE.neg(a)
FHE.div(a, plainB)   FHE.rem(a, plainB)   // RHS must be plaintext

// Bitwise
FHE.and(a, b)   FHE.or(a, b)   FHE.xor(a, b)   FHE.not(a)
FHE.shl(a, n)   FHE.shr(a, n)   FHE.rotl(a, n)   FHE.rotr(a, n)

// Comparisons → return ebool
FHE.eq(a, b)    FHE.ne(a, b)
FHE.lt(a, b)    FHE.le(a, b)    FHE.gt(a, b)    FHE.ge(a, b)

// Min / Max
FHE.min(a, b)   FHE.max(a, b)

// Conditional (the only "if" available on ciphertexts)
FHE.select(eboolCond, ifTrue, ifFalse)

// Constants & casts
FHE.asEuint32(plainUint)        // plaintext → encrypted
FHE.asEuint64(euint32Value)     // widen
FHE.asEuint32(euint64Value)     // narrow (may truncate)
FHE.asEbool(euint8)             // nonzero → true
```

**Always grant ACL on the result** of any of these before storing or returning it.

---

## 6. Access Control List (ACL) — the #1 source of bugs

A handle's ACL = the list of addresses allowed to use or decrypt it. **A new handle has only the producing contract on the ACL transiently.** If you store it without `allowThis`, the next tx can't read it. If the user calls a function that returns it without `allow(h, msg.sender)`, the user can't decrypt it.

| Function | Effect | Persistence | When |
|---|---|---|---|
| `FHE.allowThis(h)` | Grants `address(this)` permanent access | Persistent (storage) | Always when storing |
| `FHE.allow(h, addr)` | Grants `addr` permanent access | Persistent (storage) | Returning to user; sharing across contracts |
| `FHE.allowTransient(h, addr)` | Grants for current tx only | Transient (EIP-1153) | Passing a handle into another contract call in the same tx |
| `FHE.makePubliclyDecryptable(h)` | Anyone can publicly decrypt | Persistent | Reveal final result (auction winner price, vote tally) |
| `FHE.isAllowed(h, addr)` | Read ACL | view | Pre-flight check |
| `FHE.isSenderAllowed(h)` | `isAllowed(h, msg.sender)` | view | Authorize tx |

**The Store-and-Grant pattern** — every state-mutating function follows this:

```solidity
function deposit(externalEuint32 encAmount, bytes calldata inputProof) external {
    euint32 amount = FHE.fromExternal(encAmount, inputProof);     // 1. validate input
    balance[msg.sender] = FHE.add(balance[msg.sender], amount);   // 2. compute (new handle!)
    FHE.allowThis(balance[msg.sender]);                           // 3. let contract reuse
    FHE.allow(balance[msg.sender], msg.sender);                   // 4. let user decrypt
}
```

> Full ACL deep-dive + cross-contract delegation patterns: `references/core.md`.

---

## 7. Input Proofs (encrypted inputs)

Plaintexts entering the chain must be encrypted **client-side** and accompanied by a **ZK proof of knowledge** of the plaintext (so an attacker can't replay someone else's ciphertext for their own account).

**Solidity side** — accept `externalEuint*` indices + a single `bytes inputProof`, then validate:

```solidity
function bid(
    externalEuint64 encBid,
    externalEbool   encAuto,
    bytes calldata  inputProof
) external {
    euint64 bidAmt = FHE.fromExternal(encBid,  inputProof);
    ebool   isAuto = FHE.fromExternal(encAuto, inputProof);
    // ... use them
}
```

**Frontend / test side** — build the proof with the relayer SDK or hardhat plugin:

```ts
// In a Hardhat test
const input = fhevm.createEncryptedInput(contractAddr, signerAddr);
input.add64(1_500_000n);  // index 0 → externalEuint64
input.addBool(true);      // index 1 → externalEbool
const enc = await input.encrypt();

await contract.bid(enc.handles[0], enc.handles[1], enc.inputProof);
```

```ts
// In a browser dApp (relayer SDK)
import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/bundle";
const fhevm = await createInstance(SepoliaConfig);
const buf = fhevm.createEncryptedInput(contractAddr, userAddr);
buf.add64(1_500_000n);
const { handles, inputProof } = await buf.encrypt();
```

The proof binds the ciphertext to **(contract, user)** — it cannot be reused elsewhere.

---

## 8. Decryption Patterns

There are **three** ways to read an encrypted value. Pick by audience:

### 8a. User decryption (EIP-712, off-chain) — *single user reads their own data*

The user signs an EIP-712 message authorizing the KMS to reencrypt the handle under their personal keypair. **No transaction needed.** Cheapest path. Requires the contract to have called `FHE.allow(handle, user)`.

```ts
import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/bundle";
const fhevm = await createInstance(SepoliaConfig);

const keypair = fhevm.generateKeypair();
const handles = [{ handle: encBalanceHandle, contractAddress: contractAddr }];
const startTs = Math.floor(Date.now() / 1000).toString();
const days    = "10";

const eip712 = fhevm.createEIP712(keypair.publicKey, [contractAddr], startTs, days);
const sig = await signer.signTypedData(eip712.domain, eip712.types, eip712.message);

const result = await fhevm.userDecrypt(
    handles, keypair.privateKey, keypair.publicKey, sig.replace("0x",""),
    [contractAddr], userAddr, startTs, days
);
console.log(result[encBalanceHandle]);  // plaintext bigint
```

### 8b. Public decryption — *result becomes globally visible*

The contract calls `FHE.makePubliclyDecryptable(handle)`. Anyone can then call `relayer.publicDecrypt([handle])` off-chain. Use for auction winners, final vote tallies, settled prices.

```solidity
function reveal() external onlyAfterDeadline {
    FHE.makePubliclyDecryptable(winningBid);
    FHE.makePubliclyDecryptable(winnerAddr);
}
```

```ts
const result = await fhevm.publicDecrypt([winningBidHandle, winnerAddrHandle]);
```

### 8c. Oracle async decryption — *bring plaintext on-chain via callback*

When the **contract itself** needs the plaintext (e.g. settle to a non-FHE protocol), use the decryption oracle:

```solidity
import {FHE, euint32} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract Reveal is SepoliaConfig {
    euint32 private secret;
    uint32  public revealed;
    uint256 public latestRequestId;

    function requestReveal() external {
        bytes32[] memory cts = new bytes32[](1);
        cts[0] = FHE.toBytes32(secret);
        latestRequestId = FHE.requestDecryption(cts, this.onReveal.selector);
    }

    // Called by the KMS in a LATER transaction
    function onReveal(uint256 requestId, uint32 plaintext, bytes[] memory signatures) external {
        FHE.checkSignatures(requestId, signatures);   // verifies KMS quorum
        require(requestId == latestRequestId, "stale");
        revealed = plaintext;
    }
}
```

**Rules:** the callback's parameters after `requestId` **must** match the order of handles in the `cts[]` array. Always call `FHE.checkSignatures` first — without it, anyone can spoof the callback.

> Patterns + gotchas + retry / safe-result patterns: `references/decryption.md`.

---

## 9. Frontend Integration (`@zama-fhe/relayer-sdk`)

```ts
import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/bundle";

const fhevm = await createInstance({
    ...SepoliaConfig,
    network: window.ethereum,        // for browser; or RPC URL
});

// 1. Encrypt input for a contract call
const input = fhevm.createEncryptedInput(CONTRACT, await signer.getAddress());
input.add32(amount);
const { handles, inputProof } = await input.encrypt();
await contract.deposit(handles[0], inputProof);

// 2. Read user-private state
const handle = await contract.balanceOf(user);   // returns the handle
const plain  = await userDecrypt(fhevm, signer, handle, CONTRACT);

// 3. Read publicly-revealed state
const winner = await fhevm.publicDecrypt([await contract.winner()]);
```

Network configs ship with the SDK:
- `SepoliaConfig` — Sepolia testnet (most common)
- mainnet config when available

> Browser bundling tips, React hooks pattern, error handling: `references/frontend.md`.

---

## 10. Testing

The Hardhat plugin runs an **in-process FHE mock**. Tests are fast (no real coprocessor) and let you `await fhevm.userDecrypt(...)` synchronously.

```ts
import { fhevm, ethers } from "hardhat";

it("increments encrypted counter", async () => {
    const [alice] = await ethers.getSigners();
    const Counter = await ethers.deployContract("Counter");
    await fhevm.assertCoprocessorInitialized(Counter, "Counter");

    // Build encrypted input
    const enc = await fhevm
        .createEncryptedInput(await Counter.getAddress(), alice.address)
        .add32(5)
        .encrypt();

    await Counter.connect(alice).increment(enc.handles[0], enc.inputProof);

    // User-decrypt the result
    const handle = await Counter.getCount();
    const plain  = await fhevm.userDecryptEuint(
        FhevmType.euint32, handle, await Counter.getAddress(), alice
    );
    expect(plain).to.equal(5n);
});
```

**Async oracle decryption in tests:** call `await fhevm.awaitDecryptionOracle()` to flush pending callbacks.

```ts
await contract.requestReveal();
await fhevm.awaitDecryptionOracle();   // mock fast-forwards the KMS
expect(await contract.revealed()).to.equal(42);
```

Testing modes:
- **Mock** (default `npx hardhat test`) — instant, no chain
- **Sepolia** (`npx hardhat test --network sepolia`) — real coprocessor + KMS, slow but truthful

> Full test recipes (fuzzing, multi-user, ACL assertions): `references/testing.md`.

---

## 11. Common Anti-Patterns (compiler smiles, runtime breaks)

| ❌ Anti-pattern | Symptom | ✅ Fix |
|---|---|---|
| `if (someEbool) {…}` | does not compile | `FHE.select(someEbool, a, b)` |
| Returning encrypted state from a `view` and trying to `await contract.balance()` as plaintext | gets a `bytes32` handle, not a number | Use **user-decrypt** flow client-side |
| Forgetting `FHE.allowThis(h)` after a state write | next tx reverts with `ACL: not allowed` | Add `FHE.allowThis` after every assignment |
| Forgetting `FHE.allow(h, user)` before returning | user-decrypt fails with `unauthorized` | Add `FHE.allow(h, msg.sender)` |
| Using a handle from one user as input for another user's tx | proof verification reverts | `inputProof` is bound to `(contract, user)`; regenerate per user |
| `FHE.div(a, b)` where both are encrypted | panic | RHS must be plaintext |
| Reading plaintext in the same tx as `requestDecryption` | always stale / reverts | Split into two txs (callback model) |
| Skipping `FHE.checkSignatures` in the callback | anyone can forge a "decryption" | First line of every callback: `FHE.checkSignatures(requestId, signatures);` |
| Storing a fresh handle, then `FHE.allowSender` *before* writing it | wrong order; sender ACL grants to *old* handle | Write **first**, then `allowThis` then `allow`-sender |
| Defaulting every variable to `euint256` | painful gas | Pick the smallest width that fits |
| Using the legacy `TFHE.sol` from old guides | imports won't resolve | Use `@fhevm/solidity/lib/FHE.sol` |
| Forgetting `is SepoliaConfig` | every FHE op reverts | Inherit `SepoliaConfig` (or matching network config) |
| Encrypted comparisons in `require(...)` | `ebool` is not `bool` | Use `FHE.select` or oracle-decrypt the bool first |

> Extended catalog with Solidity-level reproductions: `references/anti-patterns.md`.

---

## 12. ERC-7984 — Confidential Fungible Token (OpenZeppelin)

ERC-7984 is the encrypted-balance fungible-token standard. Public total supply, **encrypted** per-account balances, **encrypted** transfer amounts.

```bash
npm i @openzeppelin/confidential-contracts
```

```solidity
pragma solidity ^0.8.27;

import {ERC7984} from "@openzeppelin/confidential-contracts/token/ERC7984/ERC7984.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract MyConfidentialToken is ERC7984, SepoliaConfig {
    constructor() ERC7984("Confidential USD", "cUSD", "https://…/metadata.json") {}
}
```

**Key surface area:**

| Method | Purpose |
|---|---|
| `confidentialBalanceOf(address) → euint64` | Returns the handle (decrypt off-chain) |
| `confidentialTransfer(to, externalEuint64 amt, bytes proof)` | Encrypted transfer |
| `confidentialTransferFrom(from, to, externalEuint64 amt, bytes proof)` | With allowance |
| `setOperator(operator, until)` | Grant operator authority (replaces approve) |
| `discloseEncryptedAmount(handle)` | Owner-side public decryption |

**ERC-20 ↔ ERC-7984 wrapping** — bring an existing ERC-20 (like USDC) into the confidential world:

```solidity
import {ERC7984ERC20Wrapper}
    from "@openzeppelin/confidential-contracts/token/ERC7984/extensions/ERC7984ERC20Wrapper.sol";

contract cUSDC is ERC7984ERC20Wrapper, SepoliaConfig {
    constructor(IERC20 underlying)
        ERC7984ERC20Wrapper(underlying)
        ERC7984("Confidential USDC", "cUSDC", "") {}
}
```

`wrap(account, amount)` deposits ERC-20 and mints encrypted balance. `unwrap(from, to, encAmount, proof)` burns encrypted balance and releases ERC-20 — the unwrap amount is decrypted by the oracle (see `references/erc7984.md`).

> Full ERC-7984 surface, allowance pitfalls, operator pattern: `references/erc7984.md`.

---

## 13. Reference Files (load on demand)

- **`QUICKSTART.md`** — Zero-to-deployed dApp in 10 minutes. Copy-paste path: bootstrap → contract → test → deploy → frontend.
- **`references/core.md`** — Complete API: every encrypted type, every `FHE.*` operation signature, casting rules, external inputs, ACL deep-dive, all 3 decryption flows, AI checklist + template + debugging guide.
- **`references/decryption.md`** — All three decryption flows in detail (user / public / oracle async), KMS verification, callback patterns, retry & timeout strategies.
- **`references/frontend.md`** — `@zama-fhe/relayer-sdk` deep-dive: encryption inputs, EIP-712 user-decrypt, publicDecrypt, browser bundling (Vite/Next), React hooks template.
- **`references/testing.md`** — Hardhat plugin tests: mock mode, Sepolia mode, `awaitDecryptionOracle`, fuzzing encrypted ops, ACL assertions, multi-user scenarios.
- **`references/erc7984.md`** — OpenZeppelin Confidential Contracts: ERC-7984 full surface, operator approvals, ERC-20 wrapper, common integration patterns.
- **`references/anti-patterns.md`** — Extended catalog of 15 FHEVM mistakes with Solidity reproductions and fixes.
- **`references/patterns.md`** — Cookbook of 20 composable patterns: max accumulators, encrypted whitelists, transient ACL, batch decryption, re-key for revocation, etc.
- **`references/security.md`** — Threat model, common vulnerability classes (ACL leakage, callback spoofing, stale replay, re-entrancy), full audit checklist.
- **`references/gas-optimization.md`** — Cost class table per encrypted type, top wins (smallest type, cached constants, transient ACL, shifts vs mul), profiling.
- **`references/networks.md`** — Network configs, chain IDs, faucets, RPC providers, multi-chain inheritance.
- **`references/agent-workflow.md`** — Meta-guide: how an AI agent should approach an FHEVM request from prompt to deploy. The 10-step playbook.
- **`references/setup.md`** — From-scratch project setup (no template), package versions, Hardhat / Foundry hybrid.

### Example contracts (drop-in templates)

- **`references/examples/ConfidentialCounter.sol`** + **`.test.ts`** + **`deploy.ts`** — Canonical store/increment/decrement counter.
- **`references/examples/BlindAuction.sol`** — Minimal sealed-bid auction with oracle reveal of winner.
- **`references/examples/SealedBidAuction.sol`** — Full sealed-bid NFT auction: deposits, refunds, settlement, encrypted bid tracking.
- **`references/examples/ConfidentialVoting.sol`** + **`.test.ts`** — Encrypted yes/no voting with oracle tally finalization.
- **`references/examples/ConfidentialToken.sol`** — ERC-7984 confidential token + ERC-20 wrapper.
- **`references/examples/EncryptedERC20.sol`** + **`.test.ts`** — Custom encrypted ERC-20 from scratch (no OZ dep): mint, transfer, approve, transferFrom.
- **`references/examples/EncryptedLottery.sol`** — Verifiable random winner using `FHE.randEuint*` + oracle reveal + ETH payout.
- **`references/examples/ConfidentialPayroll.sol`** — Multi-employee encrypted salary payments via ERC-7984 transfers.
- **`references/examples/EncryptedIdentity.sol`** — Selective-disclosure identity: prove age/country/reputation thresholds without revealing raw values.
- **`references/examples/frontend.ts`** — End-to-end browser flow: connect → encrypt input → tx → user-decrypt.

---

## 14. Decision Tree — what to write next

```
User wants to…
├── store an encrypted number per account                  → ConfidentialCounter.sol
├── transfer value privately (full ERC-20-like API)        → EncryptedERC20.sol
├── ERC-7984 standard token + ERC-20 wrapping              → ConfidentialToken.sol
├── run a sealed-bid auction                               → SealedBidAuction.sol (full) / BlindAuction.sol (minimal)
├── private voting / DAO governance                        → ConfidentialVoting.sol
├── encrypted lottery / fair random draw                   → EncryptedLottery.sol
├── encrypted payroll / multi-recipient distribution       → ConfidentialPayroll.sol
├── selective-disclosure identity / age proofs             → EncryptedIdentity.sol
├── reveal a single global result                          → FHE.makePubliclyDecryptable + publicDecrypt
├── show a user *their own* encrypted balance              → user-decrypt EIP-712 flow
├── settle to a non-FHE protocol                           → oracle async (FHE.requestDecryption + callback)
├── bring USDC into the encrypted world                    → ERC7984ERC20Wrapper
└── debug "ACL: not allowed"                               → references/anti-patterns.md row #2
```

When unsure: **read `references/core.md` first**, then jump to the example that matches the use case, then customize. Always finish by walking the AI Checklist in `core.md` and re-checking `anti-patterns.md`.

For agentic workflow guidance (how an AI agent should classify and execute an FHEVM request), read `references/agent-workflow.md`.

---

## 15. Resources

- Zama Protocol docs: https://docs.zama.org/protocol
- FHEVM Solidity library: https://github.com/zama-ai/fhevm-solidity
- Hardhat template: https://github.com/zama-ai/fhevm-hardhat-template
- Relayer SDK: https://github.com/zama-ai/relayer-sdk
- OpenZeppelin confidential contracts: https://github.com/OpenZeppelin/openzeppelin-confidential-contracts
- Awesome Zama (curated): https://github.com/zama-ai/awesome-zama
