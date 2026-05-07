# FHEVM Gas Optimization

FHE ops are 100-1000× more expensive than equivalent plaintext ops. Optimization isn't optional — it's the difference between a $1 and $100 transaction.

---

## 1. Cost class table (rough Sepolia gas, plus coprocessor fee)

| Operation | euint8 | euint32 | euint64 | euint128 | euint256 |
|-----------|--------|---------|---------|----------|----------|
| `add` / `sub` | ~50k | ~70k | ~90k | ~140k | ~200k |
| `mul` | ~80k | ~120k | ~180k | ~300k | ~500k |
| `div(_, plain)` | ~60k | ~80k | ~110k | ~180k | ~280k |
| `eq` / `ne` / `lt` / `gt` | ~50k | ~70k | ~90k | ~140k | ~200k |
| `select` | ~40k | ~50k | ~70k | ~100k | ~150k |
| `and`/`or`/`xor` | ~40k | ~50k | ~70k | ~100k | ~150k |
| `fromExternal` | ~70k | ~80k | ~100k | ~150k | ~220k |
| `asEuintN(plain)` | ~30k | ~30k | ~40k | ~60k | ~80k |
| `allowThis` | ~30k | ~30k | ~30k | ~30k | ~30k |
| `allow(_, addr)` | ~50k | ~50k | ~50k | ~50k | ~50k |
| `allowTransient` | ~5k | ~5k | ~5k | ~5k | ~5k |

These are estimates — exact costs depend on coprocessor fees and gas market.

---

## 2. The biggest wins

### 2.1 Pick the smallest type

```solidity
euint256 counter;                // ❌ ~200k per add
euint8   counter;                // ✅ ~50k per add — 4× cheaper
```

`euint8` (0–255) for boolean-ish flags, small counters.
`euint32` (0–4B) for typical balances, prices.
`euint64` for token balances.
`euint128`/`256` only when range demands it.

### 2.2 Cache encrypted constants in storage

```solidity
// ❌ recreates each call
function bad() external {
    counter = FHE.add(counter, FHE.asEuint32(1));
}

// ✅ cached once
euint32 immutable_ish ONE_ENC;
constructor() { ONE_ENC = FHE.asEuint32(1); FHE.allowThis(ONE_ENC); }
function good() external {
    counter = FHE.add(counter, ONE_ENC);
}
```

`asEuintN` is cheap, but free is cheaper.

### 2.3 Don't recompute the same handle

```solidity
// ❌ FHE.gt called twice
result1 = FHE.select(FHE.gt(a, b), x, y);
result2 = FHE.select(FHE.gt(a, b), p, q);

// ✅ once
ebool cond = FHE.gt(a, b);
result1 = FHE.select(cond, x, y);
result2 = FHE.select(cond, p, q);
```

### 2.4 Use transient ACL for one-tx flows

```solidity
// ❌ persistent grant for a one-shot delegate
FHE.allow(v, recipient);
recipient.consume(v);

// ✅ transient — ~10× cheaper
FHE.allowTransient(v, recipient);
recipient.consume(v);
```

### 2.5 Batch user grants in one go

```solidity
// ❌ separate calls
FHE.allowThis(balanceFrom);
FHE.allowThis(balanceTo);
FHE.allow(balanceFrom, from);
FHE.allow(balanceTo, to);
```

Each `allow*` is a separate storage write. Order them at end of function — at least the EVM caches stack reads.

### 2.6 Avoid `FHE.mul` when shift works

```solidity
// ❌ multiplication
result = FHE.mul(value, FHE.asEuint64(2));

// ✅ shift left by 1
result = FHE.shl(value, 1);
```

Shifts are roughly half the cost of multiplications.

### 2.7 Prefer `FHE.eq(_, ZERO)` over comparisons against constants

```solidity
ebool isZero = FHE.eq(value, FHE.asEuint64(0));
```

Simpler than `FHE.lt(value, FHE.asEuint64(1))`.

### 2.8 Avoid loops over arrays

`O(N)` FHE ops scale linearly. For N > ~20, find an alternative:

```solidity
// ❌
euint64 total = FHE.asEuint64(0);
for (uint i; i < users.length; ++i) total = FHE.add(total, balances[users[i]]);

// ✅ — maintain running total inside each balance mutation
function deposit(...) external {
    totalSupply = FHE.add(totalSupply, amount);
    FHE.allowThis(totalSupply);
}
```

---

## 3. Comparison cost reductions

Comparisons return `ebool`. Cost order: `eq` ≈ `ne` < `lt` ≈ `gt` ≈ `le` ≈ `ge`. Equality is the cheapest.

If you can refactor `lt` to `eq` (e.g. checking against a small set of values), do it.

---

## 4. ACL gas patterns

| Pattern | Cost |
|---|---|
| `allowThis` on storage var (already there) | ~5k (no-op storage write) |
| `allowThis` on new var | ~30k (cold storage) |
| `allow(_, addr)` first time | ~50k |
| `allow(_, addr)` repeat | ~5k |
| `allowTransient` | ~5k always |

Repeated `allow(value, sameAddr)` is essentially free. Don't refactor to "save" by skipping it.

---

## 5. Storage layout

Encrypted handles are `uint256`. They take a full storage slot regardless of underlying type — `euint8` and `euint256` cost the same to store. Don't try to pack them.

---

## 6. Solidity-level micro-optimizations (these matter at FHE scale)

```solidity
// ✅ unchecked iterator
for (uint256 i; i < n; ) {
    /* ... */
    unchecked { ++i; }
}

// ✅ cache storage reads
euint64 bal = balances[msg.sender];
balances[msg.sender] = FHE.sub(bal, x);   // not balances[msg.sender] = FHE.sub(balances[msg.sender], ...);
```

The savings are noise compared to FHE op cost — but free is free.

---

## 7. Decryption flow cost

| Flow | On-chain gas | Off-chain | Latency |
|---|---|---|---|
| user-decrypt | 0 | sig + KMS roundtrip | < 1s |
| public-decrypt | one `makePubliclyDecryptable` (~30k) | KMS query | < 5s |
| oracle async | `requestDecryption` (~80k) + callback gas (~50k + handler logic) | KMS quorum + relay | 30s–2min |

**Prefer user-decrypt** wherever possible — it's free on-chain and instant.

Reserve oracle async for cases where Solidity needs the plaintext to act on it.

---

## 8. Profiling

Use Hardhat's gas reporter:

```ts
// hardhat.config.ts
import "hardhat-gas-reporter";

export default {
    gasReporter: {
        enabled: true,
        currency: "USD",
        excludeContracts: ["mocks/"],
    },
};
```

Run tests with `REPORT_GAS=true npx hardhat test`. Compare runs as you optimize.

⚠️ Gas reporter shows only EVM gas, not coprocessor fees. Real cost = EVM gas × Sepolia ETH price + coprocessor fee per FHE op.

---

## 9. Top 10 optimization checklist

1. ✅ Smallest encrypted type that fits the value range
2. ✅ Cache encrypted constants (especially zero) in storage
3. ✅ Compute each handle once, reuse
4. ✅ `allowTransient` for one-tx delegations
5. ✅ Replace `mul(_, 2^k)` with `shl(_, k)`
6. ✅ Avoid loops over user arrays — use running totals
7. ✅ Prefer `FHE.eq` to `FHE.lt`/`FHE.gt` when possible
8. ✅ Choose user-decrypt > public-decrypt > oracle async
9. ✅ Order ACL grants at function tail (warmer storage)
10. ✅ Profile with gas-reporter, optimize the hot paths
