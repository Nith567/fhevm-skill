# Decryption Flows

FHEVM has **three** distinct decryption mechanisms. Pick by audience and trust model.

| Flow | Audience | Trigger | Cost | Use for |
|---|---|---|---|---|
| **User decrypt** | A specific user | Off-chain EIP-712 signature → KMS | Free (off-chain) | Personal balance, private profile |
| **Public decrypt** | Anyone | Off-chain `relayer.publicDecrypt` after on-chain mark | One small tx + off-chain call | Auction winner, vote tally, settled price |
| **Oracle async** | The contract itself | `FHE.requestDecryption` + KMS callback | Two txs | Bringing plaintext on-chain to settle to a non-FHE protocol |

---

## 1. User Decryption (EIP-712)

### Solidity side
Nothing special — just make sure the user is on the handle's ACL:

```solidity
function balanceOf(address u) external view returns (euint64) {
    require(FHE.isSenderAllowed(balances[u]) || msg.sender == u, "no");
    return balances[u];
}

function deposit(externalEuint64 enc, bytes calldata proof) external {
    euint64 amt = FHE.fromExternal(enc, proof);
    balances[msg.sender] = FHE.add(balances[msg.sender], amt);
    FHE.allowThis(balances[msg.sender]);
    FHE.allow(balances[msg.sender], msg.sender);   // <-- required for user-decrypt
}
```

### Frontend side

```ts
import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/bundle";

const fhevm = await createInstance(SepoliaConfig);

// 1. Generate an ephemeral keypair
const keypair = fhevm.generateKeypair();

// 2. Build the EIP-712 typed data
const startTimestamp = Math.floor(Date.now() / 1000).toString();
const durationDays   = "10";
const contractAddrs  = [CONTRACT_ADDRESS];

const eip712 = fhevm.createEIP712(
    keypair.publicKey,
    contractAddrs,
    startTimestamp,
    durationDays,
);

// 3. User signs (MetaMask, etc.)
const signature = await signer.signTypedData(
    eip712.domain,
    { UserDecryptRequestVerification: eip712.types.UserDecryptRequestVerification },
    eip712.message,
);

// 4. Fetch the handle from chain
const handle = await contract.balanceOf(userAddr);

// 5. Reencrypt + decrypt via KMS
const result = await fhevm.userDecrypt(
    [{ handle, contractAddress: CONTRACT_ADDRESS }],
    keypair.privateKey,
    keypair.publicKey,
    signature.replace("0x", ""),
    contractAddrs,
    userAddr,
    startTimestamp,
    durationDays,
);
console.log("Plaintext balance:", result[handle]);   // bigint
```

The signature is reusable for any handle in the listed contracts during the duration window — sign once, decrypt many.

### Common mistakes
- Forgetting to `FHE.allow(handle, user)` on the producing tx → KMS rejects with "unauthorized".
- Signing with the wrong user (must be the same address that's on the ACL).
- Listing the wrong contract address in `createEIP712`.

---

## 2. Public Decryption

### Solidity side

```solidity
function reveal() external {
    require(block.timestamp > endTime, "too early");
    FHE.makePubliclyDecryptable(winningBid);
    FHE.makePubliclyDecryptable(winnerAddr);
}
```

`makePubliclyDecryptable` is **persistent and irreversible**. Use it only when the value should be globally visible forever.

### Frontend side

```ts
const handles = [
    await contract.winningBid(),
    await contract.winnerAddr(),
];
const result = await fhevm.publicDecrypt(handles);
console.log(result[handles[0]], result[handles[1]]);
```

Anyone — including non-participants — can call this after the contract marks the handles.

---

## 3. Oracle Async Decryption (`FHE.requestDecryption`)

Use when **the contract** needs the plaintext on-chain to act on it (forward to a non-FHE protocol, emit an event, gate a transfer).

### The pattern

```solidity
import {FHE, euint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig}       from "@fhevm/solidity/config/ZamaConfig.sol";

contract Settler is SepoliaConfig {
    euint64 private encAmount;
    uint256 public  pendingRequestId;

    function startSettlement(uint64 plainExpected) external { /* … */
        bytes32[] memory cts = new bytes32[](1);
        cts[0] = FHE.toBytes32(encAmount);
        pendingRequestId = FHE.requestDecryption(cts, this.onAmountDecrypted.selector);
    }

    /// @notice Callback invoked by the KMS in a LATER transaction.
    /// @dev Parameters after `requestId` MUST be in the same order/types as `cts[]`.
    function onAmountDecrypted(
        uint256 requestId,
        uint64  plain,           // matches cts[0] = encAmount (euint64)
        bytes[] memory signatures
    ) external {
        FHE.checkSignatures(requestId, signatures);     // <-- ALWAYS first
        require(requestId == pendingRequestId, "stale");
        delete pendingRequestId;

        // … now use `plain` to settle
    }
}
```

### Multi-handle decryption

```solidity
bytes32[] memory cts = new bytes32[](3);
cts[0] = FHE.toBytes32(eAmount);   // euint64
cts[1] = FHE.toBytes32(eBidder);   // eaddress
cts[2] = FHE.toBytes32(eFlag);     // ebool
uint256 reqId = FHE.requestDecryption(cts, this.onReveal.selector);

function onReveal(
    uint256 requestId,
    uint64  amount,
    address bidder,
    bool    flag,
    bytes[] memory signatures
) external {
    FHE.checkSignatures(requestId, signatures);
    // …
}
```

The decoded types must line up. `eaddress` decodes to `address`, `ebool` to `bool`, `euintN` to the smallest native `uintN` that fits.

### Security checklist for callbacks

1. **First line**: `FHE.checkSignatures(requestId, signatures);`
2. Verify `requestId` matches a pending request you initiated.
3. Clear the pending state before doing external calls (re-entrancy).
4. Don't trust the parameter values — checkSignatures already verified them, but match `requestId` to scope.

### Failure modes

| Scenario | Behaviour |
|---|---|
| Callback called twice with same id | re-validate `requestId == pending` and reject |
| Caller spoofs the KMS | `checkSignatures` reverts |
| Plaintext too large for callback type | the contract-level `requestDecryption` reverts at request time |
| Decryption oracle is down | callback never arrives — design for retries via a new request |

### Re-running a decryption

If a callback fails, the request is consumed. To retry, call `requestDecryption` again — you'll get a new `requestId` for the same ciphertexts. Don't try to "replay" the previous id.

---

## 4. Choosing between flows

```
Need plaintext where?
├── In a user's UI → user decrypt (EIP-712)
├── For everyone, after some condition → public decrypt
└── In Solidity (e.g. forward to ERC-20) → oracle async
```

Mixing flows is fine — e.g. a confidential auction may use **user-decrypt** for each bidder to see their own bid status, and **public-decrypt** for the winner reveal.

---

## 5. Testing decryption

In Hardhat with the FHEVM plugin:

```ts
// User decrypt — synchronous in mock mode
const plain = await fhevm.userDecryptEuint(
    FhevmType.euint64, handle, contractAddr, signer
);

// Public decrypt
const plain = await fhevm.publicDecryptEuint(FhevmType.euint64, handle);

// Oracle async — flush all pending callbacks
await contract.requestReveal();
await fhevm.awaitDecryptionOracle();   // mock fast-forward
expect(await contract.revealed()).to.equal(42);
```

In Sepolia mode (`--network sepolia`) the oracle callback arrives in real time (~30s) and you must `await tx.wait()` plus poll for the resulting state change. Tests still pass — just slower.

---

See [`frontend.md`](./frontend.md) for the relayer SDK end-to-end and [`testing.md`](./testing.md) for the full test recipe.
