# FHE Library Reference 📚

**Comprehensive AI Assistant Guide to Zama FHEVM Types, Operations, Access Control, and Decryption**

This document provides complete reference material for AI assistants helping developers write confidential smart contracts using the **Zama Protocol** (FHEVM) on Ethereum.

## 🎯 Quick Reference for AI

**Import Statement:**
```solidity
import {
    FHE,
    ebool,
    euint8, euint16, euint32, euint64, euint128, euint256,
    eaddress,
    externalEbool,
    externalEuint8, externalEuint16, externalEuint32,
    externalEuint64, externalEuint128, externalEuint256,
    externalEaddress
} from "@fhevm/solidity/lib/FHE.sol";

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
```

**Inheritance (REQUIRED on every confidential contract):**
```solidity
contract MyContract is SepoliaConfig { ... }
```

**npm package:** `@fhevm/solidity`

**Core Mental Model:** All FHE types are **handles** (`uint256`-shaped) pointing to encrypted ciphertexts held by the FHE coprocessor. Without proper access control via `FHE.allow*`, encrypted values are unusable.

**🚨 AI Critical:** Without `is SepoliaConfig`, every FHE op reverts (precompile addresses unset).

## 🔢 Encrypted Data Types

### **Supported Bit Lengths**

| Type | Bit Length | Range | Use Case |
|------|------------|-------|----------|
| `ebool` | 1 bit | true/false | Encrypted booleans, flags |
| `euint8` | 8 bits | 0 - 255 | Small counters, enums |
| `euint16` | 16 bits | 0 - 65,535 | Medium values |
| `euint32` | 32 bits | 0 - 4,294,967,295 | Common balances, prices |
| `euint64` | 64 bits | 0 - 2^64 - 1 | Large balances, timestamps |
| `euint128` | 128 bits | 0 - 2^128 - 1 | Extremely large values |
| `euint256` | 256 bits | 0 - 2^256 - 1 | Maximum precision |
| `eaddress` | 160 bits | Ethereum address | Encrypted addresses |

### **Type Definitions**
```solidity
type ebool is uint256;
type euint8 is uint256;
type euint16 is uint256;
type euint32 is uint256;
type euint64 is uint256;
type euint128 is uint256;
type euint256 is uint256;
type eaddress is uint256;
```

**🚨 AI Important:** All FHE types are internally represented as `uint256` handles, NOT the actual encrypted data. The plaintext lives off-chain on the FHE coprocessor.

### **External Types (calldata-only inputs)**

```solidity
type externalEbool      is bytes32;
type externalEuint8     is bytes32;
type externalEuint16    is bytes32;
type externalEuint32    is bytes32;
type externalEuint64    is bytes32;
type externalEuint128   is bytes32;
type externalEuint256   is bytes32;
type externalEaddress   is bytes32;
```

**🚨 AI Important:** `externalEuint*` is an opaque calldata-only type — an index into a ZK `inputProof` blob. Convert to a usable type via `FHE.fromExternal(handle, proof)` (covered below).

## 🔧 Type Conversion Functions

### **From Plaintext to Encrypted (Trivial Encryption)**

```solidity
function asEbool(bool value)        internal returns (ebool);
function asEuint8(uint256 value)    internal returns (euint8);
function asEuint16(uint256 value)   internal returns (euint16);
function asEuint32(uint256 value)   internal returns (euint32);
function asEuint64(uint256 value)   internal returns (euint64);
function asEuint128(uint256 value)  internal returns (euint128);
function asEuint256(uint256 value)  internal returns (euint256);
function asEaddress(address value)  internal returns (eaddress);
```

**🚨 AI Important:** Trivial encryption produces a ciphertext whose plaintext is **publicly known** (the input was plaintext). Use it for constants like `0`, `1`, threshold values — NEVER for user secrets. User secrets must come in via `externalEuint*` + `inputProof`.

**AI Usage Example:**
```solidity
euint32 ENCRYPTED_ZERO = FHE.asEuint32(0);
ebool   ALWAYS_TRUE    = FHE.asEbool(true);
```

### **From External (User-Encrypted) Input**

```solidity
function fromExternal(externalEbool      h, bytes calldata proof) internal returns (ebool);
function fromExternal(externalEuint8     h, bytes calldata proof) internal returns (euint8);
function fromExternal(externalEuint16    h, bytes calldata proof) internal returns (euint16);
function fromExternal(externalEuint32    h, bytes calldata proof) internal returns (euint32);
function fromExternal(externalEuint64    h, bytes calldata proof) internal returns (euint64);
function fromExternal(externalEuint128   h, bytes calldata proof) internal returns (euint128);
function fromExternal(externalEuint256   h, bytes calldata proof) internal returns (euint256);
function fromExternal(externalEaddress   h, bytes calldata proof) internal returns (eaddress);
```

**🎯 AI Pattern:** Every function accepting user input from a frontend uses `externalEuintN` parameters + a single `bytes inputProof`, then validates each handle:

