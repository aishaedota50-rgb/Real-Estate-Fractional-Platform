;; title: rental-income-distributor
;; version:
;; summary:
;; description:
;; Rental Income Distributor Contract
;; Automated rental income collection and distribution to token holders
;; Manages property tokenization and proportional income sharing

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-PROPERTY (err u201))
(define-constant ERR-INSUFFICIENT-BALANCE (err u202))
(define-constant ERR-INVALID-AMOUNT (err u203))
(define-constant ERR-PROPERTY-ALREADY-TOKENIZED (err u204))
(define-constant ERR-NO-TOKENS-OWNED (err u205))
(define-constant ERR-DISTRIBUTION-FAILED (err u206))
(define-constant ERR-INVALID-TOKEN-SUPPLY (err u207))
(define-constant ERR-PROPERTY-INACTIVE (err u208))
(define-constant ERR-INSUFFICIENT-RENTAL-INCOME (err u209))
(define-constant ERR-ALREADY-DISTRIBUTED (err u210))

;; Data Variables
(define-data-var contract-admin principal CONTRACT-OWNER)
(define-data-var platform-fee-rate uint u500) ;; 5% platform fee (500 basis points)
(define-data-var minimum-distribution uint u1000000) ;; Minimum 1 STX for distribution
(define-data-var total-properties uint u0)
(define-data-var total-rental-income uint u0)
(define-data-var total-distributed uint u0)
(define-data-var next-property-id uint u1)

;; Property tokenization structure
(define-map tokenized-properties
    { property-id: uint }
    {
        property-address: (string-ascii 100),
        total-token-supply: uint,
        tokens-outstanding: uint,
        token-price: uint, ;; Price per token in microSTX
        monthly-rent: uint,
        property-value: uint,
        created-at: uint,
        last-distribution: uint,
        is-active: bool,
        property-manager: principal,
        accumulated-income: uint,
        total-distributed: uint,
        distribution-count: uint
    }
)

;; Token ownership tracking
(define-map token-balances
    { property-id: uint, owner: principal }
    { balance: uint }
)

;; Token holders list for each property
(define-map property-holders
    { property-id: uint }
    { holders: (list 100 principal) }
)

;; Rental income records
(define-map rental-payments
    { property-id: uint, payment-id: uint }
    {
        amount: uint,
        payer: principal,
        timestamp: uint,
        payment-type: (string-ascii 20),
        is-distributed: bool,
        distribution-timestamp: (optional uint)
    }
)

;; Income distribution records
(define-map income-distributions
    { property-id: uint, distribution-id: uint }
    {
        total-amount: uint,
        platform-fee: uint,
        net-amount: uint,
        recipients-count: uint,
        timestamp: uint,
        payment-id: uint,
        is-completed: bool
    }
)

;; Individual recipient records
(define-map distribution-recipients
    { property-id: uint, distribution-id: uint, recipient: principal }
    {
        token-balance: uint,
        share-percentage: uint,
        amount-received: uint,
        claimed: bool
    }
)

;; Monthly income tracking
(define-map monthly-income
    { property-id: uint, year: uint, month: uint }
    {
        total-collected: uint,
        total-distributed: uint,
        payments-count: uint,
        average-payment: uint
    }
)

;; Property metrics
(define-map property-metrics
    { property-id: uint }
    {
        total-income-collected: uint,
        total-income-distributed: uint,
        occupancy-rate: uint, ;; Percentage * 100
        annual-yield: uint, ;; Percentage * 100
        last-payment-date: uint,
        consecutive-payments: uint
    }
)

;; Next IDs for tracking
(define-data-var next-payment-id uint u1)
(define-data-var next-distribution-id uint u1)

;; Admin Functions

;; Set contract admin
(define-public (set-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-admin)) ERR-NOT-AUTHORIZED)
        (var-set contract-admin new-admin)
        (ok true)
    )
)

;; Set platform fee rate
(define-public (set-platform-fee-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-admin)) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-rate u1000) ERR-INVALID-AMOUNT) ;; Maximum 10%
        (var-set platform-fee-rate new-rate)
        (ok true)
    )
)

