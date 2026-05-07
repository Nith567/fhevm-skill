# FHEVM Anti-Patterns

Each entry: the broken pattern, what goes wrong, the fix.

---

## 1. Branching on `ebool`

**Broken**

```solidity
ebool ok = FHE.gte(balance, amount);
if (ok) {
    balance = FHE.sub(balance, amount);
}
```

`ebool` is a `uint256` handle, not a Solidity bool. The compiler rejects this.

**Fix**

```solidity
ebool ok = FHE.gte(balance, amount);
euint64 delta = FHE.select(ok, amount, FHE.asEuint64(0));
balance = FHE.sub(balance, delta);
FHE.allowThis(balance);
FHE.allow(balance, msg.sender);
```

---

## 2. Missing `FHE.allowThis` after a state write

**Broken**

```solidity
function set(externalEuint32 enc, bytes calldata p) external {
    counter = FHE.fromExternal(enc, p);
}

function inc() external {
    counter = FHE.add(counter, FHE.asEuint32(1));
}
```

The next call reverts with `ACL: contract not allowed`.

**Fix**

```solidity
function set(externalEuint32 enc, bytes calldata p) external {
    counter = FHE.fromExternal(enc, p);
    FHE.allowThis(counter);
    FHE.allow(counter, msg.sender);
}

function inc() external {
    counter = FHE.add(counter, FHE.asEuint32(1));
    FHE.allowThis(counter);
    FHE.allow(counter, msg.sender);
}
```

Rule: every assignment of an encrypted state variable is followed by `allowThis` and (usually) `allow(_, msg.sender)`.

---

## 3. Returning encrypted state from `view` and expecting plaintext

**Broken (frontend)**

```ts
const bal = await contract.balanceOf(user);
console.log("Balance:", bal);
```

`bal` is a `bytes32` handle, not the number. Logging it shows hex.

**Fix**

```ts
const handle = await contract.balanceOf(user);
const plain  = await userDecryptOne(fhevm, signer, handle, contractAddr);
console.log("Balance:", plain);
```

The view function returns the handle correctly — you must user-decrypt off-chain.

---

## 4. Skipping `FHE.fromExternal`

**Broken**

```solidity
function deposit(externalEuint64 enc, bytes calldata proof) external {
    balances[msg.sender] = euint64.wrap(externalEuint64.unwrap(enc));
}
```

Bypasses proof verification. An attacker can pass any handle.

**Fix**

```solidity
function deposit(externalEuint64 enc, bytes calldata proof) external {
    euint64 amt = FHE.fromExternal(enc, proof);
    balances[msg.sender] = FHE.add(balances[msg.sender], amt);
    FHE.allowThis(balances[msg.sender]);
    FHE.allow(balances[msg.sender], msg.sender);
}
```

---

## 5. Reading plaintext in the same tx as `requestDecryption`

**Broken**

```solidity
function reveal() external returns (uint64) {
    bytes32[] memory cts = new bytes32[](1);
    cts[0] = FHE.toBytes32(secret);
    FHE.requestDecryption(cts, this.cb.selector);
    return revealed;
}
```

`revealed` is whatever it was before the request. The KMS callback hasn't run.

**Fix**

```solidity
function reveal() external {
    bytes32[] memory cts = new bytes32[](1);
    cts[0] = FHE.toBytes32(secret);
    pendingId = FHE.requestDecryption(cts, this.cb.selector);
}

function cb(uint256 id, uint64 plain, bytes[] memory sigs) external {
    FHE.checkSignatures(id, sigs);
    require(id == pendingId);
    revealed = plain;
}
```

The frontend polls `revealed` (or listens for an event) to see the result.

---

## 6. Forgetting `FHE.checkSignatures` in the oracle callback

**Broken**

```solidity
function cb(uint256 id, uint64 plain, bytes[] memory) external {
    revealed = plain;
}
```

Anyone can call this and feed any value. Total compromise.

**Fix**