```solidity
function deposit(
    externalEuint64 encAmount,
    externalEbool   encFlag,
    bytes calldata  inputProof
) external {
    euint64 amount = FHE.fromExternal(encAmount, inputProof);
    ebool   flag   = FHE.fromExternal(encFlag,   inputProof);
    // ... use them
}
```

**🚨 AI Critical:** `FHE.fromExternal` reverts if:
- The proof was generated for a different `(contract, sender)` pair (anti-replay).
- The proof is tampered.
- The handle's claimed type doesn't match (e.g. `externalEuint32` decoded as `externalEuint64`).

Skipping `fromExternal` and trying to use the raw handle is a **critical bug** — it bypasses the ZK proof of knowledge entirely.

### **Between Encrypted Types (Casting)**

```solidity
function asEbool(euint8  value) internal returns (ebool);
function asEbool(euint32 value) internal returns (ebool);
// ... ebool cast available from any euintN (nonzero → true)

function asEuint16(euint8  value) internal returns (euint16);  // widen
function asEuint8(euint32  value) internal returns (euint8);   // narrow (truncates!)
function asEuint32(ebool   value) internal returns (euint32);  // 1 or 0
// ... and so on for all type combinations
```

**🚨 AI Critical:** Narrowing casts (e.g. `euint64` → `euint32`) **truncate silently**. Always range-check first if the value might overflow:

```solidity
ebool inRange = FHE.le(big, FHE.asEuint64(type(uint32).max));
euint64 safe  = FHE.select(inRange, big, FHE.asEuint64(type(uint32).max));
euint32 small = FHE.asEuint32(safe);
```

**AI Casting Example:**
```solidity
ebool   condition       = FHE.gt(a, b);
euint32 conditionAsInt  = FHE.asEuint32(condition);   // 0 or 1, useful for arithmetic masks
euint32 conditionalAdd  = FHE.mul(conditionAsInt, amount);  // amount or 0
```

## ➕ Arithmetic Operations

**Available for:** `euint8`, `euint16`, `euint32`, `euint64`, `euint128`, `euint256`

### **Basic Arithmetic**
```solidity
function add(euint32 lhs, euint32 rhs) internal returns (euint32);
function sub(euint32 lhs, euint32 rhs) internal returns (euint32);
function mul(euint32 lhs, euint32 rhs) internal returns (euint32);
function div(euint32 lhs, uint32  rhs) internal returns (euint32);   // RHS MUST be plaintext
function rem(euint32 lhs, uint32  rhs) internal returns (euint32);   // RHS MUST be plaintext
function neg(euint32 value)            internal returns (euint32);
function min(euint32 lhs, euint32 rhs) internal returns (euint32);
function max(euint32 lhs, euint32 rhs) internal returns (euint32);
```

**🚨 AI Critical:**
- `FHE.div(eA, eB)` with **both encrypted** → panics. Right-hand side **must** be plaintext.
- All arithmetic **wraps silently** on overflow — no revert. Test bounds with comparisons + `FHE.select`.

**AI Arithmetic Example:**
```solidity
function calculateTotal(
    externalEuint32 encPrice,
    externalEuint32 encQty,
    bytes calldata  proof
) external returns (euint32) {
    euint32 price = FHE.fromExternal(encPrice, proof);
    euint32 qty   = FHE.fromExternal(encQty,   proof);
    euint32 total = FHE.mul(price, qty);

    FHE.allowThis(total);              // Contract may reuse later
    FHE.allow(total, msg.sender);      // CRITICAL: caller can decrypt
    return total;
}
```

## 🔍 Comparison Operations

**Available for:** All encrypted types
**Returns:** `ebool` (encrypted boolean)

### **Comparison Functions**
```solidity
function eq(euint32 lhs, euint32 rhs) internal returns (ebool);   // ==
function ne(euint32 lhs, euint32 rhs) internal returns (ebool);   // !=
function lt(euint32 lhs, euint32 rhs) internal returns (ebool);   // <
function le(euint32 lhs, euint32 rhs) internal returns (ebool);   // <=
function gt(euint32 lhs, euint32 rhs) internal returns (ebool);   // >
function ge(euint32 lhs, euint32 rhs) internal returns (ebool);   // >=
```

**🚨 AI Critical:** Comparisons return `ebool`, which **CANNOT** be used in `if` statements or `require()`! Use `FHE.select` for branching, or oracle-decrypt the bool first.

**AI Comparison Example:**
```solidity
function checkSufficientBalance(euint32 balance, euint32 amount)
    external returns (ebool)
{
    ebool canAfford = FHE.ge(balance, amount);
    FHE.allowThis(canAfford);
    FHE.allow(canAfford, msg.sender);
    return canAfford;
}
```

## 🔀 Logical & Bitwise Operations

### **Boolean Logic (ebool only)**
```solidity
function and(ebool lhs, ebool rhs) internal returns (ebool);
function or (ebool lhs, ebool rhs) internal returns (ebool);
function xor(ebool lhs, ebool rhs) internal returns (ebool);
function not(ebool value)          internal returns (ebool);
```

