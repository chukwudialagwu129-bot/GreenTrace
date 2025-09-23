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

;; data vars
(define-data-var next-product-id uint u1)
(define-data-var total-carbon-credits uint u0)
(define-data-var carbon-credit-price uint u1000000) ;; 1 STX per credit

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


;; public functions

;; Register as manufacturer
(define-public (register-manufacturer (name (string-ascii 50)) (certification (string-ascii 100)))
  (let ((caller tx-sender))
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

;; Verify manufacturer or logistics provider (contract owner only)
(define-public (verify-participant (participant principal) (participant-type (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (if (is-eq participant-type "manufacturer")
      (match (map-get? manufacturers participant)
        manufacturer (map-set manufacturers participant (merge manufacturer {is-verified: true}))
        ERR_NOT_FOUND
      )
      (if (is-eq participant-type "logistics")
        (match (map-get? logistics-providers participant)
          provider (map-set logistics-providers participant (merge provider {is-verified: true}))
          ERR_NOT_FOUND
        )
        ERR_INVALID_PARTICIPANT
      )
    )
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
    ;; Check if caller is verified manufacturer
    (match (map-get? manufacturers caller)
      manufacturer (asserts! (get is-verified manufacturer) ERR_NOT_AUTHORIZED)
      ERR_NOT_AUTHORIZED
    )
    
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
    (var-set next-product-id (+ product-id u1))
    
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
    ;; Check if caller is verified logistics provider
    (match (map-get? logistics-providers caller)
      provider (asserts! (get is-verified provider) ERR_NOT_AUTHORIZED)
      ERR_NOT_AUTHORIZED
    )
    
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
            (match (map-get? products product-id)
              product (map-set products product-id (merge product {
                is-verified: true
              }))
              ERR_PRODUCT_NOT_REGISTERED
            )
            (if (is-eq submission-type "logistics")
              (match (map-get? products product-id)
                product (let ((new-total (+ (get manufacturing-carbon product) (get carbon-amount submission))))
                  (map-set products product-id (merge product {
                    logistics-carbon: (get carbon-amount submission),
                    total-carbon: new-total
                  }))
                )
                ERR_PRODUCT_NOT_REGISTERED
              )
              ERR_INVALID_PARTICIPANT
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