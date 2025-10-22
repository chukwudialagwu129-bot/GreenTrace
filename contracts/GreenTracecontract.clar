;; title: GreenTrace Carbon Footprint Tracking
;; version: 1.0.0
;; summary: Track product carbon footprint through entire supply chain with manufacturing verification
;; description: This contract enables manufacturers, logistics providers, and retailers to submit verified
;;              carbon data, links physical products to carbon NFTs via QR codes, and allows consumers
;;              to verify environmental claims and manage carbon budgets.

;; traits
(define-trait carbon-verifier-trait
  (
    (verify-carbon-data (uint uint principal) (response bool uint))
  )
)

;; token definitions
(define-non-fungible-token carbon-nft uint)
(define-fungible-token carbon-credit)

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u401))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_ALREADY_EXISTS (err u409))
(define-constant ERR_INVALID_AMOUNT (err u400))
(define-constant ERR_INSUFFICIENT_BALANCE (err u402))
(define-constant ERR_INVALID_PARTICIPANT (err u403))
(define-constant ERR_PRODUCT_NOT_REGISTERED (err u405))
(define-constant ERR_CARBON_DATA_NOT_VERIFIED (err u406))
(define-constant ERR_CONTRACT_PAUSED (err u407))
(define-constant ERR_RATE_LIMIT_EXCEEDED (err u408))
(define-constant ERR_OVERFLOW (err u409))
(define-constant ERR_INVALID_INPUT (err u410))
(define-constant ERR_UNDERFLOW (err u411))

;; data vars
(define-data-var next-product-id uint u1)
(define-data-var total-carbon-credits uint u0)
(define-data-var carbon-credit-price uint u1000000) ;; 1 STX per credit
(define-data-var contract-paused bool false)

(define-constant RATE-LIMIT-BLOCKS u10)
(define-constant MAX-OPERATIONS-PER-BLOCK u5)

;; data maps
;; Manufacturer registration
(define-map manufacturers
  principal
  {
    name: (string-ascii 50),
    certification: (string-ascii 100),
    is-verified: bool,
    registered-at: uint
  }
)

;; Logistics provider registration  
(define-map logistics-providers
  principal
  {
    name: (string-ascii 50),
    certification: (string-ascii 100),
    is-verified: bool,
    registered-at: uint
  }
)

;; Product registration with carbon NFT
(define-map products
  uint ;; product-id
  {
    manufacturer: principal,
    product-name: (string-ascii 50),
    manufacturing-carbon: uint,
    logistics-carbon: uint,
    total-carbon: uint,
    qr-code-hash: (buff 32),
    created-at: uint,
    is-verified: bool
  }
)

;; QR code to product mapping
(define-map qr-codes
  (buff 32) ;; QR code hash
  uint ;; product-id
)

;; Consumer carbon budgets
(define-map consumer-budgets
  principal
  {
    monthly-budget: uint,
    current-usage: uint,
    last-reset: uint,
    total-offsets-purchased: uint
  }
)

;; Carbon footprint submissions (pending verification)
(define-map carbon-submissions
  {submitter: principal, product-id: uint, submission-type: (string-ascii 20)}
  {
    carbon-amount: uint,
    verification-data: (string-ascii 200),
    submitted-at: uint,
    is-verified: bool
  }
)

;; Retailer carbon disclosures
(define-map retailer-disclosures
  principal
  {
    total-products: uint,
    average-carbon-footprint: uint,
    last-updated: uint
  }
)

(define-map last-operation-block principal uint)
(define-map operations-per-block {user: principal, block: uint} uint)

;; Security helper functions
(define-private (check-not-paused)
  (if (var-get contract-paused)
    ERR_CONTRACT_PAUSED
    (ok true)
  )
)

(define-private (safe-add (a uint) (b uint))
  (let ((result (+ a b)))
    (asserts! (>= result a) ERR_OVERFLOW)
    (ok result)
  )
)

(define-private (safe-mul (a uint) (b uint))
  (let ((result (* a b)))
    (asserts! (or (is-eq b u0) (is-eq (/ result b) a)) ERR_OVERFLOW)
    (ok result)
  )
)

(define-private (safe-sub (a uint) (b uint))
  (if (>= a b)
    (ok (- a b))
    ERR_UNDERFLOW
  )
)

