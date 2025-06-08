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