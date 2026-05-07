import { expect } from "chai";
import { ethers, fhevm } from "hardhat";
import { FhevmType } from "@fhevm/hardhat-plugin";

describe("EncryptedERC20", () => {
    let token: any, owner: any, alice: any, bob: any, addr: string;

    beforeEach(async () => {
        [owner, alice, bob] = await ethers.getSigners();
        token = await ethers.deployContract("EncryptedERC20", ["Confidential USD", "cUSD"]);
        addr = await token.getAddress();
        await fhevm.assertCoprocessorInitialized(token, "EncryptedERC20");
    });

    async function balOf(signer: any, account: any) {
        const handle = await token.balanceOf(account.address);
        return fhevm.userDecryptEuint(FhevmType.euint64, handle, addr, signer);
    }

    async function encU64(signer: any, n: bigint) {
        return fhevm.createEncryptedInput(addr, signer.address).add64(n).encrypt();
    }

    it("mints", async () => {
        await token.mint(alice.address, 1000n);
        expect(await balOf(alice, alice)).to.equal(1000n);
    });

    it("transfers", async () => {
        await token.mint(alice.address, 1000n);
        const e = await encU64(alice, 300n);
        await token.connect(alice).transfer(bob.address, e.handles[0], e.inputProof);
        expect(await balOf(alice, alice)).to.equal(700n);
        expect(await balOf(bob, bob)).to.equal(300n);
    });

    it("transfer over balance silently caps at balance", async () => {
        await token.mint(alice.address, 100n);
        const e = await encU64(alice, 500n);
        await token.connect(alice).transfer(bob.address, e.handles[0], e.inputProof);
        expect(await balOf(alice, alice)).to.equal(100n);
        expect(await balOf(bob, bob)).to.equal(0n);
    });

    it("approve + transferFrom", async () => {
        await token.mint(alice.address, 1000n);
        const a = await encU64(alice, 200n);
        await token.connect(alice).approve(bob.address, a.handles[0], a.inputProof);

        const t = await encU64(bob, 150n);
        await token.connect(bob).transferFrom(
            alice.address, bob.address, t.handles[0], t.inputProof
        );

        expect(await balOf(alice, alice)).to.equal(850n);
        expect(await balOf(bob, bob)).to.equal(150n);
    });

    it("rejects bob decrypting alice's balance", async () => {
        await token.mint(alice.address, 100n);
        const handle = await token.balanceOf(alice.address);
        await expect(
            fhevm.userDecryptEuint(FhevmType.euint64, handle, addr, bob)
        ).to.be.rejected;
    });
});
