;; title: property-valuation-oracle
;; version:
;; summary:
;; description:
;; Property Valuation Oracle Contract
;; Provides real-time property valuation using market data and property metrics
;; Maintains historical valuation records and provides APIs for other contracts

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-PROPERTY (err u101))
(define-constant ERR-INVALID-VALUATION (err u102))
(define-constant ERR-PROPERTY-EXISTS (err u103))
(define-constant ERR-INSUFFICIENT-DATA (err u104))
(define-constant ERR-ORACLE-NOT-AUTHORIZED (err u105))
(define-constant ERR-INVALID-TIMESTAMP (err u106))
(define-constant ERR-STALE-DATA (err u107))

;; Data Variables
(define-data-var contract-admin principal CONTRACT-OWNER)
(define-data-var oracle-fee uint u1000) ;; Fee in microSTX for oracle services
(define-data-var max-data-age uint u86400) ;; Maximum age of data in seconds (24 hours)
(define-data-var total-properties uint u0)
(define-data-var total-valuations uint u0)

;; Property structure
(define-map properties
    { property-id: uint }
    {
        address: (string-ascii 100),
        property-type: (string-ascii 20),
        square-footage: uint,
        bedrooms: uint,
        bathrooms: uint,
        year-built: uint,
        lot-size: uint,
        neighborhood: (string-ascii 50),
        created-at: uint,
        last-updated: uint,
        is-active: bool
    }
)

;; Valuation structure
(define-map property-valuations
    { property-id: uint, timestamp: uint }
    {
        current-value: uint,
        market-value: uint,
        rental-yield: uint, ;; Annual rental yield percentage * 100
        appreciation-rate: uint, ;; Annual appreciation rate * 100
        confidence-score: uint, ;; Confidence score 0-100
        comparable-sales: uint,
        market-conditions: (string-ascii 20),
        valuation-method: (string-ascii 30),
        oracle-address: principal,
        data-sources: (list 5 (string-ascii 30))
    }
)

;; Historical valuations tracking
(define-map property-history
    { property-id: uint }
    {
        valuations-count: uint,
        first-valuation: uint,
        last-valuation: uint,
        highest-value: uint,
        lowest-value: uint,
        average-value: uint
    }
)

;; Oracle providers
(define-map authorized-oracles
    { oracle-address: principal }
    {
        name: (string-ascii 50),
        reputation-score: uint,
        total-valuations: uint,
        accuracy-rating: uint,
        is-active: bool,
        created-at: uint
    }
)

;; Market data
(define-map market-data
    { region: (string-ascii 50), timestamp: uint }
    {
        median-price: uint,
        price-per-sqft: uint,
        inventory-level: uint,
        days-on-market: uint,
        sales-volume: uint,
        price-trend: (string-ascii 20),
        market-volatility: uint
    }
)

;; Latest property values (for quick access)
(define-map latest-valuations
    { property-id: uint }
    {
        value: uint,
        timestamp: uint,
        oracle: principal,
        confidence: uint
    }
)

;; Admin Functions

;; Set contract admin
(define-public (set-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-admin)) ERR-NOT-AUTHORIZED)
        (var-set contract-admin new-admin)
        (ok true)
    )
)

;; Set oracle fee
(define-public (set-oracle-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-admin)) ERR-NOT-AUTHORIZED)
        (var-set oracle-fee new-fee)
        (ok true)
    )
)

;; Set maximum data age
(define-public (set-max-data-age (new-age uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-admin)) ERR-NOT-AUTHORIZED)
        (var-set max-data-age new-age)
        (ok true)
    )
)

;; Oracle Management

;; Add authorized oracle
(define-public (add-oracle (oracle-address principal) (name (string-ascii 50)))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-admin)) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (map-get? authorized-oracles {oracle-address: oracle-address})) ERR-PROPERTY-EXISTS)
        (map-set authorized-oracles
            {oracle-address: oracle-address}
            {
                name: name,
                reputation-score: u75,
                total-valuations: u0,
                accuracy-rating: u50,
                is-active: true,
                created-at: stacks-block-height
            }
        )
        (ok true)
    )
)

