# FHEVM Patterns Cookbook

Composable, copy-paste patterns for the situations you actually run into.

---

## 1. Conditional state update (the bread-and-butter)

```solidity
ebool ok = FHE.ge(balance[from], amount);
euint64 actual = FHE.select(ok, amount, FHE.asEuint64(0));
balance[from] = FHE.sub(balance[from], actual);
balance[to]   = FHE.add(balance[to],   actual);
FHE.allowThis(balance[from]); FHE.allow(balance[from], from);
FHE.allowThis(balance[to]);   FHE.allow(balance[to], to);
```

Used everywhere — transfers, deposits, conditional minting.

---

## 2. Encrypted max accumulator

```solidity
ebool higher    = FHE.gt(newVal, currentMax);
currentMax      = FHE.select(higher, newVal,    currentMax);
currentLeader   = FHE.select(higher, newAddr,   currentLeader);
FHE.allowThis(currentMax);
FHE.allowThis(currentLeader);
```

Used in: blind auctions, leaderboards, encrypted ranking.

---

## 3. Encrypted min accumulator

```solidity
ebool lower = FHE.lt(newVal, currentMin);
currentMin  = FHE.select(lower, newVal, currentMin);
FHE.allowThis(currentMin);
```

---

## 4. Encrypted sum over array

```solidity
euint64 total = FHE.asEuint64(0);
for (uint i; i < items.length; ++i) {
    total = FHE.add(total, items[i]);
}
FHE.allowThis(total);
```

⚠️ Gas scales linearly. For N > ~50 consider chunked off-chain aggregation.

---

## 5. Encrypted average

```solidity
euint64 sum = FHE.asEuint64(0);
for (uint i; i < n; ++i) sum = FHE.add(sum, items[i]);
euint64 avg = FHE.div(sum, uint64(n));
FHE.allowThis(avg);
```

`FHE.div` accepts plaintext divisor → use `n` directly.

---

## 6. One-time secret with reveal flag

```solidity
euint64 private _secret;
bool    public  revealed;
uint64  public  revealedValue;

function reveal() external onlyAuthorized {
    bytes32[] memory cts = new bytes32[](1);
    cts[0] = FHE.toBytes32(_secret);
    _pendingId = FHE.requestDecryption(cts, this.onReveal.selector);
}

function onReveal(uint256 id, uint64 v, bytes[] memory sigs) external {
    FHE.checkSignatures(id, sigs);
    require(id == _pendingId, "stale");
    revealed = true;
    revealedValue = v;
    _pendingId = 0;
}
```

---

## 7. Conditional event emission (without leaking which branch)

You **cannot** emit different events based on an `ebool` — both branches always run, and emit is plaintext. Workaround: emit once with the encrypted handle, decrypt off-chain.

```solidity
event Conditional(address indexed user, ebool encResult);

function check() external returns (ebool) {
    ebool r = FHE.gt(secret[msg.sender], FHE.asEuint64(threshold));
    FHE.allow(r, msg.sender);
    emit Conditional(msg.sender, r);
    return r;
}
```

---

## 8. Stateful encrypted counter with cap

```solidity
function increment(externalEuint32 enc, bytes calldata p) external {
    euint32 delta = FHE.fromExternal(enc, p);
    euint32 newVal = FHE.add(counter, delta);
    ebool   under = FHE.le(newVal, FHE.asEuint32(MAX));
    counter = FHE.select(under, newVal, counter);   // discard if over cap
    FHE.allowThis(counter);
    FHE.allow(counter, msg.sender);
}
```

The cap check leaks no information about the actual value.

---

## 9. Encrypted ratio / percentage

```solidity
function pctOf(euint64 numerator, uint64 plainDenominator)
    internal returns (euint64)
{
    return FHE.div(FHE.mul(numerator, FHE.asEuint64(100)), plainDenominator);
}
```

For encrypted denominator, decrypt via oracle first (or reformulate).

---

## 10. Encrypted whitelist check

```solidity
mapping(address => ebool) public allowedEnc;

function setAllowed(address user, externalEbool enc, bytes calldata p) external onlyAdmin {
    allowedEnc[user] = FHE.fromExternal(enc, p);
    FHE.allowThis(allowedEnc[user]);
    FHE.allow(allowedEnc[user], user);
}

function action(externalEuint64 encAmt, bytes calldata p) external {
    ebool ok = FHE.and(allowedEnc[msg.sender], FHE.asEbool(true));
    euint64 amt = FHE.fromExternal(encAmt, p);
    euint64 actual = FHE.select(ok, amt, FHE.asEuint64(0));
    _doAction(actual);
}
```

Whitelist status itself stays encrypted — even from an observer.

---

## 11. Time-bounded transient ACL grant

```solidity
function singleUseShare(address recipient, euint64 v) external {
    FHE.allowTransient(v, recipient);
    IRecipient(recipient).consume(v);
}
```

`allowTransient` evaporates at the end of the tx. Cheap, no storage cost.

---