(define-private (check-rate-limit (user principal))
  (let (
    (current-block block-height)
    (last-block (default-to u0 (map-get? last-operation-block user)))
    (ops-count (default-to u0 (map-get? operations-per-block {user: user, block: current-block})))
  )
    (asserts! 
      (or 
        (>= (- current-block last-block) RATE-LIMIT-BLOCKS)
        (< ops-count MAX-OPERATIONS-PER-BLOCK)
      )
      ERR_RATE_LIMIT_EXCEEDED
    )
    (map-set last-operation-block user current-block)
    (map-set operations-per-block {user: user, block: current-block} (+ ops-count u1))
    (ok true)
  )
)

(define-private (validate-string-not-empty (str (string-ascii 50)))
  (if (> (len str) u0)
    (ok true)
    ERR_INVALID_INPUT
  )
)

;; public functions

;; Pause/unpause contract (owner only)
(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set contract-paused false)
    (ok true)
  )
)

;; Register as manufacturer
(define-public (register-manufacturer (name (string-ascii 50)) (certification (string-ascii 100)))
  (let ((caller tx-sender))
    (try! (check-not-paused))
    (try! (check-rate-limit caller))
    (try! (validate-string-not-empty name))
    (asserts! (is-none (map-get? manufacturers caller)) ERR_ALREADY_EXISTS)
    (map-set manufacturers caller {
      name: name,
      certification: certification,
      is-verified: false,
      registered-at: block-height
    })
    (ok true)
  )
)

;; Register as logistics provider
(define-public (register-logistics-provider (name (string-ascii 50)) (certification (string-ascii 100)))
  (let ((caller tx-sender))
    (try! (check-not-paused))
    (try! (check-rate-limit caller))
    (try! (validate-string-not-empty name))
    (asserts! (is-none (map-get? logistics-providers caller)) ERR_ALREADY_EXISTS)
    (map-set logistics-providers caller {
      name: name,
      certification: certification,
      is-verified: false,
      registered-at: block-height
    })
    (ok true)
  )
)

;; Register product with manufacturing carbon data
(define-public (register-product 
  (product-name (string-ascii 50))
  (manufacturing-carbon uint)
  (qr-code-hash (buff 32))
  (verification-data (string-ascii 200))
)
  (let (
    (product-id (var-get next-product-id))
    (caller tx-sender)
  )
    (try! (check-not-paused))
    (try! (check-rate-limit caller))
    (try! (validate-string-not-empty product-name))
    (asserts! (> manufacturing-carbon u0) ERR_INVALID_AMOUNT)
    
    ;; Check if caller is verified manufacturer
    (asserts! (is-some (map-get? manufacturers caller)) ERR_NOT_AUTHORIZED)
    (asserts! (get is-verified (unwrap-panic (map-get? manufacturers caller))) ERR_NOT_AUTHORIZED)
    
    ;; Check QR code not already used
    (asserts! (is-none (map-get? qr-codes qr-code-hash)) ERR_ALREADY_EXISTS)
    
    ;; Submit carbon data for verification
    (map-set carbon-submissions 
      {submitter: caller, product-id: product-id, submission-type: "manufacturing"}
      {
        carbon-amount: manufacturing-carbon,
        verification-data: verification-data,
        submitted-at: block-height,
        is-verified: false
      }
    )
    
    ;; Register product (initially unverified)
    (map-set products product-id {
      manufacturer: caller,
      product-name: product-name,
      manufacturing-carbon: manufacturing-carbon,
      logistics-carbon: u0,
      total-carbon: manufacturing-carbon,
      qr-code-hash: qr-code-hash,
      created-at: block-height,
      is-verified: false
    })
    
    ;; Map QR code to product
    (map-set qr-codes qr-code-hash product-id)
    
    ;; Mint carbon NFT
    (try! (nft-mint? carbon-nft product-id caller))
    
    ;; Increment product counter
    (var-set next-product-id (unwrap! (safe-add product-id u1) ERR_OVERFLOW))
    
    (ok product-id)
  )
)

