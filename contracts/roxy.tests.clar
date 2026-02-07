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

;; Property: Campaign lifecycle creation
(define-public (test-campaign-creation-property (metadata-hash (buff 32)) (reporter principal) (start-time uint) (end-time uint))
  (if (or 
      (<= end-time start-time)
      (not (is-standard reporter))
    )
    (ok false)
    (begin
      (let ((campaign-id (unwrap! (create-campaign metadata-hash reporter start-time end-time) (ok false))))
        (let ((campaign (unwrap! (map-get? campaigns campaign-id) (ok false))))
          (asserts! (is-eq (get creator campaign) tx-sender) (err u910))
          (asserts! (is-eq (get end-time campaign) end-time) (err u911))
          (ok true)
        )
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