## 12. Permission inheritance chain

```solidity
contract A { function expose() external returns (euint64) { /* allow B */ } }
contract B { function relay()  external returns (euint64) { /* allow C */ } }
contract C { function consume(euint64) external; }
```

Each hop must explicitly grant the next. ACL doesn't propagate automatically.

---

## 13. Multi-handle batch decryption

```solidity
function batchReveal(euint64[] memory items) external {
    uint256 n = items.length;
    bytes32[] memory cts = new bytes32[](n);
    for (uint i; i < n; ++i) cts[i] = FHE.toBytes32(items[i]);
    _pendingId = FHE.requestDecryption(cts, this.onBatch.selector);
}

function onBatch(
    uint256 reqId,
    uint64 a, uint64 b, uint64 c,
    bytes[] memory sigs
) external {
    FHE.checkSignatures(reqId, sigs);
    /* ... */
}
```

⚠️ Callback signature must enumerate every item explicitly. Solidity won't decode an array of plaintext into a `uint64[]` for you.

For a variable-length batch, do it in fixed-size chunks or store handles individually.

---

## 14. Encrypted state migration (read old → write new)

```solidity
function migrate() external onlyAdmin {
    for (uint i; i < users.length; ++i) {
        address u = users[i];
        euint64 oldBal = oldVault.balanceOf(u);
        oldVault.shareWith(address(this));      // ACL grant
        balances[u] = oldBal;
        FHE.allowThis(balances[u]);
        FHE.allow(balances[u], u);
    }
}
```

---

## 15. Conditional re-key (rotate ACL)

If a user transfers an account, re-key access:

```solidity
function transferAccount(address newOwner) external {
    FHE.allow(balances[msg.sender], newOwner);
    balances[newOwner] = balances[msg.sender];
    FHE.allowThis(balances[newOwner]);
    delete balances[msg.sender];
}
```

⚠️ Old owner still has ACL on the original handle (persistent). For revocation, re-encrypt to a fresh handle (encrypted-add 0):

```solidity
balances[newOwner] = FHE.add(balances[msg.sender], FHE.asEuint64(0));
FHE.allowThis(balances[newOwner]);
FHE.allow(balances[newOwner], newOwner);
delete balances[msg.sender];
```

The new handle has a brand-new ACL — old owner is excluded.

---

## 16. Encrypted struct in storage

```solidity
struct Position {
    euint64 collateral;
    euint64 debt;
    bool    active;
}

mapping(address => Position) public positions;

function openPosition(externalEuint64 col, externalEuint64 debt, bytes calldata p) external {
    Position storage pos = positions[msg.sender];
    pos.collateral = FHE.fromExternal(col, p);
    pos.debt       = FHE.fromExternal(debt, p);
    pos.active     = true;
    FHE.allowThis(pos.collateral);
    FHE.allowThis(pos.debt);
    FHE.allow(pos.collateral, msg.sender);
    FHE.allow(pos.debt, msg.sender);
}
```

Each encrypted field needs its own ACL. Don't forget any.

---

## 17. Encrypted access-controlled getter

```solidity
function balanceOf(address u) external view returns (euint64) {
    require(msg.sender == u || isOperator[u][msg.sender], "no access");
    return balances[u];
}
```

The `require` is plaintext — it leaks who's asking. The encrypted balance itself is still safe (only ACL-listed addresses can decrypt off-chain). For metadata privacy, consider not gating reads at all and relying purely on ACL.

---

## 18. Re-entrancy pattern with pending decryption

```solidity
function settle() external {
    require(_pendingId == 0, "already pending");
    _pendingId = type(uint256).max;
    bytes32[] memory cts = new bytes32[](1);
    cts[0] = FHE.toBytes32(secret);
    _pendingId = FHE.requestDecryption(cts, this.onSettle.selector);
}

function onSettle(uint256 id, uint64 v, bytes[] memory sigs) external {
    FHE.checkSignatures(id, sigs);
    require(id == _pendingId, "stale");
    delete _pendingId;
    _externalCallback(v);
}
```

Set the lock before the request, clear in callback. Prevents double-settlement.

---

## 19. Composing ACL with operator pattern (ERC-7984 inspired)

```solidity
mapping(address => mapping(address => uint256)) public operatorUntil;

function setOperator(address op, uint256 until) external {
    operatorUntil[msg.sender][op] = until;
    FHE.allow(balance[msg.sender], op);
}

function isAuthorized(address holder) internal view returns (bool) {
    return holder == msg.sender || operatorUntil[holder][msg.sender] > block.timestamp;
}
```

Time-bounded delegation without revealing amounts.

---

## 20. Avoiding loops over all users

When you must aggregate over N users, prefer:
- **Off-chain aggregation** with `relayer.userDecrypt` per holder, sum client-side
- **Incremental aggregation** — update the running total inside each user's mutation
- **Chunked oracle reveals** — reveal sums of buckets

The naive `for (i in users)` pattern works but blows gas budgets fast.
