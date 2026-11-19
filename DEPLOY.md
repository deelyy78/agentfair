# Deploy guide — AgentFair

> On-chain safety: deployer key NEVER goes through chat. Create it locally,
> keep it in a 0600 file, fund it with a small amount of BNB, and confirm the
> one-line summary (chain · from · to · asset · amount · fee) before the first
> broadcast of the session.

## 0. Prereqs

```bash
export PATH=~/workspace/tools/foundry-bin:$PATH
cd ~/workspace/agentfair-hackathon
forge build && forge test
```

Deployer wallet (fresh, dedicated):

```bash
cast wallet new   # save the output yourself into deployer.txt (chmod 600) — do NOT paste it in chat
```

## 1. BNB Chain testnet (chainId 97) — rehearsal with MockAgentID

RPC: `https://data-seed-prebsc-1-s1.binance.org:8545`
Faucet: https://www.bnbchain.org/en/testnet-faucet (0.3 tBNB/day is plenty)

```bash
RPC=https://data-seed-prebsc-1-s1.binance.org:8545
MOCK=$(forge create contracts/mocks/MockAgentID.sol:MockAgentID --rpc-url $RPC --private-key $DEPLOYER_PK --json | jq -r .deployedTo)
FAIR=$(forge create contracts/AgentFair.sol:AgentFair --constructor-args $MOCK --rpc-url $RPC --private-key $DEPLOYER_PK --json | jq -r .deployedTo)
cast send $MOCK "mint(address)" <HOLDER_ADDRESS> --rpc-url $RPC --private-key $DEPLOYER_PK
```

Then point `docs/index.html` at the testnet contract + testnet RPC/chain
in a scratch copy and run the full flow: register → check-in → createDrop →
claim (holder) + a non-holder control that must revert.

## 2. BNB Chain mainnet (chainId 56)

Registry (real Agent ID): `0x60b9262456de011f7d15a54cdd8c48baaa8b022f`
RPC: `https://bsc.publicnode.com`

```bash
RPC=https://bsc.publicnode.com
FAIR=$(forge create contracts/AgentFair.sol:AgentFair \
  --constructor-args 0x60b9262456de011f7d15a54cdd8c48baaa8b022f \
  --rpc-url $RPC --private-key $DEPLOYER_PK \
  --verify --etherscan-api-key $BSCSCAN_API_KEY --json | jq -r .deployedTo)
```

Sanity checks right after deploy (read-only):

```bash
cast call $FAIR "agentID()(address)" --rpc-url $RPC          # must be the registry
cast call $FAIR "isAgentHolder(address)(bool)" 0x9d3A4B1f0DE62089832DB9F755f2033B14C58e37 --rpc-url $RPC  # deelee.ai wallet -> true
cast call $FAIR "isAgentHolder(address)(bool)" 0x75c1e73eb5dbd97e66093d9dffc8ca77eae2cb70 --rpc-url $RPC  # external wallet -> false
```

Then:
1. Put `$FAIR` into `docs/index.html` (`AGENTFAIR`), commit, publish repo
   (GitHub, public) + GitHub Pages for `docs/`.
2. First interactions from the deelee.ai Agentic Wallet via `baw contract-call`
   (explicit `--gasLimit 800000` on previews): `register()`, `checkIn()`,
   create the Genesis Drop.
3. Submit the project (name, website, contract address, Agent ID usage
   description) via the hackathon submission route in the Binance
   announcement, before **2026-12-09 08:00 UTC**.
4. Community campaign: X post with #BinanceWalletHackathon #AgenticWallet +
   submit the X link via the official campaign survey (2,000 USDC pool,
   20 winners).
