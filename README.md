# Zama FHEVM Skill

Production-ready **AI agent skill** for the [Zama Protocol](https://docs.zama.org/protocol) — Fully Homomorphic Encryption on Ethereum.

Drop this into your AI coding environment (Claude Code, Cursor, Windsurf, OpenClaw…) and your agent gains full knowledge of FHEVM: encrypted types, FHE operations, ACL, input proofs, user/public/oracle decryption, the Hardhat template, the relayer SDK, OpenZeppelin Confidential Contracts (ERC-7984), testing patterns, and the long list of anti-patterns that turn a "compiles fine" contract into a runtime brick.

> **Bounty submission** — Zama Season Bounty Track. Built so an AI agent goes *prompt → working confidential dApp* with zero hand-holding.

---

## What this skill teaches the agent

- ✅ FHEVM architecture (handles, coprocessor, KMS, gateway/relayer)
- ✅ Hardhat template setup (`@fhevm/hardhat-plugin`)
- ✅ Encrypted types: `ebool`, `euint8/16/32/64/128/256`, `eaddress`
- ✅ FHE operations: arithmetic, comparison, bitwise, `FHE.select` conditional logic
- ✅ Access control: `FHE.allow`, `FHE.allowThis`, `FHE.allowTransient`, `FHE.makePubliclyDecryptable`
- ✅ Input proofs (`externalEuint*` + `FHE.fromExternal`) and the ZK proof of knowledge
- ✅ User decryption — EIP-712 signing flow with the KMS
- ✅ Public decryption — globally revealed values
- ✅ Oracle async decryption — `FHE.requestDecryption` + callback + `FHE.checkSignatures`
- ✅ Frontend integration — `@zama-fhe/relayer-sdk` (the modern fhevmjs)
- ✅ Testing FHEVM contracts — mock + Sepolia mode
- ✅ ERC-7984 confidential tokens + ERC-20 wrapping
- ✅ A catalogue of anti-patterns and how to fix each one

---

## Install

```bash
npx -y skills add Nith567/fhevm-skill
```

---

## Try it

After installing, prompt the agent:

```
"Write me a confidential voting contract using FHEVM where each vote is
 encrypted, the tally is computed on encrypted ballots, and only the
 final winner is revealed publicly."
```

```
"Build a confidential ERC-7984 stablecoin called cUSD with an ERC-20
 wrapper around USDC on Sepolia."
```

```
"My FHEVM contract reverts with 'ACL: not allowed' on the second tx.
 Help me debug."
```

The skill activates automatically on any FHE / FHEVM / Zama / encrypted-contract phrasing.

---

## Repository layout

```
fhevm-skill/
├── SKILL.md                            ← entry point loaded by the agent
├── README.md                           ← this file
├── QUICKSTART.md                       ← 0 → deployed dApp in 10 minutes
└── references/
    ├── core.md                         ← full API + AI checklist + debug guide
    ├── decryption.md                   ← user / public / oracle async flows
    ├── frontend.md                     ← @zama-fhe/relayer-sdk deep-dive
    ├── testing.md                      ← Hardhat: mock + Sepolia + flush oracle
    ├── erc7984.md                      ← OpenZeppelin Confidential Contracts
    ├── anti-patterns.md                ← 15-entry catalog of mistakes
    ├── patterns.md                     ← 20 composable patterns (cookbook)
    ├── security.md                     ← threat model + audit checklist
    ├── gas-optimization.md             ← cost classes + top wins
    ├── networks.md                     ← network configs + RPC + faucets
    ├── agent-workflow.md               ← 10-step agent playbook
    ├── setup.md                        ← from-scratch project setup
    └── examples/
        ├── ConfidentialCounter.sol     ← store/increment template (+ tests, deploy)
        ├── BlindAuction.sol            ← minimal sealed-bid + oracle reveal
        ├── SealedBidAuction.sol        ← full NFT auction with deposits/refunds
        ├── ConfidentialVoting.sol      ← encrypted voting + tally (+ tests)
        ├── ConfidentialToken.sol       ← ERC-7984 + ERC-20 wrapper
        ├── EncryptedERC20.sol          ← custom encrypted ERC-20 from scratch (+ tests)
        ├── EncryptedLottery.sol        ← FHE.randEuint + oracle reveal
        ├── ConfidentialPayroll.sol     ← multi-employee encrypted payouts
        ├── EncryptedIdentity.sol       ← selective-disclosure identity proofs
        └── frontend.ts                 ← end-to-end browser flow
```

**~5,000 lines of skill content. ~10 example contracts. ~3,000 lines of working Solidity + TypeScript.**

---

## How it's structured (skill design notes)

- **`SKILL.md` is the index** — loaded once into the agent's context. It covers the critical rules, decision tree, and short worked examples.
- **`references/*.md` are loaded on demand** — when the agent hits a specific question (decryption flow, ERC-7984 surface, anti-pattern lookup) it pulls only what it needs. Keeps context budget tight.
- **`references/examples/*` are working drop-in templates** — the agent uses these as starting points and customises rather than writing from scratch (faster + fewer mistakes).
- **Critical Rules section in `SKILL.md`** is intentionally redundant with the anti-patterns reference. Repetition prevents the agent forgetting `FHE.allowThis` mid-edit on long sessions.

---

## License

MIT.

---

## Author

Built by **Nith567** for the Zama Season Bounty Track.

