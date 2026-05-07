import { expect } from "chai";
import { ethers, fhevm } from "hardhat";
import { FhevmType } from "@fhevm/hardhat-plugin";

describe("ConfidentialVoting", () => {
    let voting: any, alice: any, bob: any, carol: any, addr: string;

    beforeEach(async () => {
        [alice, bob, carol] = await ethers.getSigners();
        voting = await ethers.deployContract("ConfidentialVoting");
        addr = await voting.getAddress();
        await fhevm.assertCoprocessorInitialized(voting, "ConfidentialVoting");
    });

    async function castVote(signer: any, proposalId: number, choice: number) {
        const e = await fhevm
            .createEncryptedInput(addr, signer.address)
            .add8(choice)
            .encrypt();
        return voting.connect(signer).vote(proposalId, e.handles[0], e.inputProof);
    }

    it("counts votes correctly", async () => {
        const tx = await voting.createProposal("Add green button", 3600);
        await tx.wait();

        await castVote(alice, 1, 1);
        await castVote(bob,   1, 1);
        await castVote(carol, 1, 0);

        await ethers.provider.send("evm_increaseTime", [3700]);
        await ethers.provider.send("evm_mine", []);

        await voting.requestFinalization(1);
        await fhevm.awaitDecryptionOracle();

        const p = await voting.proposals(1);
        expect(p.finalized).to.equal(true);
        expect(p.yesPlain).to.equal(2);
        expect(p.noPlain).to.equal(1);
    });

    it("prevents double voting", async () => {
        await voting.createProposal("Test", 3600);
        await castVote(alice, 1, 1);
        await expect(castVote(alice, 1, 0)).to.be.revertedWith("already voted");
    });

    it("rejects votes after end time", async () => {
        await voting.createProposal("Test", 60);
        await ethers.provider.send("evm_increaseTime", [120]);
        await ethers.provider.send("evm_mine", []);
        await expect(castVote(alice, 1, 1)).to.be.revertedWith("voting closed");
    });
});
