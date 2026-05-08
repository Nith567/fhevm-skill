# Testing FHEVM Contracts

`@fhevm/hardhat-plugin` ships an in-process FHE coprocessor mock. Tests run instantly without hitting Sepolia.

---

## Setup

```ts
// hardhat.config.ts
import "@fhevm/hardhat-plugin";
import "@nomicfoundation/hardhat-toolbox";

export default {
    solidity: { version: "0.8.27", settings: { optimizer: { enabled: true, runs: 800 } } },
    networks: {
        hardhat: {},
        sepolia: { url: process.env.SEPOLIA_RPC_URL!, accounts: [process.env.PRIVATE_KEY!] },
    },
};
```

Run modes:

```bash
npx hardhat test                     # mock, instant
npx hardhat test --network sepolia   # real coprocessor, slow but truthful
```

---

## Anatomy of a test

```ts
import { expect } from "chai";
import { ethers, fhevm } from "hardhat";
import { FhevmType } from "@fhevm/hardhat-plugin";

describe("ConfidentialCounter", () => {
    let counter: any, alice: any, bob: any;

    beforeEach(async () => {
        [alice, bob] = await ethers.getSigners();
        counter = await ethers.deployContract("ConfidentialCounter");
        await fhevm.assertCoprocessorInitialized(counter, "ConfidentialCounter");
    });

    it("increments by an encrypted value", async () => {
        const enc = await fhevm
            .createEncryptedInput(await counter.getAddress(), alice.address)
            .add32(7)
            .encrypt();

        await counter.connect(alice).increment(enc.handles[0], enc.inputProof);

        const handle = await counter.getCount();
        const plain  = await fhevm.userDecryptEuint(
            FhevmType.euint32, handle, await counter.getAddress(), alice
        );
        expect(plain).to.equal(7n);
    });
});
```

---

## Public decrypt assertion

```ts
await counter.reveal();
const handle = await counter.getCount();
const plain = await fhevm.publicDecryptEuint(FhevmType.euint32, handle);
expect(plain).to.equal(42n);
```

---

## Oracle async decryption

In mock mode, manually flush the oracle:

```ts
await contract.requestReveal();
await fhevm.awaitDecryptionOracle();
expect(await contract.revealed()).to.equal(42n);
```

In Sepolia mode the callback arrives in real time. Poll the resulting state:

```ts
await contract.requestReveal();
await new Promise(r => setTimeout(r, 60_000));
expect(await contract.revealed()).to.equal(42n);
```

---

## ACL assertions

```ts
const handle = await counter.getCount();
expect(await fhevm.isAllowed(handle, alice.address)).to.equal(true);
expect(await fhevm.isAllowed(handle, bob.address)).to.equal(false);
```

---

## Multi-user scenarios

Each user must build their own input proof:

```ts
const aEnc = await fhevm.createEncryptedInput(addr, alice.address).add64(100n).encrypt();
const bEnc = await fhevm.createEncryptedInput(addr, bob.address).add64(200n).encrypt();

await contract.connect(alice).deposit(aEnc.handles[0], aEnc.inputProof);
await contract.connect(bob).deposit(bEnc.handles[0], bEnc.inputProof);
```

Trying to use Alice's proof with Bob's signer reverts at `FHE.fromExternal`.

---

## Fuzzing

Stay inside the encrypted type's range and avoid wraparound surprises:

```ts
it("fuzz add", async () => {
    const a = BigInt(Math.floor(Math.random() * 1e6));
    const b = BigInt(Math.floor(Math.random() * 1e6));
    const enc = await fhevm
        .createEncryptedInput(addr, alice.address)
        .add64(a).add64(b).encrypt();
    await contract.add(enc.handles[0], enc.handles[1], enc.inputProof);
    const result = await fhevm.userDecryptEuint(
        FhevmType.euint64, await contract.result(), addr, alice
    );
    expect(result).to.equal(a + b);
});
```

For Foundry-style invariant testing on encrypted state, decrypt sentinel handles in the property check.

---

## Common test failures

| Symptom | Cause | Fix |
|---|---|---|
| `assertCoprocessorInitialized` reverts | contract missing `is SepoliaConfig` | inherit the config |
| `userDecryptEuint` returns 0n | ACL missing for signer | add `FHE.allow(h, user)` in producer |
| Test hangs in mock mode after `requestDecryption` | forgot `await fhevm.awaitDecryptionOracle()` | add the flush |
| `revert: Input proof: signer mismatch` | wrong signer in `createEncryptedInput` | pass the same address used by `connect()` |
| `revert: ACL: contract not allowed` (next call) | missing `FHE.allowThis` after a write | add it after every state assignment |
