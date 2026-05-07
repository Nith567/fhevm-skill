# From-scratch FHEVM Project Setup

When the official Hardhat template doesn't fit (existing repo, monorepo, custom config).

---

## Hardhat from scratch

```bash
mkdir my-fhe-app && cd my-fhe-app
npm init -y
npm i -D hardhat @nomicfoundation/hardhat-toolbox @fhevm/hardhat-plugin
npm i @fhevm/solidity @zama-fhe/relayer-sdk @openzeppelin/confidential-contracts
npx hardhat init     # pick TypeScript
```

`hardhat.config.ts` — **default network is Sepolia testnet**, public RPC baked in. Mainnet available but never default.

```ts
import "@nomicfoundation/hardhat-toolbox";
import "@fhevm/hardhat-plugin";
import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
dotenv.config();

const SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL ?? "https://rpc2.sepolia.org";
const MAINNET_RPC_URL = process.env.MAINNET_RPC_URL ?? "https://eth.drpc.org";
const PRIVATE_KEY     = process.env.PRIVATE_KEY;

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.27",
        settings: { optimizer: { enabled: true, runs: 800 } },
    },
    defaultNetwork: "sepolia",
    networks: {
        hardhat: { chainId: 31337 },
        sepolia: {
            url: SEPOLIA_RPC_URL,
            accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
            chainId: 11155111,
        },
        mainnet: {
            url: MAINNET_RPC_URL,
            accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
            chainId: 1,
        },
    },
};
export default config;
```

Backup public Sepolia RPCs: `https://ethereum-sepolia.publicnode.com`, `https://eth-sepolia.public.blastapi.io`.

`.env` (optional — only required for live deploy / live test):

```
PRIVATE_KEY=0xyourtestkey...

SEPOLIA_RPC_URL=https://rpc2.sepolia.org

MAINNET_RPC_URL=https://eth.drpc.org
```

Mock tests (`npx hardhat test`) need neither — they run in-process. Funded Sepolia ETH is needed only for live deploy (faucet: https://sepoliafaucet.com).

---

## Foundry hybrid setup

Foundry can compile FHEVM contracts but cannot run encrypted ops natively (no mock). Use Foundry for compile/static checks and Hardhat for tests:

```toml
# foundry.toml
[profile.default]
src           = "contracts"
libs          = ["node_modules"]
solc          = "0.8.27"
remappings    = [
    "@fhevm/solidity/=node_modules/@fhevm/solidity/",
    "@openzeppelin/=node_modules/@openzeppelin/",
]
```

---

## Network configs

| Network | Config import | Chain ID |
|---|---|---|
| Sepolia | `SepoliaConfig` from `@fhevm/solidity/config/ZamaConfig.sol` | 11155111 |
| Local hardhat (mock) | inherits via plugin auto-injection | — |

If a new network ships, swap the inherited config — nothing else changes.

---

## Verifying on Etherscan

Add the Etherscan plugin and run:

```bash
npx hardhat verify --network sepolia <CONTRACT_ADDR> [constructor args...]
```

The FHE precompile addresses inherited from `SepoliaConfig` are part of the bytecode; verification works normally.

---

## Recommended scripts

`package.json`:

```json
{
  "scripts": {
    "build": "hardhat compile",
    "test": "hardhat test",
    "test:sepolia": "hardhat test --network sepolia",
    "deploy": "hardhat --network sepolia run scripts/deploy.ts",
    "verify": "hardhat verify --network sepolia"
  }
}
```

---

## Folder layout (recommended)

```
my-fhe-app/
├── contracts/
│   ├── ConfidentialCounter.sol
│   └── …
├── test/
│   └── ConfidentialCounter.test.ts
├── scripts/
│   └── deploy.ts
├── frontend/        (optional Next.js / Vite app)
├── hardhat.config.ts
└── .env
```