### **Bitwise Operations (all euint types)**
```solidity
function and (euint32 lhs, euint32 rhs) internal returns (euint32);
function or  (euint32 lhs, euint32 rhs) internal returns (euint32);
function xor (euint32 lhs, euint32 rhs) internal returns (euint32);
function not (euint32 value)            internal returns (euint32);
function shl (euint32 lhs, uint8 bits)  internal returns (euint32);
function shr (euint32 lhs, uint8 bits)  internal returns (euint32);
function rotl(euint32 lhs, uint8 bits)  internal returns (euint32);
function rotr(euint32 lhs, uint8 bits)  internal returns (euint32);
```

**AI Logical Example:**
```solidity
function checkEligible(euint32 age, euint32 balance)
    external returns (ebool)
{
    ebool isAdult    = FHE.ge(age, FHE.asEuint32(18));
    ebool hasBalance = FHE.gt(balance, FHE.asEuint32(0));
    ebool eligible   = FHE.and(isAdult, hasBalance);

    FHE.allowThis(eligible);
    FHE.allow(eligible, msg.sender);
    return eligible;
}
```

## 🎲 Random Encrypted Values

```solidity
function randEbool()                  internal returns (ebool);
function randEuint8()                 internal returns (euint8);
function randEuint8(uint8   upper)    internal returns (euint8);    // 0..upper-1
function randEuint16()                internal returns (euint16);
function randEuint16(uint16 upper)    internal returns (euint16);
function randEuint32()                internal returns (euint32);
function randEuint32(uint32 upper)    internal returns (euint32);
function randEuint64()                internal returns (euint64);
function randEuint64(uint64 upper)    internal returns (euint64);
```

**🎯 AI Pattern:** Useful for blind auctions, encrypted lotteries, sealed-bid mechanisms.

```solidity
euint8 dieRoll = FHE.randEuint8(6);  // 0..5
FHE.allowThis(dieRoll);
FHE.allow(dieRoll, msg.sender);
```

## 🔓 Decryption Methods

**🚨 AI Critical:** Zama FHEVM has **THREE distinct decryption flows**. Choose by audience:

| Flow | Audience | Trigger | Cost | Use For |
|------|----------|---------|------|---------|
| **User decrypt** | One specific user | Off-chain EIP-712 sig → KMS | Free (off-chain) | Personal balance, profile |
| **Public decrypt** | Anyone | Off-chain `relayer.publicDecrypt` after on-chain mark | One small tx | Auction winner, vote tally |
| **Oracle async** | The contract itself | `FHE.requestDecryption` + callback | Two txs | Settle to non-FHE protocol |

### **🚨 AI Prerequisites for Decryption**

Before decrypt works:
- ✅ For user-decrypt: contract called `FHE.allow(value, user)`
- ✅ For public-decrypt: contract called `FHE.makePubliclyDecryptable(value)`
- ✅ For oracle async: contract called `FHE.requestDecryption([value], callback.selector)`

### **Flow 1: User Decryption (off-chain, EIP-712)**

The user signs an EIP-712 message authorizing the KMS to reencrypt the handle under their personal keypair. **No on-chain transaction needed.**

**Solidity side — just grant ACL:**
```solidity
function deposit(externalEuint64 enc, bytes calldata proof) external {
    euint64 amt = FHE.fromExternal(enc, proof);
    balances[msg.sender] = FHE.add(balances[msg.sender], amt);

    FHE.allowThis(balances[msg.sender]);
    FHE.allow(balances[msg.sender], msg.sender);   // ← enables user-decrypt
}

function balanceOf(address u) external view returns (euint64) {
    return balances[u];   // returns handle; user decrypts off-chain
}
```

**Frontend side (relayer SDK):**
```typescript
import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/bundle";

const fhevm = await createInstance(SepoliaConfig);
const kp = fhevm.generateKeypair();
const start = Math.floor(Date.now() / 1000).toString();
const days = "10";

const eip712 = fhevm.createEIP712(kp.publicKey, [contractAddr], start, days);
const sig = await signer.signTypedData(eip712.domain, eip712.types, eip712.message);

const handle = await contract.balanceOf(userAddr);
const result = await fhevm.userDecrypt(
    [{ handle, contractAddress: contractAddr }],
    kp.privateKey, kp.publicKey,
    sig.replace("0x", ""),
    [contractAddr], userAddr, start, days
);
console.log(result[handle]);   // bigint plaintext
```

### **Flow 2: Public Decryption**

Mark the handle on-chain, then anyone can decrypt off-chain.

```solidity
function reveal() external {
    require(block.timestamp > endTime, "too early");
    FHE.makePubliclyDecryptable(winningBid);
    FHE.makePubliclyDecryptable(winnerAddr);
}
```

**Frontend:**
```typescript
const result = await fhevm.publicDecrypt([handleA, handleB]);
```

