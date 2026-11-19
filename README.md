# AgentFair — Fair Drops for Agent ID Holders

**Agent ID Hackathon (Binance Wallet × BNB Chain) — submission project**
Submission period: 2026-11-18 08:00 UTC → 2026-12-09 08:00 UTC (15:00 WIB)

## The problem

Fair launches get farmed. One person with 500 wallets takes 500 "one-per-person"
slots, and real users get nothing. Projects have no cheap, on-chain way to say
"one human, one slot" — KYC is heavy, allowlist spreadsheets are manual and
gameable.

## The solution

An **Agent ID is one-per-user and non-transferable** (SPACE ID Agent ID,
ERC-721, BNB Chain `0x60b9262456de011f7d15a54cdd8c48baaa8b022f`). AgentFair uses
it as a sybil-resistance primitive:

- **Register** — only Agent ID holders can register (contract checks
  `balanceOf(msg.sender) > 0` on the Agent ID contract on every action).
  Each registration gets a sequential Agent Number.
- **Daily check-in** — registered agents check in once per UTC day to build a
  streak and earn AgentFair Points (a non-transferable on-chain score with
  **no monetary value** — reputation only).
- **Fair Drops** — any registered agent can create a Drop: a fixed number of
  claim slots with a start/end window (e.g. an allowlist for an NFT mint, a
  testnet seat, a community allocation).
- **Claim — 1 Agent ID = 1 claim.** Because an Agent ID cannot be transferred
  or duplicated, one claim per address is finally one claim per *person*.
  First-come-first-served until slots run out, enforced on-chain.

Drop creators get a verifiable, sybil-resistant claimant list (emitted as
events + readable on-chain) they can honor in their own launch — no
spreadsheets, no bots.

## Why Agent ID is core, not decoration

Every state-changing function (`register`, `checkIn`, `createDrop`, `claim`)
re-checks Agent ID ownership against the official SPACE ID contract. Remove
Agent ID and the product cannot function: registration, reputation and fair
claims are all built on it. Depth of integration is the design, not a gate
bolted on the side.

## Safety by design (hackathon red lines)

- The contract **holds no funds**: no payable functions, no token transfers,
  no approvals, nothing to drain.
- **No owner, no admin, no pause, no upgrade.** Deployed immutable; the only
  privileged action is a Drop creator cancelling *their own* Drop.
- No QR-code wallet login, no session handling, no credential collection —
  the dApp is a static page; users connect their own wallet and confirm every
  transaction themselves.
- No promise of returns. Points are a reputation score only. Project and
  token names do not use "Binance"/"BNB" branding.
- Agent ID is never used to look up other people's wallets by name; the
  contract only checks the *caller's own* holding.

## Contracts

| Contract | Purpose |
|---|---|
| `contracts/AgentFair.sol` | The product. Immutable, no admin, no funds. |
| `contracts/mocks/MockAgentID.sol` | Test double for the Agent ID registry (local + testnet testing only; never used on mainnet). |

Mainnet deployment uses the real Agent ID registry:
`0x60b9262456de011f7d15a54cdd8c48baaa8b022f`.

## Deployment (BNB Chain mainnet)

| | |
|---|---|
| Contract | `0xE7C3a3ac6107421C073adC4603184166D908Ae5f` |
| Deployer | `0x25E955d5237D60026b2e5fC5239ACe8c7138B32E` (funded 0.0005 BNB from the deelee.ai Agentic Wallet, tx `0x25c79dfa764977ebff2fe16a7a494a799f524babc106544feade219cfc9bd366`) |
| Deploy tx | `0x91c2bb7ba856e372f004a64754a70125e7d7d4a6ba8a942435a1a52898163a34` |
| Deploy cost | 0.0000675301 BNB |
| Registry wired | `agentID()` → `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` (verified on-chain) |
| Source verification | Sourcify **exact_match** (creation + runtime) and BscScan **Source Code Verified — Exact Match**, 2026-11-19 |

## Build & test

```bash
export PATH=~/workspace/tools/foundry-bin:$PATH   # or any Foundry install
forge build
forge test -vv
```

## Roadmap during the submission window

1. Deploy on BNB Chain testnet with MockAgentID, end-to-end test with a real
   Agentic Wallet flow.
2. Deploy on BNB Chain mainnet against the real Agent ID registry, verify
   source on BscScan, publish this repo.
3. Launch the static dApp (GitHub Pages), seed the first Drops, and invite
   Agent ID holders to register + claim (target: 30+ unique Agent ID
   interactors for the Innovation Award, then grow for the Pioneer Award).
