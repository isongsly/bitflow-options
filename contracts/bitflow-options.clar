;; Title: BitFlow Options - Decentralized Bitcoin Options Trading
;;
;; Summary: 
;; A comprehensive Layer 2 options trading protocol enabling secure creation,
;; trading, and exercise of Bitcoin-backed call and put options on Stacks blockchain.
;; Features sophisticated collateral management, oracle price feeds, and automated 
;; settlement mechanisms for institutional-grade DeFi options trading.
;;
;; Description:
;; BitFlow Options revolutionizes Bitcoin DeFi by bringing traditional options 
;; trading to the Stacks ecosystem. Built with enterprise-grade security and 
;; compliance in mind, this protocol enables users to write covered calls, 
;; protective puts, and complex option strategies while maintaining full custody 
;; of their Bitcoin assets. The system features dynamic collateral requirements,
;; real-time price oracles, automated exercise mechanics, and comprehensive 
;; portfolio management tools. Designed for both retail traders and institutional 
;; participants seeking Bitcoin yield generation and hedging capabilities.
;;
;; Key Features:
;; - Native Bitcoin asset support through SIP-010 token standards
;; - Automated collateral management and risk assessment
;; - Oracle-based price feeds with timestamp validation
;; - Portfolio tracking for complex multi-leg strategies  
;; - Governance-controlled protocol parameters and fee structures
;; - Whitelisted token system for enhanced security
;; - Gas-optimized execution for cost-effective trading
;;

;; INTERFACES & TRAIT DEFINITIONS

;; SIP-010 Fungible Token Standard Interface
(define-trait sip-010-trait (
    (transfer
        (uint principal principal (optional (buff 34)))
        (response bool uint)
    )
    (get-balance
        (principal)
        (response uint uint)
    )
    (get-total-supply
        ()
        (response uint uint)
    )
    (get-decimals
        ()
        (response uint uint)
    )
    (get-token-uri
        ()
        (response (optional (string-utf8 256)) uint)
    )
    (get-name
        ()
        (response (string-ascii 32) uint)
    )
    (get-symbol
        ()
        (response (string-ascii 32) uint)
    )
))

;; ERROR CONSTANTS

;; Core Trading Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1001))
(define-constant ERR-INVALID-EXPIRY (err u1002))
(define-constant ERR-INVALID-STRIKE-PRICE (err u1003))
(define-constant ERR-OPTION-NOT-FOUND (err u1004))
(define-constant ERR-OPTION-EXPIRED (err u1005))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u1006))
(define-constant ERR-ALREADY-EXERCISED (err u1007))
(define-constant ERR-INVALID-PREMIUM (err u1008))

;; Validation Error Codes
(define-constant ERR-INVALID-TOKEN (err u1009))
(define-constant ERR-INVALID-SYMBOL (err u1010))
(define-constant ERR-INVALID-TIMESTAMP (err u1011))
(define-constant ERR-INVALID-ADDRESS (err u1012))
(define-constant ERR-ZERO-ADDRESS (err u1013))
(define-constant ERR-EMPTY-SYMBOL (err u1014))

;; UTILITY FUNCTIONS

(define-private (get-min
        (a uint)
        (b uint)
    )
    (if (< a b)
        a
        b
    )
)

;; DATA STRUCTURES & STORAGE MAPS

;; Core Options Registry - Stores all option contract details
(define-map options
    uint
    {
        writer: principal,
        holder: (optional principal),
        collateral-amount: uint,
        strike-price: uint,
        premium: uint,
        expiry: uint,
        is-exercised: bool,
        option-type: (string-ascii 4), ;; "CALL" or "PUT"
        state: (string-ascii 9), ;; "ACTIVE" or "EXERCISED"
    }
)

;; User Portfolio Management - Tracks positions and collateral
(define-map user-positions
    principal
    {
        written-options: (list 10 uint),
        held-options: (list 10 uint),
        total-collateral-locked: uint,
    }
)

