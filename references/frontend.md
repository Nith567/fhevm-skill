# Frontend Integration — `@zama-fhe/relayer-sdk`

The relayer SDK is the **modern fhevmjs**. It runs in browser and Node, talks to the Gateway/Relayer + KMS, and gives you three primitives: encrypt inputs, user-decrypt, public-decrypt.

> Old guides reference `fhevmjs`. That package still exists but is superseded — the current package is **`@zama-fhe/relayer-sdk`**.

---

## 1. Install

```bash
npm i @zama-fhe/relayer-sdk
```

Two entry points ship in the package:

- `@zama-fhe/relayer-sdk/bundle` — pre-bundled for browsers (Vite, Next, plain `<script>`)
- `@zama-fhe/relayer-sdk/node` — Node.js / SSR / Hardhat scripts

Pick the right one for the environment.

---

## 2. Create an instance

```ts
import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/bundle";

// Browser with MetaMask
const fhevm = await createInstance({
    ...SepoliaConfig,
    network: window.ethereum,     // EIP-1193 provider
});

// Node
import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/node";
const fhevm = await createInstance({
    ...SepoliaConfig,
    network: process.env.SEPOLIA_RPC_URL,
});
```

The instance fetches the public KMS keys, ACL contract address, gateway URL — all wrapped in `SepoliaConfig`. Cache the instance globally; creating it repeatedly is wasteful (it does network fetches).

---

## 3. Encrypt input for a contract call

```ts
const buf = fhevm.createEncryptedInput(contractAddr, userAddr);
buf.add8(255);          // → externalEuint8   at index 0
buf.add16(1234);        // → externalEuint16  at index 1
buf.add32(1_000_000n);  // → externalEuint32  at index 2
buf.add64(amountBig);   // → externalEuint64  at index 3
buf.addBool(true);      // → externalEbool    at index 4
buf.addAddress(addr);   // → externalEaddress at index 5

const { handles, inputProof } = await buf.encrypt();

// Pass them in the order the contract expects (NOT necessarily index order)
await contract.deposit(handles[2], inputProof);
```

Notes:
- The **proof is per `encrypt()` call** — all handles in that batch share one proof.
- The proof binds **(contractAddr, userAddr)** — calling another contract or signing as another user fails verification.
- `bigint` is the canonical input type for `add32`/`add64`; `number` works for small values too.

---

## 4. User-decrypt (read your own private state)

The full flow lives in [`decryption.md`](./decryption.md#1-user-decryption-eip-712). One-shot helper for a single value:

```ts
async function userDecryptOne(
    fhevm, signer, handle, contractAddr,
) {
    const userAddr = await signer.getAddress();
    const kp = fhevm.generateKeypair();
    const start = Math.floor(Date.now() / 1000).toString();
    const days  = "10";
    const ctx   = [contractAddr];

    const eip712 = fhevm.createEIP712(kp.publicKey, ctx, start, days);
    const sig    = await signer.signTypedData(
        eip712.domain,
        { UserDecryptRequestVerification: eip712.types.UserDecryptRequestVerification },
        eip712.message,
    );

    const result = await fhevm.userDecrypt(
        [{ handle, contractAddress: contractAddr }],
        kp.privateKey, kp.publicKey,
        sig.replace("0x", ""),
        ctx, userAddr, start, days,
    );
    return result[handle];   // bigint | boolean | string (for eaddress)
}
```

Reuse the signature within the validity window for many handles — only sign once.

---

## 5. Public-decrypt (read globally revealed state)

```ts
const handle = await contract.publicResult();
const result = await fhevm.publicDecrypt([handle]);
console.log(result[handle]);
```

`publicDecrypt` works only after the contract has called `FHE.makePubliclyDecryptable(handle)`. Without that, the relayer rejects.

---

## 6. React hook template

```tsx
// useFhevm.ts
import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/bundle";
import { useEffect, useState } from "react";

let cached: Awaited<ReturnType<typeof createInstance>> | null = null;

export function useFhevm() {
    const [fhevm, setFhevm] = useState(cached);
    useEffect(() => {
        if (cached) return;
        (async () => {
            const inst = await createInstance({ ...SepoliaConfig, network: window.ethereum });
            cached = inst;
            setFhevm(inst);
        })();
    }, []);
    return fhevm;
}
```

```tsx
// PrivateBalance.tsx
const fhevm = useFhevm();
const { data: handle } = useReadContract({ /* … */ });

const decrypt = async () => {
    if (!fhevm || !handle) return;
    const plain = await userDecryptOne(fhevm, signer, handle, CONTRACT);
    setBalance(plain);
};
```

---

## 7. Bundling gotchas

### Vite

```ts
// vite.config.ts
export default defineConfig({
    optimizeDeps: { exclude: ["@zama-fhe/relayer-sdk"] },
    define: { global: "globalThis" },
});
```

The SDK uses some Node-style globals — defining `global` avoids `global is not defined` in dev.

### Next.js (app router)

Mark any component using the SDK with `"use client"`. Server components can't use the browser bundle.

```tsx
"use client";
import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/bundle";
```

### Webpack 5

Add fallbacks:

```js
resolve: {
    fallback: {
        crypto: require.resolve("crypto-browserify"),
        stream: require.resolve("stream-browserify"),
        buffer: require.resolve("buffer/"),
    },
},
```

---

## 8. Error handling

| Error | Cause | Fix |
|---|---|---|
| `Failed to fetch KMS public key` | Wrong network in `createInstance` | Use the network's official config object |
| `Input proof: signer mismatch` | `userAddr` passed to `createEncryptedInput` ≠ tx signer | Pass `await signer.getAddress()` |
| `User decrypt: unauthorized` | Contract didn't `FHE.allow(handle, user)` | Add the allow on the producing tx |
| `Public decrypt: not allowed` | Contract didn't `FHE.makePubliclyDecryptable` | Mark the handle on-chain first |
| `Invalid handle format` | Passed a `BigNumber` instead of `bytes32` hex | Use the raw on-chain return value |

---

## 9. End-to-end browser flow (single file)

See [`examples/frontend.ts`](./examples/frontend.ts) for a complete, runnable browser script that connects MetaMask → encrypts a deposit → submits the tx → decrypts the resulting balance.