**🚨 AI Critical:** `makePubliclyDecryptable` is **persistent and irreversible**. Use only for genuinely-public results. Never on per-user balances — that leaks every user's data forever.

### **Flow 3: Oracle Async Decryption**

When the **contract itself** needs the plaintext on-chain (settle to ERC-20, gate a transfer), use the decryption oracle.

```solidity
function requestDecryption(bytes32[] memory cts, bytes4 callbackSelector)
    internal returns (uint256 requestId);

function checkSignatures(uint256 requestId, bytes[] memory signatures) internal;

function toBytes32(ebool   v) internal pure returns (bytes32);
function toBytes32(euint8  v) internal pure returns (bytes32);
function toBytes32(euint16 v) internal pure returns (bytes32);
function toBytes32(euint32 v) internal pure returns (bytes32);
function toBytes32(euint64 v) internal pure returns (bytes32);
function toBytes32(euint128 v) internal pure returns (bytes32);
function toBytes32(euint256 v) internal pure returns (bytes32);
function toBytes32(eaddress v) internal pure returns (bytes32);
```

**AI Usage Pattern (single value):**
```solidity
contract Reveal is SepoliaConfig {
    euint32 private secret;
    uint32  public  revealed;
    uint256 private _pendingId;

    function requestReveal() external {
        bytes32[] memory cts = new bytes32[](1);
        cts[0] = FHE.toBytes32(secret);
        _pendingId = FHE.requestDecryption(cts, this.onReveal.selector);
    }

    function onReveal(
        uint256 requestId,
        uint32  plain,
        bytes[] memory signatures
    ) external {
        FHE.checkSignatures(requestId, signatures);   // ← MUST be first line
        require(requestId == _pendingId, "stale");
        delete _pendingId;
        revealed = plain;
    }
}
```

**AI Usage Pattern (multiple values):**
```solidity
function requestMulti() external {
    bytes32[] memory cts = new bytes32[](3);
    cts[0] = FHE.toBytes32(eAmount);    // euint64
    cts[1] = FHE.toBytes32(eBidder);    // eaddress
    cts[2] = FHE.toBytes32(eFlag);      // ebool
    _pendingId = FHE.requestDecryption(cts, this.onMulti.selector);
}

function onMulti(
    uint256 requestId,
    uint64  amount,
    address bidder,
    bool    flag,
    bytes[] memory signatures
) external {
    FHE.checkSignatures(requestId, signatures);
    require(requestId == _pendingId, "stale");
    // use amount, bidder, flag
}
```

**🚨 AI Critical Rules for Oracle Callbacks:**
1. **First line MUST be `FHE.checkSignatures(requestId, signatures);`** — without it, anyone can spoof a fake "decryption" callback and steal control.
2. Callback parameters after `requestId` must match `cts[]` order and types: `eboolN` → smallest native `uintN`, `ebool` → `bool`, `eaddress` → `address`.
3. Callback runs in a **separate transaction** — usually 30s+ on Sepolia, instant in Hardhat mock mode.
4. Verify `requestId == _pendingId` to prevent stale callbacks.
5. Clear pending state before any external calls (re-entrancy).

### **🚨 AI Common Decryption Errors**

| Error | Symptom | Fix |
|-------|---------|-----|
| Reading plaintext same tx as `requestDecryption` | Always reads stale value | Split into two txs (callback model) |
| Skipping `FHE.checkSignatures` | Anyone can forge fake decryption | First line of every callback |
| Forgetting `FHE.allow(value, user)` | User-decrypt fails: "unauthorized" | Add `allow` on producing tx |
| `FHE.makePubliclyDecryptable` on user-private data | Permanent global leak of all balances | Use `FHE.allow(value, user)` instead |
| Wrong callback selector | Decryption never resolves | Use `this.callback.selector` syntax |

## 🔢 Encrypted Constants

**🎯 AI Pattern:** Create constants in constructor, grant contract access once, reuse everywhere.

```solidity
contract Token is SepoliaConfig {
    euint64 private ENCRYPTED_ZERO;

    constructor() {
        ENCRYPTED_ZERO = FHE.asEuint64(0);
        FHE.allowThis(ENCRYPTED_ZERO);
    }
}
```

**AI Usage Example: Conditional Transfer**
```solidity
function transfer(
    address to,
    externalEuint64 encAmount,
    bytes calldata  proof
) external {
    euint64 amount  = FHE.fromExternal(encAmount, proof);
    euint64 balance = balances[msg.sender];

    ebool   canPay  = FHE.ge(balance, amount);
    euint64 actual  = FHE.select(canPay, amount, ENCRYPTED_ZERO);

    balances[msg.sender] = FHE.sub(balance, actual);
    balances[to]         = FHE.add(balances[to], actual);

    FHE.allowThis(balances[msg.sender]);
    FHE.allow(balances[msg.sender], msg.sender);
    FHE.allowThis(balances[to]);
    FHE.allow(balances[to], to);
}
```