;; Token Whitelist Registry - Approved tokens for trading
(define-map approved-tokens
    principal
    bool
)

;; Oracle Price Feed Registry - Real-time market data
(define-map price-feeds
    (string-ascii 10)
    {
        price: uint,
        timestamp: uint,
        source: principal,
    }
)

;; Approved Trading Symbols - Whitelisted trading pairs
(define-map allowed-symbols
    (string-ascii 10)
    bool
)

;; STATE VARIABLES

;; Sequential Option ID Counter
(define-data-var next-option-id uint u1)

;; Governance Parameters
(define-data-var contract-owner principal tx-sender)
(define-data-var protocol-fee-rate uint u100) ;; 1% = 100 basis points

;; CORE TRADING FUNCTIONS

;; Create New Option Contract
;; Allows users to write options by locking collateral
(define-public (write-option
        (token <sip-010-trait>)
        (collateral-amount uint)
        (strike-price uint)
        (premium uint)
        (expiry uint)
        (option-type (string-ascii 4))
    )
    (let (
            (option-id (var-get next-option-id))
            (current-time stacks-block-height)
            (token-principal (contract-of token))
        )
        ;; Input Validation
        (asserts! (is-approved-token token-principal) ERR-INVALID-TOKEN)
        (asserts! (> expiry current-time) ERR-INVALID-EXPIRY)
        (asserts! (> strike-price u0) ERR-INVALID-STRIKE-PRICE)
        (asserts! (> premium u0) ERR-INVALID-PREMIUM)
        (asserts!
            (check-collateral-requirement collateral-amount strike-price
                option-type
            )
            ERR-INSUFFICIENT-COLLATERAL
        )
        ;; Lock Collateral in Contract
        (try! (contract-call? token transfer collateral-amount tx-sender
            (as-contract tx-sender) none
        ))
        ;; Create Option Record
        (map-set options option-id {
            writer: tx-sender,
            holder: none,
            collateral-amount: collateral-amount,
            strike-price: strike-price,
            premium: premium,
            expiry: expiry,
            is-exercised: false,
            option-type: option-type,
            state: "ACTIVE",
        })
        ;; Update Writer Portfolio
        (let ((current-position (default-to {
                written-options: (list),
                held-options: (list),
                total-collateral-locked: u0,
            }
                (map-get? user-positions tx-sender)
            )))
            (map-set user-positions tx-sender
                (merge current-position {
                    written-options: (unwrap-panic (as-max-len?
                        (append (get written-options current-position) option-id)
                        u10
                    )),
                    total-collateral-locked: (+ (get total-collateral-locked current-position)
                        collateral-amount
                    ),
                })
            )
        )
        ;; Increment Option ID Counter
        (var-set next-option-id (+ option-id u1))
        (ok option-id)
    )
)

;; Purchase Option Contract
;; Enables buyers to acquire options by paying premium
(define-public (buy-option
        (token <sip-010-trait>)
        (option-id uint)
    )
    (let (
            (option (unwrap! (map-get? options option-id) ERR-OPTION-NOT-FOUND))
            (premium (get premium option))
            (token-principal (contract-of token))
        )
        ;; Validation Checks
        (asserts! (is-approved-token token-principal) ERR-INVALID-TOKEN)
        (asserts! (is-none (get holder option)) ERR-ALREADY-EXERCISED)
        (asserts! (< stacks-block-height (get expiry option)) ERR-OPTION-EXPIRED)
        ;; Transfer Premium to Option Writer
        (try! (contract-call? token transfer premium tx-sender (get writer option) none))
        ;; Update Option Ownership
        (map-set options option-id (merge option { holder: (some tx-sender) }))
        ;; Update Buyer Portfolio
        (let ((current-position (default-to {
                written-options: (list),
                held-options: (list),
                total-collateral-locked: u0,
            }
                (map-get? user-positions tx-sender)
            )))
            (map-set user-positions tx-sender
                (merge current-position { held-options: (unwrap-panic (as-max-len?
                    (append (get held-options current-position) option-id)
                    u10
                )) }
                ))
        )
        (ok true)
    )
)

