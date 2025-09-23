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
