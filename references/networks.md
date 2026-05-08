# Network Reference

The Zama Protocol ships network-specific config contracts. Inherit the right one for the chain you're deploying to.

---

## Supported networks

| Network | Chain ID | Config import | Status |
|---|---|---|---|
| Sepolia (testnet) | 11155111 | `SepoliaConfig` from `@fhevm/solidity/config/ZamaConfig.sol` | ✅ live, primary dev target |
| Hardhat local (mock) | 31337 | injected by `@fhevm/hardhat-plugin` | ✅ for tests |
| Mainnet | 1 | `MainnetConfig` (when released) | 🚧 follow Zama announcements |

---

## Inheritance pattern

```solidity
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract MyContract is SepoliaConfig {
    // FHE precompile addresses + ACL contract + KMS verifier
    // are wired into the inherited storage layout.
}
```

Without inheritance, `FHE.*` calls fail because the precompile addresses default to zero.

---

## Multi-chain deployment

If your contract should compile cleanly across chains, accept the config externally:

```solidity
abstract contract FHEConfig {
    function _initFHE() internal virtual;
}

contract Production is SepoliaConfig {
    // inherits all FHE wiring
}
```

For cross-chain consistency, prefer one network per deployment rather than chain-detection logic.

---

## Hardhat config (default = Sepolia testnet, public RPC baked in)

```ts
import "@fhevm/hardhat-plugin";
import * as dotenv from "dotenv";
dotenv.config();

const SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL ?? "https://rpc2.sepolia.org";
const MAINNET_RPC_URL = process.env.MAINNET_RPC_URL ?? "https://eth.drpc.org";
const PRIVATE_KEY     = process.env.PRIVATE_KEY;

export default {
    solidity: { version: "0.8.27", settings: { optimizer: { enabled: true, runs: 800 } } },
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
```

**Default behaviour**: tasks like `npx hardhat deploy` without `--network` hit Sepolia. Mainnet requires explicit `--network mainnet` and a funded `PRIVATE_KEY`.

Backup public Sepolia RPCs (rotate if rate-limited):
- `https://rpc2.sepolia.org` (default)
- `https://ethereum-sepolia.publicnode.com`
- `https://eth-sepolia.public.blastapi.io`

---

## Frontend network config

```ts
import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/bundle";

const fhevm = await createInstance({
    ...SepoliaConfig,
    network: window.ethereum,   // EIP-1193 provider
});
```

The SDK's `SepoliaConfig` bundles:
- KMS public key URL
- Gateway / relayer URL
- ACL contract address
- Decryption oracle address
- Chain ID

Mainnet equivalents will follow once Zama Protocol mainnet launches.

---

## Faucets

- Sepolia ETH: https://sepoliafaucet.com / https://www.alchemy.com/faucets/ethereum-sepolia
- Sepolia LINK / USDC etc.: chain-specific faucets

You need ETH for gas. FHE coprocessor fees are paid in ETH on Sepolia.

---

## RPC providers

**Default (no key, no setup):**
- Sepolia: `https://rpc2.sepolia.org`
- Mainnet: `https://eth.drpc.org`

Backup public endpoints:
- `https://ethereum-sepolia.publicnode.com`
- `https://eth-sepolia.public.blastapi.io`

**Keyed (faster, higher rate limit) — recommended for production:**
- Infura (`https://sepolia.infura.io/v3/<KEY>`)
- Alchemy (`https://eth-sepolia.g.alchemy.com/v2/<KEY>`)
- QuickNode

Public RPCs are fine for tests + small demos. Heavy traffic (CI, frontend production) → switch to a keyed endpoint via `SEPOLIA_RPC_URL` in `.env`.

---

## Block explorer

Sepolia: https://sepolia.etherscan.io

Verified FHEVM contracts show the FHE precompile calls as part of the inherited bytecode — verification works normally with `npx hardhat verify`.

---

## Coprocessor health

Check the Zama status page if your `requestDecryption` callbacks aren't arriving. Network-wide outages occasionally pause oracle delivery; transactions don't revert, they just delay.