**💡 AI Benefits:**
- **Performance**: Trivial encryption is cheap, but caching is cheaper.
- **Gas**: Avoid repeated `FHE.asEuintN(0)` per call.
- **Readability**: Named constants beat magic numbers in branches.

## 🔀 Conditional Operations (FHE.select)

**🎯 AI Essential:** The ONLY way to use encrypted boolean conditions for control flow.

### **Select Function Signatures**
```solidity
function select(ebool cond, euint8   t, euint8   f) internal returns (euint8);
function select(ebool cond, euint16  t, euint16  f) internal returns (euint16);
function select(ebool cond, euint32  t, euint32  f) internal returns (euint32);
function select(ebool cond, euint64  t, euint64  f) internal returns (euint64);
function select(ebool cond, euint128 t, euint128 f) internal returns (euint128);
function select(ebool cond, euint256 t, euint256 f) internal returns (euint256);
function select(ebool cond, ebool    t, ebool    f) internal returns (ebool);
function select(ebool cond, eaddress t, eaddress f) internal returns (eaddress);
```

**🚨 AI Critical Rules:**
1. **Both branches ALWAYS execute** — no short-circuit evaluation.
2. Only the result matching `cond` is returned; the other is discarded.
3. Use for ANY conditional logic involving encrypted values.

**AI Select Examples:**
```solidity
// Tiered discount
function discountedPrice(euint32 price, ebool isPremium) external returns (euint32) {
    euint32 reg     = FHE.div(price, 10);   // 10% off
    euint32 prem    = FHE.div(price, 5);    // 20% off
    euint32 final_  = FHE.select(
        isPremium,
        FHE.sub(price, prem),
        FHE.sub(price, reg)
    );
    FHE.allowThis(final_);
    FHE.allow(final_, msg.sender);
    return final_;
}

// Encrypted max accumulator (blind auction)
function placeBid(
    externalEuint64 encBid,
    bytes calldata  proof
) external {
    euint64  bid    = FHE.fromExternal(encBid, proof);
    eaddress bidder = FHE.asEaddress(msg.sender);

    ebool higher    = FHE.gt(bid, _highestBid);
    _highestBid     = FHE.select(higher, bid,    _highestBid);
    _highestBidder  = FHE.select(higher, bidder, _highestBidder);

    FHE.allowThis(_highestBid);
    FHE.allowThis(_highestBidder);
}
```

## 🔐 Access Control Functions (ACL)

**🎯 AI Most Important:** A handle's ACL is the per-handle list of addresses allowed to use or decrypt it. **A new handle has no ACL** — without granting access, the value is a locked box without keys.

### **Core Access Functions**

| Function | Purpose | Persistence | When to Use |
|----------|---------|-------------|-------------|
| `FHE.allowThis(value)` | Grants `address(this)` | Persistent (storage) | Storing to state |
| `FHE.allow(value, addr)` | Grants `addr` permanent access | Persistent (storage) | Returning to user, cross-contract sharing |
| `FHE.allowTransient(value, addr)` | Grants `addr` for current tx only | Transient (EIP-1153) | Pass to another contract this tx |
| `FHE.makePubliclyDecryptable(value)` | Anyone can publicDecrypt | Persistent | Reveal final result |
| `FHE.isAllowed(value, addr)` | Check ACL | View | Pre-flight check |
| `FHE.isSenderAllowed(value)` | `isAllowed(value, msg.sender)` | View | Caller authorization |

### **Access Control Function Signatures**
```solidity
function allowThis(ebool   v) internal;
function allowThis(euint8  v) internal;
// ... all encrypted types

function allow(ebool   v, address addr) internal;
function allow(euint8  v, address addr) internal;
// ... all encrypted types

function allowTransient(ebool   v, address addr) internal;
// ... all encrypted types

function makePubliclyDecryptable(ebool   v) internal;
// ... all encrypted types

function isAllowed(ebool   v, address addr) internal view returns (bool);
function isSenderAllowed(ebool   v)         internal view returns (bool);
```

### **Access Control Examples**

```solidity
contract AIAccessExamples is SepoliaConfig {
    mapping(address => euint64) private balances;

    // 🎯 AI PATTERN: Store with permanent access
    function deposit(externalEuint64 encAmount, bytes calldata proof) external {
        euint64 amount = FHE.fromExternal(encAmount, proof);
        balances[msg.sender] = FHE.add(balances[msg.sender], amount);

        FHE.allowThis(balances[msg.sender]);                // Contract reuse
        FHE.allow(balances[msg.sender], msg.sender);        // User decrypts off-chain
    }

    // 🎯 AI PATTERN: View function (access pre-granted)
    function getBalance() external view returns (euint64) {
        return balances[msg.sender];   // User already on ACL from deposit()
    }

    // 🎯 AI PATTERN: Computed value needs new ACL
    function calculateInterest(externalEuint64 encRate, bytes calldata proof)
        external returns (euint64)
    {
        euint64 balance  = balances[msg.sender];
        euint64 rate     = FHE.fromExternal(encRate, proof);
        euint64 interest = FHE.mul(balance, rate);

        FHE.allow(interest, msg.sender);   // New computed handle needs ACL
        return interest;
    }

    // 🎯 AI PATTERN: Transient cross-contract call
    function delegateAdd(address other, euint64 v) external {
        FHE.allowTransient(v, other);      // 1-tx access for `other`
        IOther(other).consume(v);
    }

    // 🎯 AI PATTERN: Permanent cross-contract sharing
    function shareBalance(address otherContract) external {
        FHE.allow(balances[msg.sender], otherContract);
    }
}
```

