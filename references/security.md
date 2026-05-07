# FHEVM Security Guide

Threats specific to confidential smart contracts and the patterns that defend against them. Read this **before** writing a contract that holds value.

---

## 1. The trust model

What FHEVM protects:
- ✅ Stored encrypted values are unreadable by anyone outside the ACL.
- ✅ Encrypted inputs are bound to (contract, sender) by ZK proof — can't be replayed.
- ✅ The KMS only releases plaintext to addresses on the ACL.

What FHEVM does **NOT** protect:
- ❌ Public state (balances of ETH, mappings of plaintext addresses, event logs).
- ❌ Transaction metadata (who called what, when, with what gas).
- ❌ Side channels in your code (timing of `require`s, branching on plaintext flags).
- ❌ The user's local environment (wallet signing prompts, RPC provider).

---

## 2. Common vulnerability classes

### 2.1 ACL leakage

Calling `FHE.makePubliclyDecryptable` on user-private data permanently leaks every value derived from it.

❌ **Wrong**
```solidity
function balanceOf(address u) external returns (euint64) {
    FHE.makePubliclyDecryptable(balances[u]);
    return balances[u];
}
```

✅ **Right** — use per-user `FHE.allow`:
```solidity
function balanceOf(address u) external view returns (euint64) {
    return balances[u];
}

function deposit(...) external {
    balances[msg.sender] = FHE.add(balances[msg.sender], amount);
    FHE.allowThis(balances[msg.sender]);
    FHE.allow(balances[msg.sender], msg.sender);
}
```

### 2.2 Spoofed oracle callbacks

Without `FHE.checkSignatures`, anyone can call the callback with a forged plaintext.

❌ **Critical bug**
```solidity
function onReveal(uint256 id, uint64 plain, bytes[] memory) external {
    revealed = plain;
}
```

✅ **Right**
```solidity
function onReveal(uint256 id, uint64 plain, bytes[] memory sigs) external {
    FHE.checkSignatures(id, sigs);
    require(id == _pendingId, "stale");
    revealed = plain;
}
```

### 2.3 Stale decryption replay

If you don't check the `requestId` against a stored pending id, an old callback can overwrite new state.

❌ **Wrong**
```solidity
function onReveal(uint256 id, uint64 v, bytes[] memory sigs) external {
    FHE.checkSignatures(id, sigs);
    revealed = v;
}
```

A second `requestDecryption` triggers a second callback; if the first arrives later, it overwrites the second's result.

✅ **Right**
```solidity
function requestReveal() external {
    require(_pendingId == 0, "already pending");
    _pendingId = FHE.requestDecryption(...);
}

function onReveal(uint256 id, uint64 v, bytes[] memory sigs) external {
    FHE.checkSignatures(id, sigs);
    require(id == _pendingId, "stale");
    _pendingId = 0;
    revealed = v;
}
```

### 2.4 Re-entrancy via callback

Oracle callbacks run in their own tx. They CAN call back into your contract.

❌ **Wrong**
```solidity
function onSettle(uint256 id, uint64 v, bytes[] memory sigs) external {
    FHE.checkSignatures(id, sigs);
    payable(winner).call{value: v}("");      // external call BEFORE state update
    settled = true;
}
```

✅ **Right** — checks-effects-interactions:
```solidity
function onSettle(uint256 id, uint64 v, bytes[] memory sigs) external {
    FHE.checkSignatures(id, sigs);
    require(id == _pendingId, "stale");
    settled = true;
    _pendingId = 0;
    payable(winner).call{value: v}("");
}
```

### 2.5 Input proof reuse across contracts

The proof binds (contract, sender). A proof for contract A cannot be used in contract B — `FHE.fromExternal` will revert. **But**: never expose user-provided proofs in events; while they can't be replayed, exposing them adds no benefit.

### 2.6 Plaintext leakage via gas / timing

Branching on a plaintext flag derived from encrypted data is a side channel:

```solidity
ebool       cond  = FHE.gt(secret, threshold);
// later, in oracle callback:
function onCb(uint256 id, bool plain, bytes[] memory sigs) external {
    FHE.checkSignatures(id, sigs);
    if (plain) {
        expensiveOperation();   // gas usage leaks the value
    }
}
```

Once the value is decrypted, it's plaintext — that's expected. But if the comparison was meant to stay encrypted, don't decrypt it.

### 2.7 Truncation on narrowing casts

```solidity
euint64 big = balance;
euint8  small = FHE.asEuint8(big);  // silently truncates!
```

If `big > 255`, `small` becomes `big & 0xff`, completely changing the value. Always range-check before narrowing.

### 2.8 Wraparound on arithmetic

```solidity
balance = FHE.sub(balance, amount);   // wraps if amount > balance
```

Without `FHE.select(canPay, ...)`, an underflow becomes a huge balance. **Always gate subtractions with comparisons.**

### 2.9 Front-running encrypted inputs

The encrypted ciphertext is public on-chain. An attacker can:
- See **that** you sent a tx.
- See **how much gas** you used.
- See the **input proof bytes** (but not the plaintext).

