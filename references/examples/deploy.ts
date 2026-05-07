import { ethers } from "hardhat";

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deployer:", deployer.address);

    const counter = await ethers.deployContract("ConfidentialCounter");
    await counter.waitForDeployment();
    console.log("ConfidentialCounter:", await counter.getAddress());
}

main().catch((e) => { console.error(e); process.exit(1); });