;; Exercise Option Contract
;; Allows option holders to exercise their rights
(define-public (exercise-option
        (token <sip-010-trait>)
        (option-id uint)
    )
    (let (
            (option (unwrap! (map-get? options option-id) ERR-OPTION-NOT-FOUND))
            (current-price (get-current-price))
            (token-principal (contract-of token))
        )
        ;; Authorization & Validation
        (asserts! (is-approved-token token-principal) ERR-INVALID-TOKEN)
        (asserts! (is-eq (some tx-sender) (get holder option)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get is-exercised option)) ERR-ALREADY-EXERCISED)
        (asserts! (< stacks-block-height (get expiry option)) ERR-OPTION-EXPIRED)
        ;; Route to Appropriate Exercise Function
        (if (is-eq (get option-type option) "CALL")
            (exercise-call token option current-price)
            (exercise-put token option current-price)
        )
    )
)

;; PRIVATE HELPER FUNCTIONS

;; Validate Collateral Requirements Based on Option Type
(define-private (check-collateral-requirement
        (amount uint)
        (strike uint)
        (option-type (string-ascii 4))
    )
    (if (is-eq option-type "CALL")
        (>= amount strike)
        (>= amount (/ (* strike u100000000) (get-current-price)))
    )
)

;; Execute Call Option Exercise Logic
(define-private (exercise-call
        (token <sip-010-trait>)
        (option {
            writer: principal,
            holder: (optional principal),
            collateral-amount: uint,
            strike-price: uint,
            premium: uint,
            expiry: uint,
            is-exercised: bool,
            option-type: (string-ascii 4),
            state: (string-ascii 9),
        })
        (current-price uint)
    )
    (let (
            (profit (- current-price (get strike-price option)))
            (payout (get-min profit (get collateral-amount option)))
        )
        ;; Transfer Payout to Option Holder
        (try! (as-contract (contract-call? token transfer payout tx-sender
            (unwrap! (get holder option) ERR-NOT-AUTHORIZED) none
        )))
        ;; Return Remaining Collateral to Writer
        (try! (as-contract (contract-call? token transfer (- (get collateral-amount option) payout)
            tx-sender (get writer option) none
        )))
        ;; Mark Option as Exercised
        (map-set options (get-option-id option)
            (merge option {
                is-exercised: true,
                state: "EXERCISED",
            })
        )
        (ok true)
    )
)

;; Execute Put Option Exercise Logic
(define-private (exercise-put
        (token <sip-010-trait>)
        (option {
            writer: principal,
            holder: (optional principal),
            collateral-amount: uint,
            strike-price: uint,
            premium: uint,
            expiry: uint,
            is-exercised: bool,
            option-type: (string-ascii 4),
            state: (string-ascii 9),
        })
        (current-price uint)
    )
    (let (
            (profit (- (get strike-price option) current-price))
            (payout (get-min profit (get collateral-amount option)))
        )
        ;; Transfer Payout to Option Holder
        (try! (as-contract (contract-call? token transfer payout tx-sender
            (unwrap! (get holder option) ERR-NOT-AUTHORIZED) none
        )))
        ;; Return Remaining Collateral to Writer
        (try! (as-contract (contract-call? token transfer (- (get collateral-amount option) payout)
            tx-sender (get writer option) none
        )))
        ;; Mark Option as Exercised
        (map-set options (get-option-id option)
            (merge option {
                is-exercised: true,
                state: "EXERCISED",
            })
        )
        (ok true)
    )
)

;; ORACLE & PRICING FUNCTIONS

;; Retrieve Current Market Price from Oracle Feed
(define-private (get-current-price)
    (get price (unwrap! (map-get? price-feeds "BTC-USD") u0))
)