## 🚨 AI Critical Patterns

### **❌ Common AI Mistakes**

```solidity
// ❌ WRONG: branching on ebool
function badConditional(euint32 a, euint32 b) external {
    ebool condition = FHE.gt(a, b);
    if (condition) { /* won't compile */ }
}

// ❌ WRONG: returning encrypted value without ACL
function badReturn() external returns (euint32) {
    euint32 result = FHE.asEuint32(42);
    return result;   // user can't decrypt
}

// ❌ WRONG: storing without contract ACL
function badStorage(externalEuint32 enc, bytes calldata p) external {
    counter = FHE.fromExternal(enc, p);
    // next tx: "ACL: contract not allowed"
}

// ❌ WRONG: skipping fromExternal validation
function badInput(externalEuint32 enc) external {
    counter = euint32.wrap(externalEuint32.unwrap(enc));   // bypasses ZK proof!
}

// ❌ WRONG: dividing by encrypted value
function badDiv(euint32 a, euint32 b) external returns (euint32) {
    return FHE.div(a, b);   // panics
}

// ❌ WRONG: forgetting checkSignatures in callback
function onReveal(uint256 id, uint32 plain, bytes[] memory) external {
    revealed = plain;   // anyone can call this!
}

// ❌ WRONG: missing SepoliaConfig
contract Counter {                          // no inheritance
    euint32 c;
    function inc() external { c = FHE.add(c, FHE.asEuint32(1)); }
    // every FHE op reverts: precompiles unset
}
```

### **✅ Correct AI Patterns**

```solidity
// ✅ CORRECT: FHE.select for conditionals
function goodConditional(euint32 a, euint32 b) external returns (euint32) {
    ebool   cond   = FHE.gt(a, b);
    euint32 result = FHE.select(cond, a, b);
    FHE.allowThis(result);
    FHE.allow(result, msg.sender);
    return result;
}

// ✅ CORRECT: grant ACL on every new handle
function goodReturn() external returns (euint32) {
    euint32 result = FHE.asEuint32(42);
    FHE.allow(result, msg.sender);
    return result;
}

// ✅ CORRECT: store-and-grant
function goodStorage(externalEuint32 enc, bytes calldata p) external {
    counter = FHE.fromExternal(enc, p);
    FHE.allowThis(counter);
    FHE.allow(counter, msg.sender);
}

// ✅ CORRECT: validate every external input
function goodInput(externalEuint32 enc, bytes calldata proof) external {
    counter = FHE.fromExternal(enc, proof);
    FHE.allowThis(counter);
    FHE.allow(counter, msg.sender);
}

// ✅ CORRECT: division with plaintext divisor
function goodDiv(euint32 a, uint32 plainB) external returns (euint32) {
    euint32 r = FHE.div(a, plainB);
    FHE.allow(r, msg.sender);
    return r;
}

// ✅ CORRECT: checkSignatures first in callback
function onReveal(uint256 id, uint32 plain, bytes[] memory sigs) external {
    FHE.checkSignatures(id, sigs);
    require(id == _pendingId, "stale");
    revealed = plain;
}

// ✅ CORRECT: inherit SepoliaConfig
contract Counter is SepoliaConfig {
    euint32 c;
    function inc() external {
        c = FHE.add(c, FHE.asEuint32(1));
        FHE.allowThis(c);
    }
}
```

## 🎯 AI Development Checklist

**Before generating FHEVM code, AI should verify:**

✅ **Imports**: `import {FHE, ...} from "@fhevm/solidity/lib/FHE.sol";` + `SepoliaConfig`
✅ **Inheritance**: Contract extends `SepoliaConfig` (or matching network config)
✅ **Type Sizing**: Smallest bit length that fits the value range (avoid `euint256` defaults)
✅ **External Inputs**: `externalEuintN` + `bytes inputProof`, validated via `FHE.fromExternal`
✅ **Storage ACL**: Every encrypted state write followed by `FHE.allowThis`
✅ **Return ACL**: Every returned encrypted value preceded by `FHE.allow(_, msg.sender)`
✅ **Computed ACL**: New handles from `add/mul/select/...` get fresh ACL grants
✅ **Conditionals**: Use `FHE.select` instead of `if`/`require` on `ebool`
✅ **Division**: `FHE.div(eA, plainB)` — RHS plaintext only
✅ **Decryption Flow**: Right flow per audience (user / public / oracle)
✅ **Oracle Callbacks**: First line is `FHE.checkSignatures(id, sigs)`, then `requestId` check
✅ **No Plain Read in Same Tx**: Decryption is always async — split into two txs