;; Submit logistics carbon data
(define-public (submit-logistics-carbon 
  (product-id uint)
  (logistics-carbon uint)
  (verification-data (string-ascii 200))
)
  (let ((caller tx-sender))
    (try! (check-not-paused))
    (try! (check-rate-limit caller))
    (asserts! (> logistics-carbon u0) ERR_INVALID_AMOUNT)
    
    ;; Check if caller is verified logistics provider
    (asserts! (is-some (map-get? logistics-providers caller)) ERR_NOT_AUTHORIZED)
    (asserts! (get is-verified (unwrap-panic (map-get? logistics-providers caller))) ERR_NOT_AUTHORIZED)
    
    ;; Check product exists
    (asserts! (is-some (map-get? products product-id)) ERR_PRODUCT_NOT_REGISTERED)
    
    ;; Submit logistics carbon data for verification
    (map-set carbon-submissions 
      {submitter: caller, product-id: product-id, submission-type: "logistics"}
      {
        carbon-amount: logistics-carbon,
        verification-data: verification-data,
        submitted-at: block-height,
        is-verified: false
      }
    )
    
    (ok true)
  )
)

;; Verify carbon data submission (contract owner only)
(define-public (verify-carbon-submission 
  (submitter principal)
  (product-id uint)
  (submission-type (string-ascii 20))
  (approved bool)
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    
    (match (map-get? carbon-submissions {submitter: submitter, product-id: product-id, submission-type: submission-type})
      submission (begin
        ;; Update submission verification status
        (map-set carbon-submissions 
          {submitter: submitter, product-id: product-id, submission-type: submission-type}
          (merge submission {is-verified: approved})
        )
        
        ;; If approved, update product data
        (if approved
          (if (is-eq submission-type "manufacturing")
            (begin
              (asserts! (is-some (map-get? products product-id)) ERR_PRODUCT_NOT_REGISTERED)
              (map-set products product-id (merge (unwrap-panic (map-get? products product-id)) {
                is-verified: true
              }))
            )
            (if (is-eq submission-type "logistics")
              (begin
                (asserts! (is-some (map-get? products product-id)) ERR_PRODUCT_NOT_REGISTERED)
                (let ((product (unwrap-panic (map-get? products product-id)))
                      (new-total (+ (get manufacturing-carbon product) (get carbon-amount submission))))
                  (map-set products product-id (merge product {
                    logistics-carbon: (get carbon-amount submission),
                    total-carbon: new-total
                  }))
                )
              )
              true
            )
          )
          true
        )
        
        (ok approved)
      )
      ERR_NOT_FOUND
    )
  )
)

;; Set consumer carbon budget
(define-public (set-carbon-budget (monthly-budget uint))
  (let ((caller tx-sender))
    (try! (check-not-paused))
    (asserts! (> monthly-budget u0) ERR_INVALID_AMOUNT)
    (map-set consumer-budgets caller {
      monthly-budget: monthly-budget,
      current-usage: u0,
      last-reset: block-height,
      total-offsets-purchased: u0
    })
    (ok true)
  )
)

;; Record consumer purchase (updates carbon usage)
(define-public (record-consumer-purchase (product-id uint))
  (let (
    (caller tx-sender)
    (current-height block-height)
  )
    (match (map-get? products product-id)
      product (begin
        (asserts! (get is-verified product) ERR_CARBON_DATA_NOT_VERIFIED)
        
        (match (map-get? consumer-budgets caller)
          budget (let (
            (blocks-since-reset (- current-height (get last-reset budget)))
            (should-reset (>= blocks-since-reset u4320)) ;; ~30 days in blocks
            (current-usage (if should-reset u0 (get current-usage budget)))
            (new-usage (+ current-usage (get total-carbon product)))
          )
            (map-set consumer-budgets caller (merge budget {
              current-usage: new-usage,
              last-reset: (if should-reset current-height (get last-reset budget))
            }))
            (ok (get total-carbon product))
          )
          ;; Create budget if doesn't exist
          (begin
            (map-set consumer-budgets caller {
              monthly-budget: u10000, ;; Default 10kg CO2 monthly budget
              current-usage: (get total-carbon product),
              last-reset: current-height,
              total-offsets-purchased: u0
            })
            (ok (get total-carbon product))
          )
        )
      )
      ERR_PRODUCT_NOT_REGISTERED
    )
  )
)


