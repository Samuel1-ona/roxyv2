;; title: roxy
;; version: 2.1.0
;; summary: STX-Based Gaming Prediction SDK with Advanced Features
;; description: A platform for game developers to create campaigns, manage predictions, and track leaderboards with referrals and access gating.

;; ============================================================================
;; TRAITS
;; ============================================================================

(use-trait roxy-game-trait .roxy-trait.roxy-game-trait)

;; ============================================================================
;; CONSTANTS & ERRORS
;; ============================================================================

(define-constant BPS_DENOMINATOR u10000)
(define-constant ERR-NOT-ADMIN (err u1))
(define-constant ERR-NOT-FOUND (err u2))
(define-constant ERR-UNAUTHORIZED (err u3))
(define-constant ERR-INVALID-AMOUNT (err u4))
(define-constant ERR-CAMPAIGN-EXPIRED (err u5))
(define-constant ERR-INSUFFICIENT-FUNDS (err u6))
(define-constant ERR-ALREADY-PARTICIPATED (err u7))
(define-constant ERR-EVENT-NOT-OPEN (err u8))
(define-constant ERR-EVENT-CLOSED (err u9))
(define-constant ERR-REFERRAL-SELF (err u10))

;; ============================================================================
;; DATA VARIABLES
;; ============================================================================

(define-data-var admin principal tx-sender)
(define-data-var campaign-creation-fee uint u10000000) ;; 10 STX
(define-data-var stx-per-usd uint u1000000) ;; Default 1 STX = $1 (adjust via admin/oracle)
(define-data-var next-campaign-id uint u1)
(define-data-var next-event-id uint u1)
(define-data-var protocol-treasury uint u0)

;; ============================================================================
;; DATA MAPS
;; ============================================================================

(define-map user-profiles
  principal
  { username: (string-ascii 50) }
)

(define-map campaigns
  uint
  {
    creator: principal,
    metadata-hash: (buff 32),
    prize-pool: uint,
    reporter: principal,
    start-time: uint,
    end-time: uint,
    status: (string-ascii 20),
  }
)

(define-map campaign-participants
  {
    campaign-id: uint,
    user: principal,
  }
  bool
)

(define-map referrals
  {
    campaign-id: uint,
    user: principal,
  }
  principal
)

(define-map leaderboard
  {
    campaign-id: uint,
    user: principal,
  }
  uint
)

(define-map events
  uint
  {
    campaign-id: uint,
    yes-pool: uint,
    no-pool: uint,
    status: (string-ascii 20),
    winner: (optional bool),
    metadata: (string-ascii 200),
  }
)

(define-map yes-stakes
  {
    event-id: uint,
    user: principal,
  }
  uint
)

(define-map no-stakes
  {
    event-id: uint,
    user: principal,
  }
  uint
)

;; ============================================================================
;; PUBLIC FUNCTIONS - CAMPAIGN & SDK
;; ============================================================================

(define-public (create-campaign
    (metadata-hash (buff 32))
    (reporter principal)
    (start-time uint)
    (end-time uint)
  )
  (let (
      (campaign-id (var-get next-campaign-id))
      (creation-fee (var-get campaign-creation-fee))
    )
    ;; Pay creation fee to protocol treasury
    (try! (stx-transfer? creation-fee tx-sender (as-contract tx-sender)))
    (var-set protocol-treasury (+ (var-get protocol-treasury) creation-fee))

    (map-set campaigns campaign-id {
      creator: tx-sender,
      metadata-hash: metadata-hash,
      prize-pool: u0,
      reporter: reporter,
      start-time: start-time,
      end-time: end-time,
      status: "open",
    })

    (var-set next-campaign-id (+ campaign-id u1))
    (ok campaign-id)
  )
)

(define-public (join-campaign
    (campaign-id uint)
    (referrer (optional principal))
  )
  (let (
      (campaign (unwrap! (map-get? campaigns campaign-id) ERR-NOT-FOUND))
      (fee (var-get stx-per-usd)) ;; $1 in micro-STX
    )
    (asserts!
      (is-none (map-get? campaign-participants {
        campaign-id: campaign-id,
        user: tx-sender,
      }))
      ERR-ALREADY-PARTICIPATED
    )

    ;; Pay join fee
    (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))

    ;; Handle Referral (10% to referrer, 90% to prize pool)
    (let (
        (referral-amount (/ fee u10))
        (caller tx-sender)
        (pool-addition (match referrer
          ref (if (not (is-eq ref caller))
            (begin
              (try! (as-contract (stx-transfer? referral-amount tx-sender ref)))
              (map-set referrals {
                campaign-id: campaign-id,
                user: caller,
              }
                ref
              )
              (- fee referral-amount)
            )
            fee
          )
          fee
        ))
      )
      ;; Update Campaign Prize Pool
      (map-set campaigns campaign-id
        (merge campaign { prize-pool: (+ (get prize-pool campaign) pool-addition) })
      )

      ;; Register participation
      (map-set campaign-participants {
        campaign-id: campaign-id,
        user: tx-sender,
      }
        true
      )
      (ok true)
    )
  )
)