## 📋 Quick AI Template

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, euint32, externalEuint32}
    from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig}
    from "@fhevm/solidity/config/ZamaConfig.sol";

contract AIFHEVMTemplate is SepoliaConfig {
    mapping(address => euint32) private userData;
    mapping(address => bool)    public  hasData;

    // Pattern: store user-encrypted input
    function storeData(externalEuint32 encVal, bytes calldata proof) external {
        userData[msg.sender] = FHE.fromExternal(encVal, proof);
        FHE.allowThis(userData[msg.sender]);
        FHE.allow(userData[msg.sender], msg.sender);
        hasData[msg.sender] = true;
    }

    // Pattern: view returns handle (user decrypts off-chain)
    function getData() external view returns (euint32) {
        require(hasData[msg.sender], "no data");
        return userData[msg.sender];
    }

    // Pattern: computed value needs fresh ACL
    function computeDouble() external returns (euint32) {
        require(hasData[msg.sender], "no data");
        euint32 d = userData[msg.sender];
        euint32 r = FHE.add(d, d);
        FHE.allow(r, msg.sender);
        return r;
    }

    // Pattern: encrypted conditional
    function conditionalOp(externalEuint32 encThr, bytes calldata proof)
        external returns (euint32)
    {
        require(hasData[msg.sender], "no data");
        euint32 d   = userData[msg.sender];
        euint32 thr = FHE.fromExternal(encThr, proof);

        ebool   above = FHE.gt(d, thr);
        euint32 r     = FHE.select(
            above,
            FHE.mul(d, FHE.asEuint32(2)),
            d
        );

        FHE.allowThis(r);
        FHE.allow(r, msg.sender);
        return r;
    }
}
```

## 🔄 Multi-Transaction Oracle Decryption Pattern

**🎯 AI Critical:** When the contract itself needs the plaintext, decryption is always **two transactions**.

```solidity
contract SecureVoting is SepoliaConfig {
    mapping(bytes32 => euint32) private results;
    mapping(bytes32 => uint256) public  pendingRequest;
    mapping(bytes32 => uint32)  public  finalResult;
    mapping(bytes32 => bool)    public  finalized;

    // Tx 1: request decryption of the tally
    function requestFinalize(bytes32 proposalId) external {
        require(pendingRequest[proposalId] == 0, "already requested");

        bytes32[] memory cts = new bytes32[](1);
        cts[0] = FHE.toBytes32(results[proposalId]);
        uint256 reqId = FHE.requestDecryption(cts, this.onFinalize.selector);
        pendingRequest[proposalId] = reqId;
    }

    // Tx 2: KMS callback in a later block (verified via signatures)
    function onFinalize(
        uint256 requestId,
        uint32  decryptedTally,
        bytes[] memory signatures
    ) external {
        FHE.checkSignatures(requestId, signatures);

        // map back to which proposal triggered this id
        // (caller-side bookkeeping: see BlindAuction example)
        // ...

        finalResult[/* proposalId */] = decryptedTally;
        finalized[/* proposalId */]   = true;
    }
}
```

## 🔄 Cross-Contract Permissions

### **Pattern 1: Permanent Sharing**
```solidity
contract DataProvider is SepoliaConfig {
    mapping(address => euint32) private userData;

    function shareWith(address consumer) external {
        require(FHE.isSenderAllowed(userData[msg.sender]), "no data");
        FHE.allow(userData[msg.sender], consumer);
    }

    function storeUserData(externalEuint32 enc, bytes calldata proof) external {
        userData[msg.sender] = FHE.fromExternal(enc, proof);
        FHE.allowThis(userData[msg.sender]);
        FHE.allow(userData[msg.sender], msg.sender);
    }
}

contract DataConsumer is SepoliaConfig {
    mapping(address => euint32) private processed;

    function process(address provider, address user) external {
        DataProvider(provider).shareWith(address(this));   // get ACL
        // fetch handle (need a getter on the provider, omitted for brevity)
        // compute on it
        // ...
    }
}
```

### **Pattern 2: Transient (one-tx) Sharing**
```solidity
contract Sender is SepoliaConfig {
    function sendOnce(address recipient, euint32 v) external {
        FHE.allowTransient(v, recipient);   // ACL valid for THIS tx only
        IRecipient(recipient).consume(v);
    }
}

contract Recipient is SepoliaConfig {
    euint32 stored;

    function consume(euint32 v) external {
        require(FHE.isAllowed(v, address(this)), "no access");
        stored = v;
        FHE.allowThis(stored);   // upgrade transient → persistent for future txs
    }
}
```

### **🚨 AI Cross-Contract Mistakes**

```solidity
// ❌ WRONG: assume contract has access without grant
contract BadConsumer is SepoliaConfig {
    function process(euint32 data) external {
        euint32 r = FHE.add(data, FHE.asEuint32(10));   // ACL: not allowed
    }
}

