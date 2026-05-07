# Quickstart — Zero to Confidential dApp in 10 Minutes

A copy-paste path from empty directory to a deployed confidential contract on Sepolia, with frontend.

---

## 0. Prereqs

- Node 20+
- (Optional) A funded Sepolia wallet for live deploy — mock tests need nothing

---

## 1. Bootstrap

```bash
git clone https://github.com/zama-ai/fhevm-hardhat-template my-fhe-app
cd my-fhe-app
npm install
```

That's it. **Default network is Sepolia testnet** with a public RPC baked in — no `.env` needed for mock tests.

**For Sepolia live deploy** (or mainnet later), create `.env`:
```
PRIVATE_KEY=0xyourtestkey...

SEPOLIA_RPC_URL=https://rpc2.sepolia.org

MAINNET_RPC_URL=https://eth.drpc.org
```

---

## 2. Replace the sample contract

Create `contracts/ConfidentialCounter.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, euint32, externalEuint32} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract ConfidentialCounter is SepoliaConfig {
    euint32 private _count;

    function increment(externalEuint32 enc, bytes calldata proof) external {
        euint32 delta = FHE.fromExternal(enc, proof);
        _count = FHE.add(_count, delta);
        FHE.allowThis(_count);
        FHE.allow(_count, msg.sender);
    }

    function getCount() external view returns (euint32) {
        return _count;
    }
}
```

---

## 3. Compile + test (mock mode, instant)

```bash
npx hardhat compile
```

Create `test/ConfidentialCounter.test.ts`:

```typescript
import { expect } from "chai";
import { ethers, fhevm } from "hardhat";
import { FhevmType } from "@fhevm/hardhat-plugin";

describe("ConfidentialCounter", () => {
    it("increments", async () => {
        const [alice] = await ethers.getSigners();
        const counter = await ethers.deployContract("ConfidentialCounter");
        const addr = await counter.getAddress();

        const enc = await fhevm
            .createEncryptedInput(addr, alice.address)
            .add32(7)
            .encrypt();

        await counter.connect(alice).increment(enc.handles[0], enc.inputProof);

        const handle = await counter.getCount();
        const plain = await fhevm.userDecryptEuint(
            FhevmType.euint32, handle, addr, alice
        );
        expect(plain).to.equal(7n);
    });
});
```

```bash
npx hardhat test
```

✅ If green: you have a working FHEVM dev loop.

---

## 4. Deploy to Sepolia

Create `deploy/01_counter.ts`:

```typescript
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const fn: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { deployer } = await hre.getNamedAccounts();
    await hre.deployments.deploy("ConfidentialCounter", {
        from: deployer,
        log: true,
    });
};
export default fn;
fn.tags = ["counter"];
```

```bash
npx hardhat --network sepolia deploy --tags counter
```

Note the deployed address.

---

## 5. Frontend (vite + ethers + relayer SDK)

```bash
mkdir frontend && cd frontend
npm create vite@latest . -- --template react-ts
npm install
npm install ethers @zama-fhe/relayer-sdk
```

`vite.config.ts`:
```typescript
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
export default defineConfig({
    plugins: [react()],
    optimizeDeps: { exclude: ["@zama-fhe/relayer-sdk"] },
    define: { global: "globalThis" },
});
```

Replace `src/App.tsx`:

```tsx
import { useState } from "react";
import { BrowserProvider, Contract } from "ethers";
import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/bundle";

const ADDR = "0xYourDeployedAddress";
const ABI = [
    "function increment(bytes32 enc, bytes proof) external",
    "function getCount() view returns (bytes32)",
];

export default function App() {
    const [count, setCount] = useState<bigint | null>(null);

    async function increment() {
        const provider = new BrowserProvider((window as any).ethereum);
        const signer = await provider.getSigner();
        const user = await signer.getAddress();
        const fhevm = await createInstance({
            ...SepoliaConfig,
            network: (window as any).ethereum,
        });

        const buf = fhevm.createEncryptedInput(ADDR, user);
        buf.add32(1);
        const { handles, inputProof } = await buf.encrypt();

        const counter = new Contract(ADDR, ABI, signer);
        const tx = await counter.increment(handles[0], inputProof);
        await tx.wait();

        const handle = await counter.getCount();
        const kp = fhevm.generateKeypair();
        const start = Math.floor(Date.now() / 1000).toString();
        const days = "10";
        const eip712 = fhevm.createEIP712(kp.publicKey, [ADDR], start, days);
        const sig = await signer.signTypedData(
            eip712.domain,
            { UserDecryptRequestVerification: eip712.types.UserDecryptRequestVerification },
            eip712.message
        );
        const result = await fhevm.userDecrypt(
            [{ handle, contractAddress: ADDR }],
            kp.privateKey, kp.publicKey,
            sig.replace("0x", ""),
            [ADDR], user, start, days
        );
        setCount(result[handle] as bigint);
    }

    return (
        <div style={{ padding: 40, fontFamily: "monospace" }}>
            <h1>Confidential Counter</h1>
            <button onClick={increment}>Increment +1 (encrypted)</button>
            <p>Your private count: {count?.toString() ?? "—"}</p>
        </div>
    );
}
```

```bash
npm run dev
```

Connect MetaMask on Sepolia, click increment, sign the EIP-712 reencryption, watch your private count update.

---

## 6. What you just built

- ✅ A contract with **encrypted state**
- ✅ Frontend that **encrypts user input** with a ZK proof
- ✅ Tx sent on-chain — the network only ever sees ciphertext + proof
- ✅ **User-decrypt** flow letting only the holder read their own count

The same primitives scale to:
- Confidential ERC-7984 tokens — `examples/ConfidentialToken.sol`
- Sealed-bid auctions — `examples/BlindAuction.sol`
- Confidential voting — `examples/ConfidentialVoting.sol`
- Encrypted DAOs — `examples/ConfidentialDAO.sol`
- Encrypted lotteries — `examples/EncryptedLottery.sol`

Pick the closest example, customize, ship.

---

## 7. Common first-time issues

| Symptom | Fix |
|---|---|
| `Coprocessor not initialized` | inherit `SepoliaConfig` |
| `ACL: contract not allowed` (next tx) | add `FHE.allowThis(handle)` after every store |
| `User decrypt: unauthorized` | add `FHE.allow(handle, msg.sender)` in producer |
| `Input proof: signer mismatch` | the address in `createEncryptedInput` must match the tx signer |
| `Cannot divide by encrypted value` | RHS of `FHE.div` must be plaintext |

Detailed catalog: [`references/anti-patterns.md`](./references/anti-patterns.md).