If your contract behaviour depends on order (auctions, AMMs), MEV applies. Mitigate with commit-reveal, batch auctions, or confidential ordering.

### 2.10 Owner-extractable encrypted state

If contract code exposes a `decryptAll()` admin function, the owner can decrypt everything. Audit for:
- `onlyOwner` functions calling `FHE.requestDecryption` on user state
- `FHE.allow(userBalance, owner)` patterns
- Operator approvals that don't expire

### 2.11 The encrypted-zero distinguishing attack

If you initialize uninitialized values to a publicly known constant (0), an observer can sometimes distinguish "zero" from "known plaintext zero" via gas patterns. Practical impact is low but worth knowing.

### 2.12 ACL persistence after revocation

There is no `FHE.revoke`. Once granted, ACL is forever (or at least, until the handle is overwritten with a new one). For revocation:
1. Re-key by adding encrypted zero: `newH = FHE.add(oldH, FHE.asEuint64(0))`
2. Update storage to `newH`, allowThis + allow new owner
3. Old ACL pointed at oldH; oldH is now orphaned

---

## 3. Audit checklist

Before deploying to mainnet, verify:

- [ ] Every contract inherits `SepoliaConfig` (or matching network config)
- [ ] Every state-mutating function ends with `FHE.allowThis(handle)`
- [ ] Every function returning encrypted state grants `FHE.allow(handle, msg.sender)`
- [ ] Every external input is validated via `FHE.fromExternal(handle, proof)`
- [ ] Every oracle callback starts with `FHE.checkSignatures(requestId, signatures)`
- [ ] Every oracle callback verifies `requestId == _pendingId`
- [ ] Pending request flag is cleared **before** any external call in callbacks
- [ ] No `FHE.makePubliclyDecryptable` on per-user data
- [ ] Subtractions are gated with `FHE.ge` + `FHE.select` to avoid wraparound
- [ ] Narrowing casts are preceded by range checks
- [ ] No `if (eboolValue)` or `require(eboolValue)` — only `FHE.select`
- [ ] Encrypted division has plaintext divisor
- [ ] Operator approvals expire (no permanent third-party access)
- [ ] Admin / owner functions are minimal — no global decrypt backdoors
- [ ] Re-entrancy guards on oracle callbacks if they call out
- [ ] Tests cover: ACL grants, unauthorized decrypt attempts, replay attempts, callback signature failures

---

## 4. Defensive coding patterns

### 4.1 ACL guard helper

```solidity
modifier ensureUserAcl(euint64 h) {
    require(FHE.isSenderAllowed(h), "no access");
    _;
}
```

Apply on functions where the caller must already have decrypt rights.

### 4.2 Reentrancy lock for pending decryption

```solidity
modifier noPending() {
    require(_pendingId == 0, "pending decryption");
    _;
}
```

### 4.3 Bounded loops

```solidity
function batchProcess(uint256 batchSize) external {
    uint256 end = nextIndex + batchSize;
    require(end <= users.length, "out of bounds");
    require(batchSize <= MAX_BATCH, "batch too big");
    for (uint i = nextIndex; i < end; ++i) {
        _process(users[i]);
    }
    nextIndex = end;
}
```

Never `for (uint i; i < users.length; ++i)` if `users` can grow without bound.

### 4.4 Explicit ACL revocation via re-key

```solidity
function revokeAccess(address u) external onlyAdmin {
    balances[u] = FHE.add(balances[u], FHE.asEuint64(0));
    FHE.allowThis(balances[u]);
    FHE.allow(balances[u], u);
}
```

Old grants point at the old handle. The new handle starts with a fresh ACL (admin not on it).

---

## 5. Testing for security

```typescript
it("rejects spoofed callback", async () => {
    await expect(
        contract.connect(attacker).onReveal(99, 999, [])
    ).to.be.reverted;
});

it("rejects unauthorized decrypt", async () => {
    const handle = await contract.balanceOf(alice.address);
    await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, handle, addr, bob)
    ).to.be.rejected;
});

it("rejects input proof from different signer", async () => {
    const enc = await fhevm.createEncryptedInput(addr, bob.address).add64(1n).encrypt();
    await expect(
        contract.connect(alice).deposit(enc.handles[0], enc.inputProof)
    ).to.be.reverted;
});

it("prevents stale callback overwrite", async () => {
    await contract.requestReveal();
    await contract.fakeCallback(0, 999, []);
    expect(await contract.revealed()).to.equal(0n);
});
```

---

## 6. When in doubt

1. Decrypt as little as possible — every `requestDecryption` is a privacy hole.
2. Use `FHE.allow` (per-user) over `makePubliclyDecryptable` (global).
3. Treat the relayer as untrusted infrastructure — it can't decrypt without KMS, but it can drop or delay messages.
4. Audit ACL grants like you'd audit `transferOwnership` — once granted, hard to revoke.
5. Get a second opinion. The Zama team and community review confidential contract design — use them.