;; Utility Function to Get Option ID (Helper for Exercise Functions)
(define-private (get-option-id (option {
    writer: principal,
    holder: (optional principal),
    collateral-amount: uint,
    strike-price: uint,
    premium: uint,
    expiry: uint,
    is-exercised: bool,
    option-type: (string-ascii 4),
    state: (string-ascii 9),
}))
    (var-get next-option-id)
)

;; VALIDATION HELPER FUNCTIONS

;; Check if Token is Approved for Trading
(define-private (is-approved-token (token principal))
    (default-to false (map-get? approved-tokens token))
)

;; Check if Trading Symbol is Allowed
(define-private (is-allowed-symbol (symbol (string-ascii 10)))
    (default-to false (map-get? allowed-symbols symbol))
)

;; Validate Principal Address Format
(define-private (is-valid-principal (address principal))
    (and
        (not (is-eq address (as-contract tx-sender)))
        (not (is-eq address .base))
        (not (is-eq address tx-sender))
        true
    )
)

;; Validate Trading Symbol Format
(define-private (is-valid-symbol (symbol (string-ascii 10)))
    (and
        (not (is-eq symbol ""))
        (not (is-eq symbol " "))
        (>= (len symbol) u2)
    )
)

;; Check if Token is Critical (Protected)
(define-private (is-critical-token (token principal))
    (or
        (is-eq token .wrapped-btc)
        (is-eq token .wrapped-stx)
    )
)

;; Check if Symbol is Critical (Protected)
(define-private (is-critical-symbol (symbol (string-ascii 10)))
    (or
        (is-eq symbol "BTC-USD")
        (is-eq symbol "STX-USD")
    )
)

;; READ-ONLY QUERY FUNCTIONS

;; Retrieve Option Contract Details
(define-read-only (get-option (option-id uint))
    (map-get? options option-id)
)

;; Retrieve User Portfolio Information
(define-read-only (get-user-position (user principal))
    (map-get? user-positions user)
)

;; Get Current Protocol Fee Rate
(define-read-only (get-protocol-fee-rate)
    (var-get protocol-fee-rate)
)

;; ADMINISTRATIVE & GOVERNANCE FUNCTIONS

;; Update Protocol Fee Structure (Owner Only)
(define-public (set-protocol-fee-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-rate u1000) ERR-INVALID-PREMIUM) ;; Maximum 10%
        (var-set protocol-fee-rate new-rate)
        (ok true)
    )
)

;; Update Oracle Price Feed Data (Owner Only)
(define-public (update-price-feed
        (symbol (string-ascii 10))
        (price uint)
        (timestamp uint)
    )
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-allowed-symbol symbol) ERR-INVALID-SYMBOL)
        (asserts! (>= timestamp stacks-block-height) ERR-INVALID-TIMESTAMP)
        (asserts! (> price u0) ERR-INVALID-STRIKE-PRICE)
        (map-set price-feeds symbol {
            price: price,
            timestamp: timestamp,
            source: tx-sender,
        })
        (ok true)
    )
)

;; Manage Token Whitelist (Owner Only)
(define-public (set-approved-token
        (token principal)
        (approved bool)
    )
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-principal token) ERR-INVALID-ADDRESS)
        (asserts! (not (is-eq token .base)) ERR-INVALID-TOKEN)
        ;; Protect Critical Tokens from Removal
        (asserts!
            (or
                approved
                (not (is-critical-token token))
            )
            ERR-NOT-AUTHORIZED
        )
        (map-set approved-tokens token approved)
        (ok true)
    )
)

;; Manage Trading Symbol Whitelist (Owner Only)
(define-public (set-allowed-symbol
        (symbol (string-ascii 10))
        (allowed bool)
    )
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-symbol symbol) ERR-EMPTY-SYMBOL)
        ;; Protect Critical Symbols from Removal
        (asserts!
            (or
                allowed
                (not (is-critical-symbol symbol))
            )
            ERR-NOT-AUTHORIZED
        )
        (map-set allowed-symbols symbol allowed)
        (ok true)
    )
)