;; Deactivate oracle
(define-public (deactivate-oracle (oracle-address principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-admin)) ERR-NOT-AUTHORIZED)
        (match (map-get? authorized-oracles {oracle-address: oracle-address})
            oracle-data (begin
                (map-set authorized-oracles
                    {oracle-address: oracle-address}
                    (merge oracle-data {is-active: false})
                )
                (ok true)
            )
            ERR-INVALID-PROPERTY
        )
    )
)

;; Property Management

;; Register new property
(define-public (register-property
    (property-id uint)
    (address (string-ascii 100))
    (property-type (string-ascii 20))
    (square-footage uint)
    (bedrooms uint)
    (bathrooms uint)
    (year-built uint)
    (lot-size uint)
    (neighborhood (string-ascii 50))
)
    (begin
        (asserts! (is-none (map-get? properties {property-id: property-id})) ERR-PROPERTY-EXISTS)
        (asserts! (> square-footage u0) ERR-INVALID-PROPERTY)
        (asserts! (> year-built u1900) ERR-INVALID-PROPERTY)
        
        (map-set properties
            {property-id: property-id}
            {
                address: address,
                property-type: property-type,
                square-footage: square-footage,
                bedrooms: bedrooms,
                bathrooms: bathrooms,
                year-built: year-built,
                lot-size: lot-size,
                neighborhood: neighborhood,
                created-at: stacks-block-height,
                last-updated: stacks-block-height,
                is-active: true
            }
        )
        
        (var-set total-properties (+ (var-get total-properties) u1))
        (ok property-id)
    )
)

;; Update property information
(define-public (update-property
    (property-id uint)
    (square-footage uint)
    (bedrooms uint)
    (bathrooms uint)
    (lot-size uint)
)
    (begin
        (match (map-get? properties {property-id: property-id})
            property-data (begin
                (asserts! (> square-footage u0) ERR-INVALID-PROPERTY)
                (map-set properties
                    {property-id: property-id}
                    (merge property-data {
                        square-footage: square-footage,
                        bedrooms: bedrooms,
                        bathrooms: bathrooms,
                        lot-size: lot-size,
                        last-updated: stacks-block-height
                    })
                )
                (ok true)
            )
            ERR-INVALID-PROPERTY
        )
    )
)

;; Valuation Functions

;; Submit property valuation (by authorized oracle)
(define-public (submit-valuation
    (property-id uint)
    (current-value uint)
    (market-value uint)
    (rental-yield uint)
    (appreciation-rate uint)
    (confidence-score uint)
    (comparable-sales uint)
    (market-conditions (string-ascii 20))
    (valuation-method (string-ascii 30))
    (data-sources (list 5 (string-ascii 30)))
)
    (let
        (
            (timestamp stacks-block-height)
            (oracle-data (map-get? authorized-oracles {oracle-address: tx-sender}))
        )
        (asserts! (is-some oracle-data) ERR-ORACLE-NOT-AUTHORIZED)
        (asserts! (get is-active (unwrap-panic oracle-data)) ERR-ORACLE-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? properties {property-id: property-id})) ERR-INVALID-PROPERTY)
        (asserts! (> current-value u0) ERR-INVALID-VALUATION)
        (asserts! (<= confidence-score u100) ERR-INVALID-VALUATION)
        
        ;; Store the valuation
        (map-set property-valuations
            {property-id: property-id, timestamp: timestamp}
            {
                current-value: current-value,
                market-value: market-value,
                rental-yield: rental-yield,
                appreciation-rate: appreciation-rate,
                confidence-score: confidence-score,
                comparable-sales: comparable-sales,
                market-conditions: market-conditions,
                valuation-method: valuation-method,
                oracle-address: tx-sender,
                data-sources: data-sources
            }
        )
        
        ;; Update latest valuation
        (map-set latest-valuations
            {property-id: property-id}
            {
                value: current-value,
                timestamp: timestamp,
                oracle: tx-sender,
                confidence: confidence-score
            }
        )
        
        ;; Update property history
        (update-property-history property-id current-value)
        
        ;; Update oracle stats
        (update-oracle-stats tx-sender)
        
        (var-set total-valuations (+ (var-get total-valuations) u1))
        (ok timestamp)
    )
)

