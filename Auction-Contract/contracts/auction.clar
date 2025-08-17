;; NFT Auction Contract
;; Enable bidding on NFTs, with highest bid winning

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-auction-not-found (err u101))
(define-constant err-auction-ended (err u102))
(define-constant err-bid-too-low (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-auction-active (err u105))

;; Data structures
(define-map auctions 
  { nft-contract: principal, nft-id: uint }
  {
    seller: principal,
    highest-bidder: (optional principal),
    highest-bid: uint,
    end-block: uint,
    active: bool
  })

(define-map bidder-funds principal uint)

;; Function 1: Place Bid
;; Allows users to bid on an active NFT auction
(define-public (place-bid (nft-contract principal) (nft-id uint) (bid-amount uint))
  (let (
    (auction-key {nft-contract: nft-contract, nft-id: nft-id})
    (auction-data (unwrap! (map-get? auctions auction-key) err-auction-not-found))
  )
    (begin
      ;; Validate auction is active and not ended
      (asserts! (get active auction-data) err-auction-ended)
      (asserts! (< burn-block-height (get end-block auction-data)) err-auction-ended)
      (asserts! (> bid-amount u0) err-invalid-amount)
      (asserts! (> bid-amount (get highest-bid auction-data)) err-bid-too-low)
      
      ;; Transfer STX from bidder to contract
      (try! (stx-transfer? bid-amount tx-sender (as-contract tx-sender)))
      
      ;; Return previous highest bidder's funds if exists
      (match (get highest-bidder auction-data)
        previous-bidder
        (begin
          (try! (as-contract (stx-transfer? (get highest-bid auction-data) tx-sender previous-bidder)))
          (map-delete bidder-funds previous-bidder)
        )
        true
      )
      
      ;; Update auction with new highest bid
      (map-set auctions auction-key
        (merge auction-data {
          highest-bidder: (some tx-sender),
          highest-bid: bid-amount
        }))
      
      ;; Track bidder funds
      (map-set bidder-funds tx-sender bid-amount)
      
      (ok {
        nft-contract: nft-contract,
        nft-id: nft-id,
        new-highest-bid: bid-amount,
        bidder: tx-sender
      }))))

;; Function 2: End Auction
;; Ends the auction and transfers NFT to highest bidder, STX to seller
(define-public (end-auction (nft-contract principal) (nft-id uint))
  (let (
    (auction-key {nft-contract: nft-contract, nft-id: nft-id})
    (auction-data (unwrap! (map-get? auctions auction-key) err-auction-not-found))
  )
    (begin
      ;; Validate auction can be ended
      (asserts! (get active auction-data) err-auction-ended)
      (asserts! (>= burn-block-height (get end-block auction-data)) err-auction-active)
      
      ;; Check if there was a winning bid
      (match (get highest-bidder auction-data)
        winner
        (begin
          ;; Transfer NFT to winner (assuming NFT contract has transfer function)
          ;; Note: This would need to call the actual NFT contract's transfer function
          ;; (try! (contract-call? nft-contract transfer nft-id (get seller auction-data) winner))
          
          ;; Transfer STX to seller
          (try! (as-contract (stx-transfer? (get highest-bid auction-data) tx-sender (get seller auction-data))))
          
          ;; Clear bidder funds tracking
          (map-delete bidder-funds winner)
        )
        ;; No bids case - no transfers needed
        true
      )
      
      ;; Mark auction as ended
      (map-set auctions auction-key
        (merge auction-data {active: false}))
      
      (ok {
        nft-contract: nft-contract,
        nft-id: nft-id,
        winner: (get highest-bidder auction-data),
        winning-bid: (get highest-bid auction-data),
        seller: (get seller auction-data)
      }))))

;; Read-only functions for querying auction data
(define-read-only (get-auction-info (nft-contract principal) (nft-id uint))
  (map-get? auctions {nft-contract: nft-contract, nft-id: nft-id}))

(define-read-only (get-bidder-funds (bidder principal))
  (map-get? bidder-funds bidder))