;; SDK Sync Function
(define-public (sync-score
    (campaign-id uint)
    (player principal)
    (game-contract <roxy-game-trait>)
  )
  (let ((campaign (unwrap! (map-get? campaigns campaign-id) ERR-NOT-FOUND)))
    (asserts! (is-eq (contract-of game-contract) (get reporter campaign))
      ERR-UNAUTHORIZED
    )

    (let ((score (try! (contract-call? game-contract get-player-score campaign-id player))))
      (map-set leaderboard {
        campaign-id: campaign-id,
        user: player,
      }
        score
      )
      (ok score)
    )
  )
)

;; ============================================================================
;; PUBLIC FUNCTIONS - PREDICTIONS
;; ============================================================================

(define-public (create-match
    (campaign-id uint)
    (metadata (string-ascii 200))
  )
  (let ((event-id (var-get next-event-id)))
    (let ((campaign (unwrap! (map-get? campaigns campaign-id) ERR-NOT-FOUND)))
      ;; Only campaign creator or reporter can create matches
      (asserts!
        (or (is-eq tx-sender (get creator campaign)) (is-eq tx-sender (get reporter campaign)))
        ERR-UNAUTHORIZED
      )

      (map-set events event-id {
        campaign-id: campaign-id,
        yes-pool: u0,
        no-pool: u0,
        status: "open",
        winner: none,
        metadata: metadata,
      })

      (var-set next-event-id (+ event-id u1))
      (ok event-id)
    )
  )
)

(define-public (stake
    (event-id uint)
    (amount uint)
    (is-yes bool)
  )
  (let ((event (unwrap! (map-get? events event-id) ERR-NOT-FOUND)))
    (asserts! (is-eq (get status event) "open") ERR-EVENT-NOT-OPEN)

    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

    (if is-yes
      (begin
        (map-set events event-id
          (merge event { yes-pool: (+ (get yes-pool event) amount) })
        )
        (let ((current-stake (default-to u0
            (map-get? yes-stakes {
              event-id: event-id,
              user: tx-sender,
            })
          )))
          (map-set yes-stakes {
            event-id: event-id,
            user: tx-sender,
          }
            (+ current-stake amount)
          )
        )
      )
      (begin
        (map-set events event-id
          (merge event { no-pool: (+ (get no-pool event) amount) })
        )
        (let ((current-stake (default-to u0
            (map-get? no-stakes {
              event-id: event-id,
              user: tx-sender,
            })
          )))
          (map-set no-stakes {
            event-id: event-id,
            user: tx-sender,
          }
            (+ current-stake amount)
          )
        )
      )
    )
    (ok true)
  )
)

(define-public (resolve-match
    (event-id uint)
    (winner-is-yes bool)
  )
  (let ((event (unwrap! (map-get? events event-id) ERR-NOT-FOUND)))
    (let ((campaign (unwrap! (map-get? campaigns (get campaign-id event)) ERR-NOT-FOUND)))
      (asserts! (is-eq tx-sender (get reporter campaign)) ERR-UNAUTHORIZED)
      (map-set events event-id
        (merge event {
          status: "resolved",
          winner: (some winner-is-yes),
        })
      )
      (ok true)
    )
  )
)

(define-public (claim-reward (event-id uint))
  (let ((event (unwrap! (map-get? events event-id) ERR-NOT-FOUND)))
    (asserts! (is-eq (get status event) "resolved") ERR-EVENT-CLOSED)

    (let (
        (is-yes-winner (unwrap! (get winner event) ERR-NOT-FOUND))
        (yes-pool (get yes-pool event))
        (no-pool (get no-pool event))
        (total-pool (+ yes-pool no-pool))
      )
      (if is-yes-winner
        (let (
            (recipient tx-sender)
            (user-stake (unwrap!
              (map-get? yes-stakes {
                event-id: event-id,
                user: recipient,
              })
              ERR-NOT-FOUND
            ))
          )
          (let ((reward (/ (* user-stake total-pool) yes-pool)))
            (map-set yes-stakes {
              event-id: event-id,
              user: recipient,
            }
              u0
            )
            (as-contract (stx-transfer? reward tx-sender recipient))
          )
        )
        (let (
            (recipient tx-sender)
            (user-stake (unwrap!
              (map-get? no-stakes {
                event-id: event-id,
                user: recipient,
              })
              ERR-NOT-FOUND
            ))
          )
          (let ((reward (/ (* user-stake total-pool) no-pool)))
            (map-set no-stakes {
              event-id: event-id,
              user: recipient,
            }
              u0
            )
            (as-contract (stx-transfer? reward tx-sender recipient))
          )
        )
      )
    )
  )
)

;; ============================================================================
;; ADMIN FUNCTIONS
;; ============================================================================

(define-public (withdraw-treasury (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-ADMIN)
    (asserts! (<= amount (var-get protocol-treasury)) ERR-INSUFFICIENT-FUNDS)
    (var-set protocol-treasury (- (var-get protocol-treasury) amount))
    (as-contract (stx-transfer? amount tx-sender (var-get admin)))
  )
)

(define-public (set-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-ADMIN)
    (ok (var-set admin new-admin))
  )
)
