# Roxy - Bitcoin L2 Prediction Market Game

## Overview

Roxy is a decentralized prediction market platform built on Bitcoin Layer 2 (Stacks blockchain) that enables users to make predictions on various outcomes, accumulate points through successful predictions, and participate in a peer-to-peer marketplace for trading points. The platform combines individual prediction capabilities with collaborative guild-based prediction systems, creating a competitive environment with comprehensive leaderboards.


![Roxy Logo](https://github.com/user-attachments/assets/f57fe362-4e7c-40d6-977d-cd521fec1452)

## Features

###  Prediction Markets

- **Binary Event System**: Create and participate in YES/NO prediction events covering sports, price movements, and other outcomes
- **Proportional Rewards**: Winners receive rewards proportional to their stake in the winning pool
- **Admin-Controlled Events**: Secure event creation and resolution managed by contract administrators
- **Multi-Event Support**: Simultaneous participation across multiple prediction events

###  Collaborative Guild System

- **Guild Creation**: Users can form prediction guilds to pool resources and strategies
- **Shared Staking**: Guild members contribute points to a collective pool for larger prediction stakes
- **Collective Rewards**: Winnings are distributed among guild members based on contributions
- **Guild Leaderboards**: Track and compare guild performance metrics across the platform

###  Point Marketplace

- **Point Trading**: Buy and sell earned points using STX tokens
- **Partial Purchases**: Support for buying portions of listed point packages
- **Protocol Fees**: 2% transaction fee automatically collected by the protocol
- **Listing Requirements**: 
  - Minimum 10,000 earned points required to create listings
  - 10 STX listing fee per marketplace listing
- **Secure Transactions**: All trades executed on-chain with automatic point transfers

###  Leaderboard & Statistics

- **Individual Metrics**: Track personal performance including total predictions, wins, losses, and win rate
- **Guild Rankings**: Compare guild performance across multiple metrics
- **Points Tracking**: Monitor total points earned and current balances
- **Real-time Updates**: On-chain statistics updated with each transaction

###  Points & Rewards System

- **Welcome Bonus**: New users receive 1,000 starting points upon registration
- **Earning Mechanism**: Accumulate points by correctly predicting event outcomes
- **Reward Distribution**: Proportional payout system ensures fair distribution based on stake size
- **Earned Points Tracking**: Separate tracking of earned points for marketplace eligibility

## Architecture

### Data Storage

#### User Management
- **`user-points`**: Total point balance for each registered user
- **`earned-points`**: Points accumulated from winning predictions (used for marketplace selling threshold)
- **`user-names`**: Username registry for user identification
- **`user-stats`**: Comprehensive statistics including prediction count, wins, losses, win rate, and total points earned

#### Event Management
- **`events`**: Complete event registry containing pool sizes, status (open/closed/resolved), winner information, and metadata
- **`yes-stakes`**: Individual user stakes on YES outcomes per event
- **`no-stakes`**: Individual user stakes on NO outcomes per event

#### Guild System
- **`guilds`**: Guild information including creator, name, total pooled points, and member count
- **`guild-members`**: Membership registry tracking which users belong to which guilds
- **`guild-deposits`**: Individual user contributions to guild point pools
- **`guild-yes-stakes`**: Guild collective stakes on YES outcomes per event
- **`guild-no-stakes`**: Guild collective stakes on NO outcomes per event
- **`guild-stats`**: Guild-level performance metrics for leaderboard rankings

#### Marketplace
- **`listings`**: Active and inactive point sale listings with seller information, point amounts, STX prices, and status
- **`protocol-treasury`**: Accumulated protocol fees from marketplace transactions and listing fees

#### Transaction Logging
- **`transaction-logs`**: Comprehensive on-chain event log for frontend integration, tracking all major actions (registrations, staking, claims, marketplace transactions, etc.)

## Key Functions

### User Functions
- `register(username)`: Register a new user and receive starting points
- `stake-yes(event-id, amount)`: Place a YES prediction stake
- `stake-no(event-id, amount)`: Place a NO prediction stake
- `claim(event-id)`: Claim rewards from resolved events

### Marketplace Functions
- `create-listing(points, price-stx)`: List points for sale (requires 10,000+ earned points)
- `buy-listing(listing-id, points-to-buy)`: Purchase points from marketplace
- `cancel-listing(listing-id)`: Cancel an active listing

### Guild Functions
- `create-guild(guild-id, name)`: Create a new prediction guild
- `join-guild(guild-id)`: Join an existing guild
- `deposit-to-guild(guild-id, amount)`: Contribute points to guild pool
- `guild-stake-yes(guild-id, event-id, amount)`: Place guild YES stake
- `guild-stake-no(guild-id, event-id, amount)`: Place guild NO stake
- `guild-claim(guild-id, event-id)`: Claim guild rewards

### Admin Functions
- `create-event(event-id, metadata)`: Create new prediction events
- `resolve-event(event-id, winner)`: Resolve events and set winners
- `withdraw-protocol-fees(amount)`: Withdraw accumulated protocol fees

### Read-Only Functions
- `get-user-points(user)`: Query user point balance
- `get-earned-points(user)`: Query earned points (for marketplace eligibility)
- `can-sell(user)`: Check if user can create marketplace listings
- `get-event(event-id)`: Get event details and status
- `get-listing(listing-id)`: Get marketplace listing information
- `get-protocol-treasury()`: Query protocol treasury balance
- `get-user-stats(user)`: Get user leaderboard statistics
- `get-guild-stats(guild-id)`: Get guild leaderboard statistics

## Constants

- **Starting Points**: 1,000 points for new users
- **Minimum Earned for Selling**: 10,000 earned points required to create marketplace listings
- **Listing Fee**: 10 STX per marketplace listing
- **Protocol Fee**: 2% (200 basis points) on all marketplace transactions

## Getting Started

### Prerequisites
- Stacks wallet (Hiro Wallet recommended)
- STX tokens for transaction fees and marketplace purchases
- Clarinet development environment (for local testing)


### Usage

1. **Register**: Call `register(username)` to create an account and receive 1,000 starting points
2. **Participate**: Stake points on prediction events using `stake-yes` or `stake-no`
3. **Claim Rewards**: After events are resolved, use `claim` to collect your winnings
4. **Trade Points**: Once you've earned 10,000+ points, create listings on the marketplace
5. **Join Guilds**: Form or join guilds for collaborative predictions and shared rewards

## Protocol Fees

The protocol collects fees to support development, rewards, and governance:
- **Marketplace Fee**: 2% of each point sale transaction
- **Listing Fee**: 10 STX per marketplace listing creation
- **Treasury Management**: Admin can withdraw accumulated fees via `withdraw-protocol-fees`