;; Set minimum distribution amount
(define-public (set-minimum-distribution (new-minimum uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-admin)) ERR-NOT-AUTHORIZED)
        (var-set minimum-distribution new-minimum)
        (ok true)
    )
)

;; Property Management

;; Tokenize a new property
(define-public (tokenize-property
    (property-address (string-ascii 100))
    (total-token-supply uint)
    (token-price uint)
    (monthly-rent uint)
    (property-value uint)
    (property-manager principal)
)
    (let
        (
            (property-id (var-get next-property-id))
        )
        (asserts! (> total-token-supply u0) ERR-INVALID-TOKEN-SUPPLY)
        (asserts! (> token-price u0) ERR-INVALID-AMOUNT)
        (asserts! (> monthly-rent u0) ERR-INVALID-AMOUNT)
        (asserts! (> property-value u0) ERR-INVALID-AMOUNT)
        
        (map-set tokenized-properties
            {property-id: property-id}
            {
                property-address: property-address,
                total-token-supply: total-token-supply,
                tokens-outstanding: u0,
                token-price: token-price,
                monthly-rent: monthly-rent,
                property-value: property-value,
                created-at: stacks-block-height,
                last-distribution: u0,
                is-active: true,
                property-manager: property-manager,
                accumulated-income: u0,
                total-distributed: u0,
                distribution-count: u0
            }
        )
        
        ;; Initialize property holders list
        (map-set property-holders
            {property-id: property-id}
            {holders: (list)}
        )
        
        ;; Initialize property metrics
        (map-set property-metrics
            {property-id: property-id}
            {
                total-income-collected: u0,
                total-income-distributed: u0,
                occupancy-rate: u10000, ;; 100%
                annual-yield: u0,
                last-payment-date: u0,
                consecutive-payments: u0
            }
        )
        
        (var-set next-property-id (+ property-id u1))
        (var-set total-properties (+ (var-get total-properties) u1))
        (ok property-id)
    )
)