;; Update property history helper
(define-private (update-property-history (property-id uint) (value uint))
    (match (map-get? property-history {property-id: property-id})
        history-data (map-set property-history
            {property-id: property-id}
            {
                valuations-count: (+ (get valuations-count history-data) u1),
                first-valuation: (get first-valuation history-data),
                last-valuation: stacks-block-height,
                highest-value: (if (> value (get highest-value history-data)) value (get highest-value history-data)),
                lowest-value: (if (< value (get lowest-value history-data)) value (get lowest-value history-data)),
                average-value: (/ (+ (* (get average-value history-data) (get valuations-count history-data)) value) (+ (get valuations-count history-data) u1))
            }
        )
        (map-set property-history
            {property-id: property-id}
            {
                valuations-count: u1,
                first-valuation: stacks-block-height,
                last-valuation: stacks-block-height,
                highest-value: value,
                lowest-value: value,
                average-value: value
            }
        )
    )
)

;; Update oracle statistics
(define-private (update-oracle-stats (oracle-address principal))
    (match (map-get? authorized-oracles {oracle-address: oracle-address})
        oracle-data (map-set authorized-oracles
            {oracle-address: oracle-address}
            (merge oracle-data {
                total-valuations: (+ (get total-valuations oracle-data) u1)
            })
        )
        false
    )
)

;; Read-only Functions

;; Get property information
(define-read-only (get-property (property-id uint))
    (map-get? properties {property-id: property-id})
)

;; Get latest valuation
(define-read-only (get-latest-valuation (property-id uint))
    (map-get? latest-valuations {property-id: property-id})
)

;; Get specific valuation
(define-read-only (get-valuation (property-id uint) (timestamp uint))
    (map-get? property-valuations {property-id: property-id, timestamp: timestamp})
)

;; Get property history
(define-read-only (get-property-history (property-id uint))
    (map-get? property-history {property-id: property-id})
)

;; Get oracle information
(define-read-only (get-oracle-info (oracle-address principal))
    (map-get? authorized-oracles {oracle-address: oracle-address})
)

;; Get contract stats
(define-read-only (get-contract-stats)
    {
        total-properties: (var-get total-properties),
        total-valuations: (var-get total-valuations),
        oracle-fee: (var-get oracle-fee),
        max-data-age: (var-get max-data-age),
        admin: (var-get contract-admin)
    }
)

;; Get market data
(define-read-only (get-market-data (region (string-ascii 50)) (timestamp uint))
    (map-get? market-data {region: region, timestamp: timestamp})
)

;; Validate data freshness
(define-read-only (is-data-fresh (timestamp uint))
    (>= (+ timestamp (var-get max-data-age)) stacks-block-height)
)

;; Calculate property value trend
(define-read-only (get-value-trend (property-id uint))
    (match (map-get? property-history {property-id: property-id})
        history-data (let
            (
                (current-val (default-to u0 (get value (map-get? latest-valuations {property-id: property-id}))))
                (avg-val (get average-value history-data))
            )
            (if (> current-val avg-val)
                {trend: "increasing", percentage: (/ (* (- current-val avg-val) u100) avg-val)}
                {trend: "decreasing", percentage: (/ (* (- avg-val current-val) u100) avg-val)}
            )
        )
        {trend: "no-data", percentage: u0}
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