;; Purchase carbon offsets
(define-public (purchase-carbon-offsets (amount uint))
  (let (
    (caller tx-sender)
    (cost (unwrap! (safe-mul amount (var-get carbon-credit-price)) ERR_OVERFLOW))
  )
    (try! (check-not-paused))
    (try! (check-rate-limit caller))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Mint carbon credits to user BEFORE transfer (reentrancy protection)
    (try! (ft-mint? carbon-credit amount caller))
    
    ;; Update total credits issued
    (var-set total-carbon-credits (unwrap! (safe-add (var-get total-carbon-credits) amount) ERR_OVERFLOW))
    
    ;; Update consumer's offset purchase record
    (match (map-get? consumer-budgets caller)
      budget (map-set consumer-budgets caller (merge budget {
        total-offsets-purchased: (unwrap! (safe-add (get total-offsets-purchased budget) amount) ERR_OVERFLOW)
      }))
      ;; Create budget record if doesn't exist
      (map-set consumer-budgets caller {
        monthly-budget: u10000,
        current-usage: u0,
        last-reset: block-height,
        total-offsets-purchased: amount
      })
    )
    
    ;; Transfer STX for carbon credits AFTER state updates (reentrancy protection)
    (try! (stx-transfer? cost caller CONTRACT_OWNER))
    
    (ok amount)
  )
)

;; Update retailer disclosure
(define-public (update-retailer-disclosure (total-products uint) (average-carbon uint))
  (let ((caller tx-sender))
    (try! (check-not-paused))
    (asserts! (> total-products u0) ERR_INVALID_AMOUNT)
    (asserts! (> average-carbon u0) ERR_INVALID_AMOUNT)
    (map-set retailer-disclosures caller {
      total-products: total-products,
      average-carbon-footprint: average-carbon,
      last-updated: block-height
    })
    (ok true)
  )
)

;; read only functions

;; Get product carbon footprint by QR code
(define-read-only (get-product-by-qr (qr-code-hash (buff 32)))
  (match (map-get? qr-codes qr-code-hash)
    product-id (map-get? products product-id)
    none
  )
)

;; Get product carbon footprint by ID
(define-read-only (get-product (product-id uint))
  (map-get? products product-id)
)

;; Get manufacturer info
(define-read-only (get-manufacturer (manufacturer principal))
  (map-get? manufacturers manufacturer)
)

;; Get logistics provider info
(define-read-only (get-logistics-provider (provider principal))
  (map-get? logistics-providers provider)
)

;; Get consumer carbon budget
(define-read-only (get-consumer-budget (consumer principal))
  (map-get? consumer-budgets consumer)
)

;; Get carbon submission status
(define-read-only (get-carbon-submission (submitter principal) (product-id uint) (submission-type (string-ascii 20)))
  (map-get? carbon-submissions {submitter: submitter, product-id: product-id, submission-type: submission-type})
)

;; Get retailer disclosure
(define-read-only (get-retailer-disclosure (retailer principal))
  (map-get? retailer-disclosures retailer)
)

;; Check if consumer is within carbon budget
(define-read-only (check-carbon-budget (consumer principal))
  (match (map-get? consumer-budgets consumer)
    budget (ok (<= (get current-usage budget) (get monthly-budget budget)))
    (ok true) ;; No budget set means no restrictions
  )
)

;; Get carbon credit price
(define-read-only (get-carbon-credit-price)
  (var-get carbon-credit-price)
)

;; Get total carbon credits issued
(define-read-only (get-total-carbon-credits)
  (var-get total-carbon-credits)
)

;; Get NFT owner
(define-read-only (get-nft-owner (product-id uint))
  (nft-get-owner? carbon-nft product-id)
)

;; Get consumer carbon credit balance
(define-read-only (get-carbon-credit-balance (account principal))
  (ft-get-balance carbon-credit account)
)

;; Security read-only functions
(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

(define-read-only (get-last-operation-block (user principal))
  (default-to u0 (map-get? last-operation-block user))
)

(define-read-only (is-manufacturer-verified (manufacturer principal))
  (match (map-get? manufacturers manufacturer)
    mfr (get is-verified mfr)
    false
  )
)

(define-read-only (is-logistics-verified (provider principal))
  (match (map-get? logistics-providers provider)
    prov (get is-verified prov)
    false
  )
)

;; private functions

;; Calculate total carbon footprint
(define-private (calculate-total-carbon (manufacturing uint) (logistics uint))
  (+ manufacturing logistics)
)

;; Check if participant is verified
(define-private (is-participant-verified (participant principal) (participant-type (string-ascii 20)))
  (if (is-eq participant-type "manufacturer")
    (match (map-get? manufacturers participant)
      manufacturer (get is-verified manufacturer)
      false
    )
    (if (is-eq participant-type "logistics")
      (match (map-get? logistics-providers participant)
        provider (get is-verified provider)
        false
      )
      false
    )
  )
)