// ✅ CORRECT: explicit ACL via allowTransient
contract GoodSender is SepoliaConfig {
    function sendTo(address consumer, euint32 v) external {
        FHE.allowTransient(v, consumer);
        IConsumer(consumer).process(v);
    }
}
```

## 🔍 AI Debugging Guide

### 🚨 Common AI-Generated Code Issues

**Issue #1: "ACL: sender not allowed"**
```solidity
// 🔍 SYMPTOM: User-decrypt fails / "unauthorized"
// 🎯 AI FIX: grant ACL to msg.sender on producing tx
function fixThis() external returns (euint32) {
    euint32 r = someComputation();
    FHE.allow(r, msg.sender);   // ADD THIS
    return r;
}
```

**Issue #2: "ACL: contract not allowed"**
```solidity
// 🔍 SYMPTOM: next tx reverts when reading own state
// 🎯 AI FIX: allowThis after every state write
function store(externalEuint32 e, bytes calldata p) external {
    counter = FHE.fromExternal(e, p);
    FHE.allowThis(counter);   // ADD THIS
}
```

**Issue #3: "Cannot convert ebool to bool"**
```solidity
// ❌ AI MISTAKE
if (FHE.gt(a, b)) { /* ... */ }
require(FHE.ge(bal, amt), "low");

// ✅ AI FIX
euint64 actual = FHE.select(FHE.ge(bal, amt), amt, FHE.asEuint64(0));
balance = FHE.sub(balance, actual);
```

**Issue #4: "Coprocessor not initialized"**
```solidity
// 🔍 SYMPTOM: every FHE op reverts
// 🎯 AI FIX: inherit SepoliaConfig
contract MyContract is SepoliaConfig { /* ... */ }
```

**Issue #5: "Input proof: signer mismatch"**
```typescript
// 🔍 SYMPTOM: tx reverts at FHE.fromExternal
// 🎯 AI FIX: build the input for the actual signer
const enc = await fhevm
    .createEncryptedInput(contractAddr, await signer.getAddress())   // not someoneElseAddr
    .add32(amount)
    .encrypt();
```

**Issue #6: Oracle callback never resolves / "stale"**
```solidity
// 🔍 SYMPTOM: requestDecryption returns id but callback never updates state
// 🎯 AI FIX: ensure callback signature matches and checkSignatures is first
function onReveal(uint256 reqId, uint32 plain, bytes[] memory sigs) external {
    FHE.checkSignatures(reqId, sigs);   // FIRST LINE
    require(reqId == _pendingId, "stale");
    revealed = plain;
}
```

**Issue #7: Tests hanging in mock mode**
```typescript
// 🔍 SYMPTOM: oracle decryption test never completes
// 🎯 AI FIX: flush the mock oracle
await contract.requestReveal();
await fhevm.awaitDecryptionOracle();   // ADD THIS
expect(await contract.revealed()).to.equal(42n);
```

### 🎯 AI Debugging Prompts

**For ACL issues:**
> "This FHEVM contract has 'ACL: not allowed' errors. Add `FHE.allowThis` after every encrypted state write and `FHE.allow(_, msg.sender)` before every encrypted return: [code]"

**For compilation issues:**
> "Fix this FHEVM code that won't compile. Replace `if`/`require` on `ebool` with `FHE.select` and ensure inputs use `externalEuintN` + `bytes proof` validated via `FHE.fromExternal`: [code]"

**For decryption issues:**
> "This FHEVM oracle callback is being spoofed / never updates. Add `FHE.checkSignatures(requestId, signatures)` as the first line and verify the callback selector matches: [code]"

## 💡 AI Performance Tips

1. **Choose appropriate bit lengths** — `euint8`/`euint32` over `euint256` whenever possible.
2. **Cache encrypted constants** — store `FHE.asEuint64(0)` in storage with `allowThis`, reuse forever.
3. **Avoid recompute** — store the result of an `FHE.select` in a local var, don't call twice.
4. **Batch ACL grants** — one `allow` per handle per granted address, not per use.
5. **Prefer transient ACL for one-tx flows** — `allowTransient` is cheaper than persistent `allow`.
6. **Validate inputs first** — `FHE.fromExternal` is the gas-cheapest reject path; do it before expensive ops.
7. **Pick decryption flow by audience** — user-decrypt is **free** (off-chain only); avoid oracle async unless the contract genuinely needs the plaintext.

---

**🚀 AI Quick Start:** Use this reference to generate secure, efficient confidential smart contracts on the Zama Protocol. Pair with [`decryption.md`](./decryption.md) for full decryption flow details and [`anti-patterns.md`](./anti-patterns.md) for the extended catalog of mistakes to avoid.