```solidity
function cb(uint256 id, uint64 plain, bytes[] memory sigs) external {
    FHE.checkSignatures(id, sigs);
    require(id == pendingId, "stale");
    revealed = plain;
}
```

`checkSignatures` is non-negotiable. Always the first line.

---

## 7. Dividing by an encrypted value

**Broken**

```solidity
euint32 result = FHE.div(a, b);
```

Panics. FHE division requires a plaintext divisor.

**Fix**

```solidity
euint32 result = FHE.div(a, plainDivisor);
```

If you genuinely need both encrypted, decrypt one via the oracle first.

---

## 8. Wrong order: granting ACL on the previous handle

**Broken**

```solidity
function deposit(externalEuint64 enc, bytes calldata p) external {
    FHE.allow(balance, msg.sender);
    balance = FHE.fromExternal(enc, p);
}
```

`allow` runs against the *old* handle. The new one has no user ACL.

**Fix: write first, ACL second.**

```solidity
function deposit(externalEuint64 enc, bytes calldata p) external {
    balance = FHE.fromExternal(enc, p);
    FHE.allowThis(balance);
    FHE.allow(balance, msg.sender);
}
```

---

## 9. Defaulting to `euint256`

**Broken**

```solidity
euint256 counter;
counter = FHE.add(counter, FHE.asEuint256(1));
```

Wildly expensive for a counter that will never exceed `2³²`.

**Fix**

```solidity
euint32 counter;
counter = FHE.add(counter, FHE.asEuint32(1));
```

Match the type to the value range.

---

## 10. Reusing an input proof across users

**Broken**

```ts
const enc = await fhevm.createEncryptedInput(contractAddr, alice).add64(100n).encrypt();
await contract.connect(bob).deposit(enc.handles[0], enc.inputProof);
```

`FHE.fromExternal` reverts: proof binds `(contract, alice)`, but the tx signer is `bob`.

**Fix:** generate a fresh input per signer.

---

## 11. Encrypted comparisons in `require`

**Broken**

```solidity
require(FHE.gte(balance, amount), "insufficient");
```

`FHE.gte` returns `ebool`, not `bool`. Doesn't compile.

**Fix:** restructure with `FHE.select`, or oracle-decrypt the bool first.

```solidity
ebool ok = FHE.gte(balance, amount);
balance = FHE.sub(balance, FHE.select(ok, amount, FHE.asEuint64(0)));
```

---

## 12. Forgetting `is SepoliaConfig`

**Broken**

```solidity
contract Counter {
    euint32 c;
    function inc() external { c = FHE.add(c, FHE.asEuint32(1)); }
}
```

Every FHE op reverts (precompile addresses unset).

**Fix**

```solidity
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
contract Counter is SepoliaConfig {
    euint32 c;
    function inc() external {
        c = FHE.add(c, FHE.asEuint32(1));
        FHE.allowThis(c);
    }
}
```

---

## 13. Calling `makePubliclyDecryptable` on user-private data

**Broken**

```solidity
function balanceOf(address u) external returns (euint64) {
    FHE.makePubliclyDecryptable(balances[u]);
    return balances[u];
}
```

Permanently leaks every user's balance to the world.

**Fix:** use `FHE.allow(balances[u], u)` and let the user user-decrypt. Reserve `makePubliclyDecryptable` for explicitly-public results.

---

## 14. Using legacy `TFHE.sol`

**Broken**

```solidity
import "fhevm/lib/TFHE.sol";
TFHE.add(a, b);
```

Old API; package no longer maintained for the current Zama Protocol.

**Fix**

```solidity
import {FHE} from "@fhevm/solidity/lib/FHE.sol";
FHE.add(a, b);
```

---

## 15. Expecting `FHE.select` to short-circuit

**Broken assumption**

```solidity
result = FHE.select(cheapCheck, expensiveBranch, cheapDefault);
```

`expensiveBranch` runs every time.

**Fix:** if a branch is expensive, gate the *call site*, not the encrypted value. Or denote the expensive computation with a plaintext flag the user passes in.
