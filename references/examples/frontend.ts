import { BrowserProvider, Contract } from "ethers";
import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/bundle";

const CONTRACT = "0xYourCounterAddress";
const ABI = [
    "function set(bytes32,bytes) external",
    "function increment(bytes32,bytes) external",
    "function getCount() view returns (bytes32)",
];

export async function depositAndRead() {
    const provider = new BrowserProvider((window as any).ethereum);
    const signer   = await provider.getSigner();
    const userAddr = await signer.getAddress();

    const fhevm = await createInstance({ ...SepoliaConfig, network: (window as any).ethereum });

    const buf = fhevm.createEncryptedInput(CONTRACT, userAddr);
    buf.add32(123);
    const { handles, inputProof } = await buf.encrypt();

    const counter = new Contract(CONTRACT, ABI, signer);
    const tx = await counter.set(handles[0], inputProof);
    await tx.wait();

    const handle = await counter.getCount();

    const kp = fhevm.generateKeypair();
    const start = Math.floor(Date.now() / 1000).toString();
    const days  = "10";
    const eip712 = fhevm.createEIP712(kp.publicKey, [CONTRACT], start, days);
    const sig = await signer.signTypedData(
        eip712.domain,
        { UserDecryptRequestVerification: eip712.types.UserDecryptRequestVerification },
        eip712.message,
    );

    const result = await fhevm.userDecrypt(
        [{ handle, contractAddress: CONTRACT }],
        kp.privateKey, kp.publicKey,
        sig.replace("0x", ""),
        [CONTRACT], userAddr, start, days,
    );
    return result[handle];
}