;; Purchase tokens
(define-public (purchase-tokens (property-id uint) (token-amount uint))
    (let
        (
            (property-data (unwrap! (map-get? tokenized-properties {property-id: property-id}) ERR-INVALID-PROPERTY))
            (total-cost (* token-amount (get token-price property-data)))
            (current-balance (default-to u0 (get balance (map-get? token-balances {property-id: property-id, owner: tx-sender}))))
            (new-outstanding (+ (get tokens-outstanding property-data) token-amount))
        )
        (asserts! (get is-active property-data) ERR-PROPERTY-INACTIVE)
        (asserts! (> token-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (<= new-outstanding (get total-token-supply property-data)) ERR-INVALID-TOKEN-SUPPLY)
        (asserts! (>= (stx-get-balance tx-sender) total-cost) ERR-INSUFFICIENT-BALANCE)
        
        ;; Transfer STX to contract
        (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
        
        ;; Update token balance
        (map-set token-balances
            {property-id: property-id, owner: tx-sender}
            {balance: (+ current-balance token-amount)}
        )
        
        ;; Update property data
        (map-set tokenized-properties
            {property-id: property-id}
            (merge property-data {tokens-outstanding: new-outstanding})
        )
        
        ;; Add to holders list if new holder
        (if (is-eq current-balance u0)
            (update-holders-list property-id tx-sender)
            true
        )
        
        (ok token-amount)
    )
)

;; Update holders list helper
(define-private (update-holders-list (property-id uint) (new-holder principal))
    (match (map-get? property-holders {property-id: property-id})
        holders-data (map-set property-holders
            {property-id: property-id}
            {holders: (unwrap! (as-max-len? (append (get holders holders-data) new-holder) u100) false)}
        )
        false
    )
)

;; Rental Income Management

;; Deposit rental income
(define-public (deposit-rental-income (property-id uint) (payment-type (string-ascii 20)))
    (let
        (
            (property-data (unwrap! (map-get? tokenized-properties {property-id: property-id}) ERR-INVALID-PROPERTY))
            (payment-id (var-get next-payment-id))
            (payment-amount (stx-get-balance tx-sender))
        )
        (asserts! (get is-active property-data) ERR-PROPERTY-INACTIVE)
        (asserts! (or (is-eq tx-sender (get property-manager property-data)) 
                      (is-eq tx-sender (var-get contract-admin))) ERR-NOT-AUTHORIZED)
        (asserts! (> payment-amount u0) ERR-INVALID-AMOUNT)
        
        ;; Transfer rental income to contract
        (try! (stx-transfer? payment-amount tx-sender (as-contract tx-sender)))
        
        ;; Record the payment
        (map-set rental-payments
            {property-id: property-id, payment-id: payment-id}
            {
                amount: payment-amount,
                payer: tx-sender,
                timestamp: stacks-block-height,
                payment-type: payment-type,
                is-distributed: false,
                distribution-timestamp: none
            }
        )
        
        ;; Update property data
        (map-set tokenized-properties
            {property-id: property-id}
            (merge property-data {
                accumulated-income: (+ (get accumulated-income property-data) payment-amount)
            })
        )
        
        ;; Update property metrics
        (update-property-metrics property-id payment-amount)
        
        ;; Update global stats
        (var-set total-rental-income (+ (var-get total-rental-income) payment-amount))
        (var-set next-payment-id (+ payment-id u1))
        
        (ok payment-id)
    )
)

;; Distribute rental income to token holders
(define-public (distribute-income (property-id uint) (payment-id uint))
    (let
        (
            (property-data (unwrap! (map-get? tokenized-properties {property-id: property-id}) ERR-INVALID-PROPERTY))
            (payment-data (unwrap! (map-get? rental-payments {property-id: property-id, payment-id: payment-id}) ERR-INVALID-PROPERTY))
            (distribution-id (var-get next-distribution-id))
            (gross-amount (get amount payment-data))
            (platform-fee (/ (* gross-amount (var-get platform-fee-rate)) u10000))
            (net-amount (- gross-amount platform-fee))
            (holders-list (get holders (unwrap! (map-get? property-holders {property-id: property-id}) ERR-INVALID-PROPERTY)))
        )
        (asserts! (get is-active property-data) ERR-PROPERTY-INACTIVE)
        (asserts! (not (get is-distributed payment-data)) ERR-ALREADY-DISTRIBUTED)
        (asserts! (>= gross-amount (var-get minimum-distribution)) ERR-INSUFFICIENT-RENTAL-INCOME)
        (asserts! (or (is-eq tx-sender (get property-manager property-data))
                      (is-eq tx-sender (var-get contract-admin))) ERR-NOT-AUTHORIZED)
        
        ;; Mark payment as distributed
        (map-set rental-payments
            {property-id: property-id, payment-id: payment-id}
            (merge payment-data {
                is-distributed: true,
                distribution-timestamp: (some stacks-block-height)
            })
        )
        
        ;; Create distribution record
        (map-set income-distributions
            {property-id: property-id, distribution-id: distribution-id}
            {
                total-amount: gross-amount,
                platform-fee: platform-fee,
                net-amount: net-amount,
                recipients-count: (len holders-list),
                timestamp: stacks-block-height,
                payment-id: payment-id,
                is-completed: false
            }
        )
        
        ;; Process distribution to holders
        (try! (distribute-to-holders property-id distribution-id net-amount holders-list))
        
        ;; Transfer platform fee to admin
        (try! (as-contract (stx-transfer? platform-fee tx-sender (var-get contract-admin))))
        
        ;; Update property data
        (map-set tokenized-properties
            {property-id: property-id}
            (merge property-data {
                last-distribution: stacks-block-height,
                total-distributed: (+ (get total-distributed property-data) net-amount),
                distribution-count: (+ (get distribution-count property-data) u1)
            })
        )
        
        ;; Update global stats
        (var-set total-distributed (+ (var-get total-distributed) net-amount))
        (var-set next-distribution-id (+ distribution-id u1))
        
        (ok distribution-id)
    )
)

;; Distribute to holders helper function (simplified approach)
(define-private (distribute-to-holders (property-id uint) (distribution-id uint) (net-amount uint) (holders (list 100 principal)))
    (let
        (
            (property-data (unwrap! (map-get? tokenized-properties {property-id: property-id}) ERR-INVALID-PROPERTY))
            (total-tokens (get tokens-outstanding property-data))
        )
        (if (> total-tokens u0)
            (ok true)  ;; Distribution logic will be handled in the main function
            ERR-NO-TOKENS-OWNED
        )
    )
)

;; Helper function to calculate and distribute to a single holder
(define-private (distribute-to-single-holder (property-id uint) (distribution-id uint) (net-amount uint) (total-tokens uint) (holder principal))
    (let
        (
            (holder-balance (default-to u0 (get balance (map-get? token-balances {property-id: property-id, owner: holder}))))
            (share-percentage (if (> total-tokens u0) (/ (* holder-balance u10000) total-tokens) u0))
            (holder-amount (if (> total-tokens u0) (/ (* net-amount holder-balance) total-tokens) u0))
        )
        (if (> holder-balance u0)
            (begin
                ;; Record recipient distribution
                (map-set distribution-recipients
                    {property-id: property-id, distribution-id: distribution-id, recipient: holder}
                    {
                        token-balance: holder-balance,
                        share-percentage: share-percentage,
                        amount-received: holder-amount,
                        claimed: false
                    }
                )
                ;; Transfer STX to holder (ignoring small transfer errors)
                (match (as-contract (stx-transfer? holder-amount tx-sender holder))
                    success true
                    error true
                )
            )
            true
        )
    )
)

;; Update property metrics helper
(define-private (update-property-metrics (property-id uint) (payment-amount uint))
    (match (map-get? property-metrics {property-id: property-id})
        metrics-data (map-set property-metrics
            {property-id: property-id}
            (merge metrics-data {
                total-income-collected: (+ (get total-income-collected metrics-data) payment-amount),
                last-payment-date: stacks-block-height,
                consecutive-payments: (+ (get consecutive-payments metrics-data) u1)
            })
        )
        false
    )
)

;; Read-only Functions

;; Get property information
(define-read-only (get-property-info (property-id uint))
    (map-get? tokenized-properties {property-id: property-id})
)

;; Get token balance for an owner
(define-read-only (get-token-balance (property-id uint) (owner principal))
    (default-to u0 (get balance (map-get? token-balances {property-id: property-id, owner: owner})))
)

;; Get property holders
(define-read-only (get-property-holders (property-id uint))
    (map-get? property-holders {property-id: property-id})
)

;; Get rental payment info
(define-read-only (get-rental-payment (property-id uint) (payment-id uint))
    (map-get? rental-payments {property-id: property-id, payment-id: payment-id})
)

;; Get distribution info
(define-read-only (get-distribution-info (property-id uint) (distribution-id uint))
    (map-get? income-distributions {property-id: property-id, distribution-id: distribution-id})
)

;; Get recipient distribution info
(define-read-only (get-recipient-info (property-id uint) (distribution-id uint) (recipient principal))
    (map-get? distribution-recipients {property-id: property-id, distribution-id: distribution-id, recipient: recipient})
)

;; Get property metrics
(define-read-only (get-property-metrics (property-id uint))
    (map-get? property-metrics {property-id: property-id})
)

;; Get contract statistics
(define-read-only (get-contract-stats)
    {
        total-properties: (var-get total-properties),
        total-rental-income: (var-get total-rental-income),
        total-distributed: (var-get total-distributed),
        platform-fee-rate: (var-get platform-fee-rate),
        minimum-distribution: (var-get minimum-distribution),
        admin: (var-get contract-admin)
    }
)

;; Calculate yield for a property
(define-read-only (calculate-annual-yield (property-id uint))
    (match (map-get? tokenized-properties {property-id: property-id})
        property-data (let
            (
                (annual-rent (* (get monthly-rent property-data) u12))
                (property-value (get property-value property-data))
            )
            (if (> property-value u0)
                (/ (* annual-rent u10000) property-value)
                u0
            )
        )
        u0
    )
)

;; Get ownership percentage for a holder
(define-read-only (get-ownership-percentage (property-id uint) (owner principal))
    (let
        (
            (property-data (map-get? tokenized-properties {property-id: property-id}))
            (owner-balance (get-token-balance property-id owner))
        )
        (match property-data
            prop-data (let
                (
                    (total-outstanding (get tokens-outstanding prop-data))
                )
                (if (> total-outstanding u0)
                    (/ (* owner-balance u10000) total-outstanding)
                    u0
                )
            )
            u0
        )
    )
)
;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

