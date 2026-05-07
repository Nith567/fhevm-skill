import { expect } from "chai";
import { ethers, fhevm } from "hardhat";
import { FhevmType } from "@fhevm/hardhat-plugin";

describe("ConfidentialCounter", () => {
    let counter: any;
    let alice: any, bob: any;
    let addr: string;

    beforeEach(async () => {
        [alice, bob] = await ethers.getSigners();
        counter = await ethers.deployContract("ConfidentialCounter");
        addr = await counter.getAddress();
        await fhevm.assertCoprocessorInitialized(counter, "ConfidentialCounter");
    });

    async function encryptU32(signer: any, n: number) {
        return fhevm.createEncryptedInput(addr, signer.address).add32(n).encrypt();
    }

    async function readCount(signer: any) {
        const handle = await counter.getCount();
        return fhevm.userDecryptEuint(FhevmType.euint32, handle, addr, signer);
    }

    it("set and read", async () => {
        const e = await encryptU32(alice, 42);
        await counter.connect(alice).set(e.handles[0], e.inputProof);
        expect(await readCount(alice)).to.equal(42n);
    });

    it("increment", async () => {
        const a = await encryptU32(alice, 10);
        await counter.connect(alice).set(a.handles[0], a.inputProof);

        const b = await encryptU32(alice, 5);
        await counter.connect(alice).increment(b.handles[0], b.inputProof);

        expect(await readCount(alice)).to.equal(15n);
    });

    it("decrement wraps (no overflow revert)", async () => {
        const a = await encryptU32(alice, 1);
        await counter.connect(alice).set(a.handles[0], a.inputProof);

        const b = await encryptU32(alice, 5);
        await counter.connect(alice).decrement(b.handles[0], b.inputProof);

        expect(await readCount(alice)).to.equal((1n << 32n) - 4n);
    });

    it("rejects bob's input proof for alice's tx", async () => {
        const e = await encryptU32(bob, 7);
        await expect(
            counter.connect(alice).set(e.handles[0], e.inputProof)
        ).to.be.reverted;
    });

    it("only the granted user can decrypt", async () => {
        const e = await encryptU32(alice, 99);
        await counter.connect(alice).set(e.handles[0], e.inputProof);
        const handle = await counter.getCount();
        await expect(
            fhevm.userDecryptEuint(FhevmType.euint32, handle, addr, bob)
        ).to.be.rejected;
    });
});
