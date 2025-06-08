# BitFlow Options Protocol

> **Decentralized Bitcoin Options Trading on Stacks Layer 2**

A comprehensive, institutional-grade options trading protocol enabling secure creation, trading, and exercise of Bitcoin-backed derivatives on the Stacks blockchain. Built for both retail traders and institutional participants seeking Bitcoin yield generation and sophisticated hedging capabilities.

## 🚀 Key Features

- **Native Bitcoin Support** - Trade options on Bitcoin and Bitcoin-pegged assets through SIP-010 tokens
- **Automated Collateral Management** - Dynamic risk assessment and automated collateral requirements
- **Oracle-Based Pricing** - Real-time price feeds with timestamp validation for accurate settlements  
- **Portfolio Management** - Comprehensive tracking for complex multi-leg option strategies
- **Gas Optimized** - Cost-effective execution designed for high-frequency trading
- **Institutional Grade** - Enterprise security with governance-controlled parameters

## 🏗️ System Overview

BitFlow Options operates as a decentralized exchange for Bitcoin options, leveraging Stacks' Layer 2 capabilities to provide fast, cost-effective derivatives trading while maintaining Bitcoin's security guarantees.

### Core Components

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Option Writer │    │  Option Buyer   │    │ Protocol Oracle │
│                 │    │                 │    │                 │
│ • Locks Collat. │    │ • Pays Premium  │    │ • Price Feeds   │
│ • Sets Terms    │◄──►│ • Gains Rights  │◄──►│ • Validation    │
│ • Earns Premium │    │ • Can Exercise  │    │ • Timestamps    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │ BitFlow Options │
                    │    Protocol     │
                    │                 │
                    │ • Option Registry│
                    │ • Collateral Mgmt│
                    │ • Auto Settlement│
                    └─────────────────┘
```

## 🏛️ Contract Architecture

### Data Structures

#### Option Registry

```clarity
(define-map options uint {
    writer: principal,           ;; Option creator
    holder: (optional principal), ;; Option owner
    collateral-amount: uint,     ;; Locked collateral
    strike-price: uint,          ;; Exercise price
    premium: uint,               ;; Option cost
    expiry: uint,                ;; Expiration block
    is-exercised: bool,          ;; Exercise status
    option-type: (string-ascii 4), ;; "CALL" or "PUT"
    state: (string-ascii 9)      ;; "ACTIVE" or "EXERCISED"
})
```

#### Portfolio Management

```clarity
(define-map user-positions principal {
    written-options: (list 10 uint),    ;; Created options
    held-options: (list 10 uint),       ;; Owned options
    total-collateral-locked: uint       ;; Total locked funds
})
```

#### Oracle Price Feeds

```clarity
(define-map price-feeds (string-ascii 10) {
    price: uint,        ;; Current market price
    timestamp: uint,    ;; Last update time
    source: principal   ;; Oracle provider
})
```

### Function Categories

#### Core Trading Functions

- `write-option` - Create new option contracts
- `buy-option` - Purchase existing options
- `exercise-option` - Execute option rights

#### Administrative Functions

- `set-protocol-fee-rate` - Update fee structure
- `update-price-feed` - Manage oracle data
- `set-approved-token` - Token whitelist management
- `set-allowed-symbol` - Trading pair management

#### Query Functions

- `get-option` - Retrieve option details
- `get-user-position` - View user portfolio
- `get-protocol-fee-rate` - Check current fees

## 🔄 Data Flow

### Option Creation Flow

```
1. Writer calls write-option()
   ├── Validate inputs (expiry, strike, premium)
   ├── Check collateral requirements
   ├── Lock collateral in contract
   ├── Create option record
   ├── Update writer's portfolio
   └── Return option ID

2. Option becomes available for purchase
```

### Option Trading Flow

```
1. Buyer calls buy-option()
   ├── Validate option exists and not expired
   ├── Transfer premium to writer
   ├── Update option ownership
   ├── Update buyer's portfolio
   └── Option ready for exercise

2. Option holder can exercise before expiry
```

### Exercise Flow

```
1. Holder calls exercise-option()
   ├── Validate ownership and expiry
   ├── Get current price from oracle
   ├── Calculate profit/payout
   ├── Transfer funds (payout + remaining collateral)
   ├── Mark option as exercised
   └── Update portfolios
```

## 🛡️ Security Features

### Collateral Management

- **Dynamic Requirements** - Collateral calculated based on option type and strike price
- **Automated Validation** - Real-time checks prevent under-collateralized positions
- **Locked Funds** - Collateral secured in contract until exercise or expiry

### Access Control

- **Owner-Only Functions** - Critical parameters controlled by governance
- **Token Whitelist** - Only approved tokens can be used for trading
- **Protected Assets** - Critical tokens (BTC, STX) have removal protection

### Oracle Security

- **Timestamp Validation** - Price feeds must be current
- **Source Tracking** - All price updates logged with provider information
- **Protected Symbols** - Critical trading pairs cannot be disabled

## 📋 Usage Guide

### Writing Options

```clarity
;; Create a Bitcoin call option
(contract-call? .bitflow-options write-option
    .wrapped-bitcoin      ;; Underlying asset
    u100000000           ;; 1 BTC collateral (8 decimals)
    u4500000000000       ;; $45,000 strike price
    u500000000           ;; 0.05 BTC premium
    u2160               ;; Expires in ~15 days
    "CALL")             ;; Call option
```

### Buying Options

```clarity
;; Purchase an existing option
(contract-call? .bitflow-options buy-option
    .wrapped-bitcoin    ;; Payment token
    u1)                ;; Option ID
```

### Exercising Options

```clarity
;; Exercise option rights
(contract-call? .bitflow-options exercise-option
    .wrapped-bitcoin    ;; Settlement token
    u1)                ;; Option ID
```

## 🔧 Development Setup

### Prerequisites

- Stacks CLI (`stacks-cli`)
- Clarinet for testing
- SIP-010 compliant tokens

### Deployment

1. Deploy token contracts first
2. Deploy BitFlow Options protocol
3. Configure approved tokens and price feeds
4. Set initial protocol parameters

### Testing

```bash
clarinet test
clarinet check
```

## 📊 Protocol Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Protocol Fee | 1% (100 bp) | Fee on option exercises |
| Max Fee Rate | 10% (1000 bp) | Maximum allowable fee |
| Min Collateral | Strike Price | Minimum collateral for calls |
| Oracle Timeout | N/A | Price feed staleness limit |

## 🤝 Contributing

We welcome contributions to BitFlow Options Protocol. Please review our contribution guidelines and submit pull requests for review.
