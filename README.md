# Roxy - Bitcoin L2 Gaming & Prediction SDK

## Overview

Roxy is a decentralized gaming SDK built on Bitcoin Layer 2 (Stacks) that enables game developers to integrate **prediction markets**, **staking**, and **cross-game identity** directly into their gameplay loop. 

Unlike traditional prediction markets that are standalone apps, Roxy brings the market *to the game*. Players can stake on their own matches, compete in high-stakes arenas, and carry their reputation across the entire ecosystem.

![Roxy SDK](https://github.com/user-attachments/assets/f57fe362-4e7c-40d6-977d-cd521fec1452)

---

## Core Features (v2.3.0)

### 1. Prediction Markets & Staking
- **In-Game Wagers**: Allow players to stake STX on the outcome of their own matches or tournaments.
- **Binary Outcomes**: Simple YES/NO pools for clear resolution (e.g., "Will Player X win Match #42?").
- **Proportional Payouts**: Winners share the losing pool's stake, minus protocol fees.
- **Slippage-Free**: Peer-to-pool model ensures liquidity and fair odds.

### 2. Campaign Management
- **Developer-Controlled Contexts**: Create "Campaigns" (seasons, tournaments, or specific game modes) to isolate scoring and leaderboards.
- **Custom configurations**: Set scoring modes (Cumulative, High Score, Low Score) and duration.
- **Sponsored Prize Pools**: Deposit STX into a campaign to reward top performers automatically.

### 3. Gamer Identity & Reputation
- **Unified Profile**: A single on-chain username and stats profile across all Roxy-integrated games.
- **Verifiable History**: Wins, losses, and total volume are tracked on-chain, creating a trustless "skill rating".
- **Sybil Resistance**: Cost-to-attack ensures leaderboards remain fair.

---

## Architecture

The Roxy ecosystem is composed of three main layers:

### 1. The Core Contract (`roxy.clar`)
The heart of the protocol. It handles:
- Campaign creation and configuration.
- Staking logic and pool management.
- User identity and global stats.
- Payout calculations and treasury management.

**Testnet Address**: `STVAH96MR73TP2FZG2W4X220MEB4NEMJHPMVYQNS.Roxy`

### 2. The SDK Trait (`roxy-sdk-trait`)
A standard interface that defines how games communicate with the core contract. This ensures forward compatibility and easy integration for developers.

**Testnet Address**: `STVAH96MR73TP2FZG2W4X220MEB4NEMJHPMVYQNS.roxy-trait`

### 3. The Game Wrapper (`game-example.clar`)
An example implementation showing how to wrap SDK calls within your game logic. This pattern allows games to abstract away the complexity of DeFi interactions from their players.

---

## Integration Guide

### Prerequisites
- **Clarinet**: For local development and testing.
- **Stacks.js**: For frontend wallet connection.

### Step 1: Implement the Trait
Your game contract should implicitly or explicitly interact with `roxy-sdk-trait`.

```clarity
(use-trait roxy-sdk-trait 'STVAH96MR73TP2FZG2W4X220MEB4NEMJHPMVYQNS.roxy-trait.roxy-sdk-trait)
```

### Step 2: Create a Campaign
Initialize your game mode (Campaign) to start tracking scores.

```clarity
(contract-call? 'STVAH96MR73TP2FZG2W4X220MEB4NEMJHPMVYQNS.Roxy create-campaign 
    0x00... (metadata-hash) 
    tx-sender (reporter) 
    u100 (start-height) 
    u1000 (end-height) 
    u0 (scoring-mode: cumulative)
)
```

### Step 3: Trigger SDK Actions
Call SDK functions from your game client or contract wrapper.

**Example: Staking on a Match**
```clarity
(contract-call? 'STVAH96MR73TP2FZG2W4X220MEB4NEMJHPMVYQNS.Roxy stake 
    event-id 
    u1000000 ;; 1 STX 
    true ;; VOTE YES
)
```

---

## Key Functions

### Game/Campaign Management
- `create-campaign`: Launch a new tracking context.
- `create-match`: Open a betting pool for a specific game event.
- `resolve-match`: (Reporter only) Settle the outcome and enable payouts.

### Player Actions
- `set-username`: Claim a unique identity.
- `stake`: Place a bet on an active match.
- `claim-reward`: Withdraw winnings from a resolved match.
- `sync-score`: Post game results to the campaign leaderboard.

### Read-Only
- `get-campaign`: View campaign details and total prize pool.
- `get-event`: Check odds/pools for a specific match.
- `get-user-profile`: Retrieve a player's alias and stats.

---

## Development & Testing

### Local Setup
1. Clone the repo.
2. `clarinet integrate` to spin up a local Devnet.
3. Deploy contracts (automatically handled by Clarinet).

### Frontend Example
Check `example/frontend-example` for a complete Vite + React implementation showing:
- Wallet Connection
- Profile Management
- Game Loop Integration
- Transaction Broadcasting

---

## License
MIT
