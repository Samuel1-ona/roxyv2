;; title: Roxy Tests
;; version: 2.1.0
;; summary: Rendezvous fuzzing test suite for Roxy contract
;; description: Property-based testing for STX-Based Gaming Prediction SDK

;; =============================================================================
;; PROPERTY-BASED TESTS FOR RENDEZVOUS
;; =============================================================================

;; Property: User registration (set-username) input validation
(define-public (test-set-username-fuzz (username (string-ascii 50)))
  (begin
    (unwrap! (set-username username) (ok false))
    (ok true)
  )
)

;; Property: Campaign creation input validation
(define-public (test-create-campaign-fuzz (metadata-hash (buff 32)) (reporter principal) (start-time uint) (end-time uint))
  (begin
    (unwrap! (create-campaign metadata-hash reporter start-time end-time) (ok false))
    (ok true)
  )
)

;; Property/Helper: Join campaign
(define-public (test-join-campaign-fuzz (campaign-id uint) (referrer (optional principal)))
  (begin
    (unwrap! (join-campaign campaign-id referrer) (ok false))
    (ok true)
  )
)

;; Property: Match creation
(define-public (test-create-match-fuzz (campaign-id uint) (metadata (string-ascii 200)))
  (begin
    (unwrap! (create-match campaign-id metadata) (ok false))
    (ok true)
  )
)

;; Property: Staking
(define-public (test-stake-fuzz (event-id uint) (amount uint) (is-yes bool))
  (begin
    (unwrap! (stake event-id amount is-yes) (ok false))
    (ok true)
  )
)

;; Property: Resolve match
(define-public (test-resolve-match-fuzz (event-id uint) (winner-is-yes bool))
  (begin
    (unwrap! (resolve-match event-id winner-is-yes) (ok false))
    (ok true)
  )
)

;; Property: Claim reward
(define-public (test-claim-reward-fuzz (event-id uint))
  (begin
    (unwrap! (claim-reward event-id) (ok false))
    (ok true)
  )
)

;; =============================================================================
;; PROPERTY TESTS WITH PRECONDITION CHECKING
;; =============================================================================

;; Property: Username uniqueness
(define-public (test-username-uniqueness-property (username (string-ascii 50)))
  (if (or 
      (is-eq username "")
      (is-some (map-get? usernames username))
    )
    (ok false)
    (begin
      (unwrap! (set-username username) (ok false))
      (let ((profile (unwrap! (map-get? user-profiles tx-sender) (ok false))))
        (asserts! (is-eq (get username profile) username) (err u901))
        (asserts! (is-eq (map-get? usernames username) (some tx-sender)) (err u902))
        (ok true)
      )
    )
  )
)

;; Property: Staking increases pools
(define-public (test-staking-pool-property (event-id uint) (amount uint) (is-yes bool))
  (let ((event-opt (map-get? events event-id)))
    (if (or 
        (is-none event-opt)
        (is-eq amount u0)
      )
      (ok false)
      (let ((event (unwrap-panic event-opt)))
        (if (not (is-eq (get status event) "open"))
          (ok false)
          (let ((initial-yes (get yes-pool event)) (initial-no (get no-pool event)))
            (unwrap! (stake event-id amount is-yes) (ok false))
            (let ((final-event (unwrap! (map-get? events event-id) (ok false))))
              (if is-yes
                (asserts! (is-eq (get yes-pool final-event) (+ initial-yes amount)) (err u920))
                (asserts! (is-eq (get no-pool final-event) (+ initial-no amount)) (err u921))
              )
              (ok true)
            )
          )
        )
      )
    )
  )
)

;; =============================================================================
;; SYSTEM INVARIANTS
;; =============================================================================

;; @desc Error code for paused protocol
(define-constant ERR-PAUSED u10)

;; @desc Property: create-campaign should fail when paused
(define-public (prop-pause-halting (paused bool))
  (begin
    (try! (set-paused paused))
    (let ((res (create-campaign 0x0101010101010101010101010101010101010101010101010101010101010101 tx-sender u100 u200)))
      (if paused
        (asserts! (is-eq res (err ERR-PAUSED)) (err u1001))
        (asserts! (is-ok res) (err u1002))
      )
      ;; Reset for next test
      (try! (set-paused false))
      (ok true)
    )
  )
)

;; @desc Property: 2-step admin handoff integrity
(define-public (prop-admin-handoff (new-admin principal))
  (begin
    (asserts! (is-standard new-admin) (ok true)) ;; Skip non-standard for this
    (try! (propose-admin new-admin))
    ;; Check current admin is still tx-sender
    (asserts! (is-eq (unwrap-panic (get-admin)) tx-sender) (err u1003))
    ;; Reset for next test (since we can't easily claim in Rendezvous without changing tx-sender context)
    (ok true)
  )
)

;; @desc Invariant: Treasury must always be backed by contract balance
(define-public (invariant-treasury-backing)
  (let ((treasury (unwrap-panic (get-protocol-treasury))))
    (asserts! (>= (stx-get-balance (as-contract tx-sender)) treasury) (err u901))
    (ok true)
  )
)

;; Invariant: User profile mapping consistency
(define-public (test-invariant-profile-sync)
  (match (map-get? user-profiles tx-sender)
    profile (let ((username (get username profile)))
      (asserts! (is-eq (map-get? usernames username) (some tx-sender)) (err u951))
      (ok true)
    )
    (ok true)
  )
)

;; =============================================================================
;; EDGE CASE FUZZING
;; =============================================================================

;; Edge: Staking zero amount must fail
(define-public (test-stake-zero-edge (event-id uint))
  (let ((res (stake event-id u0 true)))
    (asserts! (is-err res) (err u960))
    (ok true)
  )
)

;; Edge: Invalid campaign times must fail
(define-public (test-campaign-invalid-times-edge (start-uint uint))
  (let ((res (create-campaign 0x0101010101010101010101010101010101010101010101010101010101010101 tx-sender start-uint start-uint)))
    (asserts! (is-err res) (err u961))
    (ok true)
  )
)

;; Edge: Unauthorized status update must fail
(define-public (test-unauthorized-campaign-status-edge (campaign-id uint) (new-status (string-ascii 20)))
  (let ((campaign-opt (map-get? campaigns campaign-id)))
    (if (is-none campaign-opt)
      (ok false)
      (let ((campaign (unwrap-panic campaign-opt)))
        (if (is-eq tx-sender (get creator campaign))
          (ok false) ;; Skip if we are the creator (valid case)
          (let ((res (update-campaign-status campaign-id new-status)))
            (asserts! (is-eq res (err u3)) (err u962)) ;; ERR-UNAUTHORIZED
            (ok true)
          )
        )
      )
    )
  )
)
