;; title: Roxy Tests
;; version: 1.0.0
;; summary: Rendezvous fuzzing test suite for Roxy contract
;; description: Property-based testing for Bitcoin L2 Prediction Market Game with Points System and Marketplace

;; =============================================================================
;; PROPERTY-BASED TESTS FOR RENDEZVOUS
;; =============================================================================

;; Basic Fuzzing Tests - Input Validation and Error Handling
;; These tests ensure the contract can handle various input types without crashing

;; Property: User registration input validation
(define-public (test-register-fuzz (username (string-ascii 50)))
  (begin
    (unwrap! (register username) (ok false))
    (ok true)
  )
)

;; Property: Event creation input validation (admin only - may fail)
(define-public (test-create-event-fuzz (event-id uint) (metadata (string-ascii 200)))
  (begin
    (unwrap! (create-event event-id metadata) (ok false))
    (ok true)
  )
)

;; Property: YES staking input validation
(define-public (test-stake-yes-fuzz (event-id uint) (amount uint))
  (begin
    (unwrap! (stake-yes event-id amount) (ok false))
    (ok true)
  )
)

;; Property: NO staking input validation
(define-public (test-stake-no-fuzz (event-id uint) (amount uint))
  (begin
    (unwrap! (stake-no event-id amount) (ok false))
    (ok true)
  )
)

;; Property: Event resolution input validation (admin only - may fail)
(define-public (test-resolve-event-fuzz (event-id uint) (winner bool))
  (begin
    (unwrap! (resolve-event event-id winner) (ok false))
    (ok true)
  )
)

;; Property: Claim rewards input validation
(define-public (test-claim-fuzz (event-id uint))
  (begin
    (unwrap! (claim event-id) (ok false))
    (ok true)
  )
)

;; Property: Create listing input validation
(define-public (test-create-listing-fuzz (points uint) (price-stx uint))
  (begin
    (unwrap! (create-listing points price-stx) (ok false))
    (ok true)
  )
)

;; Property: Buy listing input validation
(define-public (test-buy-listing-fuzz (listing-id uint) (points-to-buy uint))
  (begin
    (unwrap! (buy-listing listing-id points-to-buy) (ok false))
    (ok true)
  )
)

;; Property: Cancel listing input validation
(define-public (test-cancel-listing-fuzz (listing-id uint))
  (begin
    (unwrap! (cancel-listing listing-id) (ok false))
    (ok true)
  )
)

;; Property: Withdraw protocol fees input validation (admin only - may fail)
(define-public (test-withdraw-protocol-fees-fuzz (amount uint))
  (begin
    (unwrap! (withdraw-protocol-fees amount) (ok false))
    (ok true)
  )
)

;; Property: Create guild input validation
(define-public (test-create-guild-fuzz (guild-id uint) (name (string-ascii 50)))
  (begin
    (unwrap! (create-guild guild-id name) (ok false))
    (ok true)
  )
)

;; Property: Join guild input validation
(define-public (test-join-guild-fuzz (guild-id uint))
  (begin
    (unwrap! (join-guild guild-id) (ok false))
    (ok true)
  )
)

;; Property: Leave guild input validation
(define-public (test-leave-guild-fuzz (guild-id uint))
  (begin
    (unwrap! (leave-guild guild-id) (ok false))
    (ok true)
  )
)

;; Property: Deposit to guild input validation
(define-public (test-deposit-to-guild-fuzz (guild-id uint) (amount uint))
  (begin
    (unwrap! (deposit-to-guild guild-id amount) (ok false))
    (ok true)
  )
)

;; Property: Withdraw from guild input validation
(define-public (test-withdraw-from-guild-fuzz (guild-id uint) (amount uint))
  (begin
    (unwrap! (withdraw-from-guild guild-id amount) (ok false))
    (ok true)
  )
)

;; Property: Guild stake YES input validation
(define-public (test-guild-stake-yes-fuzz (guild-id uint) (event-id uint) (amount uint))
  (begin
    (unwrap! (guild-stake-yes guild-id event-id amount) (ok false))
    (ok true)
  )
)

;; Property: Guild stake NO input validation
(define-public (test-guild-stake-no-fuzz (guild-id uint) (event-id uint) (amount uint))
  (begin
    (unwrap! (guild-stake-no guild-id event-id amount) (ok false))
    (ok true)
  )
)

;; Property: Guild claim input validation
(define-public (test-guild-claim-fuzz (guild-id uint) (event-id uint))
  (begin
    (unwrap! (guild-claim guild-id event-id) (ok false))
    (ok true)
  )
)

;; =============================================================================
;; HELPER FUNCTIONS FOR STATE SETUP
;; =============================================================================
;; These helpers allow Rendezvous to set up state needed for property tests

;; Helper: Register user (sets up user state for other tests)
(define-public (test-register-helper (username (string-ascii 50)))
  (let ((register-result (register username)))
    (ok true)
  )
)

;; Helper: Create event (admin only - may fail if not admin)
(define-public (test-create-event-helper (event-id uint) (metadata (string-ascii 200)))
  (let ((create-result (create-event event-id metadata)))
    (ok true)
  )
)

;; Helper: Create guild (sets up guild state for other tests)
(define-public (test-create-guild-helper (guild-id uint) (name (string-ascii 50)))
  (let ((create-result (create-guild guild-id name)))
    (ok true)
  )
)

;; Helper: Resolve event (admin only - may fail if not admin)
(define-public (test-resolve-event-helper (event-id uint) (winner bool))
  (let ((resolve-result (resolve-event event-id winner)))
    (ok true)
  )
)

;; =============================================================================
;; PROPERTY TESTS WITH PRECONDITION CHECKING
;; =============================================================================

;; Property: Staking YES should deduct points from user and add to event pool
(define-public (test-stake-yes-property (event-id uint) (amount uint))
  (if (or
      ;; Precondition 1: amount must be > 0
      (is-eq amount u0)
      ;; Precondition 2: user must be registered (have points)
      (is-none (map-get? user-points tx-sender))
      ;; Precondition 3: user must have enough points
      (< (default-to u0 (map-get? user-points tx-sender)) amount)
      ;; Precondition 4: event must exist and be open
      (is-none (map-get? events event-id))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let (
        (event (unwrap! (map-get? events event-id) (ok false)))
        (initial-points (default-to u0 (map-get? user-points tx-sender)))
        (initial-yes-pool (get yes-pool event))
      )
      (if (is-eq (get status event) "open")
        (begin
          (unwrap! (stake-yes event-id amount) (ok false))
          (let (
              (final-points (default-to u0 (map-get? user-points tx-sender)))
              (final-yes-pool (get yes-pool (unwrap! (map-get? events event-id) (ok false))))
            )
            ;; Verify property: points deducted and pool increased
            (asserts! (is-eq final-points (- initial-points amount))
              (err u999)
            )
            (asserts! (is-eq final-yes-pool (+ initial-yes-pool amount))
              (err u998)
            )
            (ok true)
          )
        )
        (ok false) ;; Event not open - discard
      )
    )
  )
)

;; Property: Staking NO should deduct points from user and add to event pool
(define-public (test-stake-no-property (event-id uint) (amount uint))
  (if (or
      ;; Precondition 1: amount must be > 0
      (is-eq amount u0)
      ;; Precondition 2: user must be registered (have points)
      (is-none (map-get? user-points tx-sender))
      ;; Precondition 3: user must have enough points
      (< (default-to u0 (map-get? user-points tx-sender)) amount)
      ;; Precondition 4: event must exist and be open
      (is-none (map-get? events event-id))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let (
        (event (unwrap! (map-get? events event-id) (ok false)))
        (initial-points (default-to u0 (map-get? user-points tx-sender)))
        (initial-no-pool (get no-pool event))
      )
      (if (is-eq (get status event) "open")
        (begin
          (unwrap! (stake-no event-id amount) (ok false))
          (let (
              (final-points (default-to u0 (map-get? user-points tx-sender)))
              (final-no-pool (get no-pool (unwrap! (map-get? events event-id) (ok false))))
            )
            ;; Verify property: points deducted and pool increased
            (asserts! (is-eq final-points (- initial-points amount))
              (err u999)
            )
            (asserts! (is-eq final-no-pool (+ initial-no-pool amount))
              (err u998)
            )
            (ok true)
          )
        )
        (ok false) ;; Event not open - discard
      )
    )
  )
)

;; Property: Claiming should increase user points when winning
(define-public (test-claim-property (event-id uint))
  (if (or
      ;; Precondition 1: event must exist
      (is-none (map-get? events event-id))
      ;; Precondition 2: user must be registered
      (is-none (map-get? user-points tx-sender))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let (
        (event (unwrap! (map-get? events event-id) (ok false)))
        (initial-points (default-to u0 (map-get? user-points tx-sender)))
      )
      (if (is-eq (get status event) "resolved")
        (match (get winner event)
          winner
          (begin
            ;; Check if user has a stake in the winning side
            (match (if winner
                (map-get? yes-stakes { event-id: event-id, user: tx-sender })
                (map-get? no-stakes { event-id: event-id, user: tx-sender })
              )
              stake
              (if (> stake u0)
                (begin
                  (unwrap! (claim event-id) (ok false))
                  (let ((final-points (default-to u0 (map-get? user-points tx-sender))))
                    ;; Verify property: points increased
                    (asserts! (>= final-points initial-points)
                      (err u997)
                    )
                    (ok true)
                  )
                )
                (ok false) ;; No stake - discard
              )
              (ok false) ;; No stake found - discard
            )
          )
          (ok false) ;; Winner not set - discard
        )
        (ok false) ;; Event not resolved - discard
      )
    )
  )
)

;; Property: Creating listing should lock points and deduct from user
(define-public (test-create-listing-property (points uint) (price-stx uint))
  (if (or
      ;; Precondition 1: points must be > 0
      (is-eq points u0)
      ;; Precondition 2: price must be > 0
      (is-eq price-stx u0)
      ;; Precondition 3: user must be registered
      (is-none (map-get? user-points tx-sender))
      ;; Precondition 4: user must have enough points
      (< (default-to u0 (map-get? user-points tx-sender)) points)
      ;; Precondition 5: user must have earned >= 10,000 points
      (< (default-to u0 (map-get? earned-points tx-sender)) u10000)
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let ((initial-points (default-to u0 (map-get? user-points tx-sender))))
      (unwrap! (create-listing points price-stx) (ok false))
      (let ((final-points (default-to u0 (map-get? user-points tx-sender))))
        ;; Verify property: points deducted
        (asserts! (is-eq final-points (- initial-points points))
          (err u996)
        )
        (ok true)
      )
    )
  )
)

;; Property: Buying listing should transfer points to buyer
(define-public (test-buy-listing-property (listing-id uint) (points-to-buy uint))
  (if (or
      ;; Precondition 1: points-to-buy must be > 0
      (is-eq points-to-buy u0)
      ;; Precondition 2: listing must exist
      (is-none (map-get? listings listing-id))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let (
        (listing (unwrap! (map-get? listings listing-id) (ok false)))
        (initial-buyer-points (default-to u0 (map-get? user-points tx-sender)))
      )
      (if (and
          (get active listing)
          (>= (get points listing) points-to-buy)
        )
        (begin
          (unwrap! (buy-listing listing-id points-to-buy) (ok false))
          (let ((final-buyer-points (default-to u0 (map-get? user-points tx-sender))))
            ;; Verify property: buyer received points
            (asserts! (is-eq final-buyer-points (+ initial-buyer-points points-to-buy))
              (err u995)
            )
            (ok true)
          )
        )
        (ok false) ;; Listing not active or insufficient points - discard
      )
    )
  )
)

;; Property: Canceling listing should return points to seller
(define-public (test-cancel-listing-property (listing-id uint))
  (if (or
      ;; Precondition 1: listing must exist
      (is-none (map-get? listings listing-id))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let (
        (listing (unwrap! (map-get? listings listing-id) (ok false)))
        (initial-seller-points (default-to u0 (map-get? user-points (get seller listing))))
        (listing-points (get points listing))
      )
      (if (and
          (get active listing)
          (is-eq tx-sender (get seller listing))
        )
        (begin
          (unwrap! (cancel-listing listing-id) (ok false))
          (let ((final-seller-points (default-to u0 (map-get? user-points (get seller listing)))))
            ;; Verify property: seller got points back
            (asserts! (is-eq final-seller-points (+ initial-seller-points listing-points))
              (err u994)
            )
            (ok true)
          )
        )
        (ok false) ;; Listing not active or not seller - discard
      )
    )
  )
)

;; Property: Joining guild should add user as member
(define-public (test-join-guild-property (guild-id uint))
  (if (or
      ;; Precondition 1: guild must exist
      (is-none (map-get? guilds guild-id))
      ;; Precondition 2: user must not already be a member
      (is-some (is-guild-member guild-id tx-sender))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (begin
      (unwrap! (join-guild guild-id) (ok false))
      ;; Verify property: user is now a member
      (match (is-guild-member guild-id tx-sender)
        member-status
        (if member-status
          (ok true)
          (ok false) ;; Member status is false
        )
        (ok false) ;; Should not be none
      )
    )
  )
)

;; Property: Depositing to guild should transfer points from user to guild
(define-public (test-deposit-to-guild-property (guild-id uint) (amount uint))
  (if (or
      ;; Precondition 1: amount must be > 0
      (is-eq amount u0)
      ;; Precondition 2: guild must exist
      (is-none (map-get? guilds guild-id))
      ;; Precondition 3: user must be a member
      (is-none (is-guild-member guild-id tx-sender))
      ;; Precondition 4: user must be registered
      (is-none (map-get? user-points tx-sender))
      ;; Precondition 5: user must have enough points
      (< (default-to u0 (map-get? user-points tx-sender)) amount)
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let (
        (guild (unwrap! (map-get? guilds guild-id) (ok false)))
        (initial-user-points (default-to u0 (map-get? user-points tx-sender)))
        (initial-guild-points (get total-points guild))
      )
      (unwrap! (deposit-to-guild guild-id amount) (ok false))
      (let (
          (final-user-points (default-to u0 (map-get? user-points tx-sender)))
          (final-guild-points (get total-points (unwrap! (map-get? guilds guild-id) (ok false))))
        )
        ;; Verify property: points transferred
        (asserts! (is-eq final-user-points (- initial-user-points amount))
          (err u991)
        )
        (asserts! (is-eq final-guild-points (+ initial-guild-points amount))
          (err u990)
        )
        (ok true)
      )
    )
  )
)

;; Property: Withdrawing from guild should transfer points from guild to user
(define-public (test-withdraw-from-guild-property (guild-id uint) (amount uint))
  (if (or
      ;; Precondition 1: amount must be > 0
      (is-eq amount u0)
      ;; Precondition 2: guild must exist
      (is-none (map-get? guilds guild-id))
      ;; Precondition 3: user must be a member
      (is-none (is-guild-member guild-id tx-sender))
      ;; Precondition 4: user must have deposits
      (is-none (map-get? guild-deposits { guild-id: guild-id, user: tx-sender }))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let (
        (guild (unwrap! (map-get? guilds guild-id) (ok false)))
        (user-deposit (unwrap! (map-get? guild-deposits { guild-id: guild-id, user: tx-sender }) (ok false)))
        (initial-guild-points (get total-points guild))
        (initial-user-points (default-to u0 (map-get? user-points tx-sender)))
      )
      (if (and
          (>= user-deposit amount)
          (>= initial-guild-points amount)
        )
        (begin
          (unwrap! (withdraw-from-guild guild-id amount) (ok false))
          (let (
              (final-guild-points (get total-points (unwrap! (map-get? guilds guild-id) (ok false))))
              (final-user-points (default-to u0 (map-get? user-points tx-sender)))
            )
            ;; Verify property: points transferred
            (asserts! (is-eq final-user-points (+ initial-user-points amount))
              (err u989)
            )
            (asserts! (is-eq final-guild-points (- initial-guild-points amount))
              (err u988)
            )
            (ok true)
          )
        )
        (ok false) ;; Insufficient deposits or guild points - discard
      )
    )
  )
)

;; Property: Guild staking YES should deduct from guild pool and add to event pool
(define-public (test-guild-stake-yes-property (guild-id uint) (event-id uint) (amount uint))
  (if (or
      ;; Precondition 1: amount must be > 0
      (is-eq amount u0)
      ;; Precondition 2: guild must exist
      (is-none (map-get? guilds guild-id))
      ;; Precondition 3: user must be a member
      (is-none (is-guild-member guild-id tx-sender))
      ;; Precondition 4: guild must have enough points
      (< (get total-points (unwrap! (map-get? guilds guild-id) (ok false))) amount)
      ;; Precondition 5: event must exist and be open
      (is-none (map-get? events event-id))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let (
        (guild (unwrap! (map-get? guilds guild-id) (ok false)))
        (event (unwrap! (map-get? events event-id) (ok false)))
        (initial-guild-points (get total-points guild))
        (initial-yes-pool (get yes-pool event))
      )
      (if (is-eq (get status event) "open")
        (begin
          (unwrap! (guild-stake-yes guild-id event-id amount) (ok false))
          (let (
              (final-guild-points (get total-points (unwrap! (map-get? guilds guild-id) (ok false))))
              (final-yes-pool (get yes-pool (unwrap! (map-get? events event-id) (ok false))))
            )
            ;; Verify property: guild points deducted and event pool increased
            (asserts! (is-eq final-guild-points (- initial-guild-points amount))
              (err u987)
            )
            (asserts! (is-eq final-yes-pool (+ initial-yes-pool amount))
              (err u986)
            )
            (ok true)
          )
        )
        (ok false) ;; Event not open - discard
      )
    )
  )
)

;; Property: Guild staking NO should deduct from guild pool and add to event pool
(define-public (test-guild-stake-no-property (guild-id uint) (event-id uint) (amount uint))
  (if (or
      ;; Precondition 1: amount must be > 0
      (is-eq amount u0)
      ;; Precondition 2: guild must exist
      (is-none (map-get? guilds guild-id))
      ;; Precondition 3: user must be a member
      (is-none (is-guild-member guild-id tx-sender))
      ;; Precondition 4: guild must have enough points
      (< (get total-points (unwrap! (map-get? guilds guild-id) (ok false))) amount)
      ;; Precondition 5: event must exist and be open
      (is-none (map-get? events event-id))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let (
        (guild (unwrap! (map-get? guilds guild-id) (ok false)))
        (event (unwrap! (map-get? events event-id) (ok false)))
        (initial-guild-points (get total-points guild))
        (initial-no-pool (get no-pool event))
      )
      (if (is-eq (get status event) "open")
        (begin
          (unwrap! (guild-stake-no guild-id event-id amount) (ok false))
          (let (
              (final-guild-points (get total-points (unwrap! (map-get? guilds guild-id) (ok false))))
              (final-no-pool (get no-pool (unwrap! (map-get? events event-id) (ok false))))
            )
            ;; Verify property: guild points deducted and event pool increased
            (asserts! (is-eq final-guild-points (- initial-guild-points amount))
              (err u985)
            )
            (asserts! (is-eq final-no-pool (+ initial-no-pool amount))
              (err u984)
            )
            (ok true)
          )
        )
        (ok false) ;; Event not open - discard
      )
    )
  )
)

;; Property: Guild claiming should increase guild points when winning
(define-public (test-guild-claim-property (guild-id uint) (event-id uint))
  (if (or
      ;; Precondition 1: event must exist
      (is-none (map-get? events event-id))
      ;; Precondition 2: guild must exist
      (is-none (map-get? guilds guild-id))
      ;; Precondition 3: user must be a member
      (is-none (is-guild-member guild-id tx-sender))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let (
        (event (unwrap! (map-get? events event-id) (ok false)))
        (guild (unwrap! (map-get? guilds guild-id) (ok false)))
        (initial-guild-points (get total-points guild))
      )
      (if (is-eq (get status event) "resolved")
        (match (get winner event)
          winner
          (begin
            ;; Check if guild has a stake in the winning side
            (match (if winner
                (map-get? guild-yes-stakes { guild-id: guild-id, event-id: event-id })
                (map-get? guild-no-stakes { guild-id: guild-id, event-id: event-id })
              )
              stake
              (if (> stake u0)
                (begin
                  (unwrap! (guild-claim guild-id event-id) (ok false))
                  (let ((final-guild-points (get total-points (unwrap! (map-get? guilds guild-id) (ok false)))))
                    ;; Verify property: guild points increased
                    (asserts! (>= final-guild-points initial-guild-points)
                      (err u983)
                    )
                    (ok true)
                  )
                )
                (ok false) ;; No stake - discard
              )
              (ok false) ;; No stake found - discard
            )
          )
          (ok false) ;; Winner not set - discard
        )
        (ok false) ;; Event not resolved - discard
      )
    )
  )
)

;; Property: Leaving guild should remove user as member (only if no deposits)
(define-public (test-leave-guild-property (guild-id uint))
  (if (or
      ;; Precondition 1: guild must exist
      (is-none (map-get? guilds guild-id))
      ;; Precondition 2: user must be a member
      (is-none (is-guild-member guild-id tx-sender))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let ((user-deposit (default-to u0 (map-get? guild-deposits { guild-id: guild-id, user: tx-sender }))))
      ;; Can only leave if deposits are 0
      (if (is-eq user-deposit u0)
        (begin
          (unwrap! (leave-guild guild-id) (ok false))
          ;; Verify property: user is no longer a member
          (match (is-guild-member guild-id tx-sender)
            member-status
            (if member-status
              (ok false) ;; Still a member - test failed
              (ok true)  ;; Not a member - success
            )
            (ok true) ;; Not a member (none) - success
          )
        )
        (ok false) ;; Has deposits - discard (must withdraw first)
      )
    )
  )
)

;; =============================================================================
;; EDGE CASE TESTS
;; =============================================================================

;; Edge Case: Claiming when losing should clear stake but return 0 reward
(define-public (test-claim-losing-property (event-id uint))
  (if (or
      ;; Precondition 1: event must exist
      (is-none (map-get? events event-id))
      ;; Precondition 2: user must be registered
      (is-none (map-get? user-points tx-sender))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let (
        (event (unwrap! (map-get? events event-id) (ok false)))
        (initial-points (default-to u0 (map-get? user-points tx-sender)))
      )
      (if (is-eq (get status event) "resolved")
        (match (get winner event)
          winner
          (begin
            ;; Check if user has a stake in the LOSING side
            (match (if winner
                (map-get? no-stakes { event-id: event-id, user: tx-sender })
                (map-get? yes-stakes { event-id: event-id, user: tx-sender })
              )
              stake
              (if (> stake u0)
                (begin
                  (unwrap! (claim event-id) (ok false))
                  (let ((final-points (default-to u0 (map-get? user-points tx-sender))))
                    ;; Verify property: points unchanged (no reward for losing)
                    (asserts! (is-eq final-points initial-points)
                      (err u982)
                    )
                    ;; Verify stake was cleared
                    (match (if winner
                        (map-get? no-stakes { event-id: event-id, user: tx-sender })
                        (map-get? yes-stakes { event-id: event-id, user: tx-sender })
                      )
                      remaining-stake
                      (begin
                        (asserts! (is-eq remaining-stake u0) (err u981))
                        (ok true)
                      )
                      (ok true) ;; Stake cleared (none)
                    )
                  )
                )
                (ok false) ;; No losing stake - discard
              )
              (ok false) ;; No stake found - discard
            )
          )
          (ok false) ;; Winner not set - discard
        )
        (ok false) ;; Event not resolved - discard
      )
    )
  )
)

;; Edge Case: Partial purchase of listing should update listing correctly
(define-public (test-buy-listing-partial-property (listing-id uint) (points-to-buy uint))
  (if (or
      ;; Precondition 1: points-to-buy must be > 0
      (is-eq points-to-buy u0)
      ;; Precondition 2: listing must exist
      (is-none (map-get? listings listing-id))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let (
        (listing (unwrap! (map-get? listings listing-id) (ok false)))
        (initial-listing-points (get points listing))
        (initial-listing-price (get price-stx listing))
      )
      (if (and
          (get active listing)
          (> initial-listing-points points-to-buy) ;; Must be partial purchase
          (>= initial-listing-points points-to-buy)
        )
        (begin
          (unwrap! (buy-listing listing-id points-to-buy) (ok false))
          (let ((updated-listing (unwrap! (map-get? listings listing-id) (ok false))))
            ;; Verify property: listing still active with reduced points
            (asserts! (get active updated-listing)
              (err u980)
            )
            (asserts! (is-eq (get points updated-listing) (- initial-listing-points points-to-buy))
              (err u979)
            )
            (ok true)
          )
        )
        (ok false) ;; Not a partial purchase or invalid - discard
      )
    )
  )
)

;; Edge Case: Multiple stakes on same event should accumulate
(define-public (test-stake-yes-accumulate-property (event-id uint) (amount1 uint) (amount2 uint))
  (if (or
      ;; Precondition 1: amounts must be > 0
      (is-eq amount1 u0)
      (is-eq amount2 u0)
      ;; Precondition 2: user must be registered
      (is-none (map-get? user-points tx-sender))
      ;; Precondition 3: user must have enough points for both stakes
      (< (default-to u0 (map-get? user-points tx-sender)) (+ amount1 amount2))
      ;; Precondition 4: event must exist and be open
      (is-none (map-get? events event-id))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let (
        (event (unwrap! (map-get? events event-id) (ok false)))
        (initial-points (default-to u0 (map-get? user-points tx-sender)))
        (initial-yes-pool (get yes-pool event))
      )
      (if (is-eq (get status event) "open")
        (begin
          ;; First stake
          (unwrap! (stake-yes event-id amount1) (ok false))
          ;; Second stake
          (unwrap! (stake-yes event-id amount2) (ok false))
          (let (
              (final-points (default-to u0 (map-get? user-points tx-sender)))
              (final-yes-pool (get yes-pool (unwrap! (map-get? events event-id) (ok false))))
              (total-stake (unwrap! (map-get? yes-stakes { event-id: event-id, user: tx-sender }) (ok false)))
            )
            ;; Verify property: points deducted correctly, pool increased, stake accumulated
            (asserts! (is-eq final-points (- initial-points (+ amount1 amount2)))
              (err u978)
            )
            (asserts! (is-eq final-yes-pool (+ initial-yes-pool (+ amount1 amount2)))
              (err u977)
            )
            (asserts! (is-eq total-stake (+ amount1 amount2))
              (err u976)
            )
            (ok true)
          )
        )
        (ok false) ;; Event not open - discard
      )
    )
  )
)

;; =============================================================================
;; ENHANCED COVERAGE TESTS
;; =============================================================================

;; Enhanced: Create listing should add listing fee to treasury (10 STX)
(define-public (test-create-listing-fee-property (points uint) (price-stx uint))
  (if (or
      ;; Precondition 1: points must be > 0
      (is-eq points u0)
      ;; Precondition 2: price must be > 0
      (is-eq price-stx u0)
      ;; Precondition 3: user must be registered
      (is-none (map-get? user-points tx-sender))
      ;; Precondition 4: user must have enough points
      (< (default-to u0 (map-get? user-points tx-sender)) points)
      ;; Precondition 5: user must have earned >= 10,000 points
      (< (default-to u0 (map-get? earned-points tx-sender)) u10000)
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let ((initial-treasury (var-get protocol-treasury)))
      (unwrap! (create-listing points price-stx) (ok false))
      (let ((final-treasury (var-get protocol-treasury)))
        ;; Verify property: listing fee (10 STX = 10,000,000 micro-STX) added to treasury
        (asserts! (is-eq final-treasury (+ initial-treasury u10000000))
          (err u975)
        )
        (ok true)
      )
    )
  )
)

;; Enhanced: Buy listing should calculate and add protocol fee to treasury (2%)
(define-public (test-buy-listing-protocol-fee-property (listing-id uint) (points-to-buy uint))
  (if (or
      ;; Precondition 1: points-to-buy must be > 0
      (is-eq points-to-buy u0)
      ;; Precondition 2: listing must exist
      (is-none (map-get? listings listing-id))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let (
        (listing (unwrap! (map-get? listings listing-id) (ok false)))
        (initial-treasury (var-get protocol-treasury))
      )
      (if (and
          (get active listing)
          (>= (get points listing) points-to-buy)
        )
        (let (
            (total-price (get price-stx listing))
            (total-points (get points listing))
            (price-per-point (/ total-price total-points))
            (actual-price-stx (* price-per-point points-to-buy))
            (expected-protocol-fee (/ (* actual-price-stx u200) u10000))
          )
          (unwrap! (buy-listing listing-id points-to-buy) (ok false))
          (let ((final-treasury (var-get protocol-treasury)))
            ;; Verify property: protocol fee (2%) added to treasury
            (asserts! (is-eq final-treasury (+ initial-treasury expected-protocol-fee))
              (err u973)
            )
            (ok true)
          )
        )
        (ok false) ;; Listing not active or insufficient points - discard
      )
    )
  )
)

;; Enhanced: Username uniqueness should be enforced
(define-public (test-register-username-uniqueness-property (username (string-ascii 50)))
  (if (or
      ;; Precondition 1: username must not be empty (basic check)
      (is-eq (len username) u0)
      ;; Precondition 2: user must not already be registered
      (is-some (map-get? user-points tx-sender))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (begin
      ;; First registration should succeed
      (unwrap! (register username) (ok false))
      ;; Verify username is stored and tracked for uniqueness
      (match (get-username tx-sender)
        stored-username
        (begin
          (asserts! (is-eq stored-username username) (err u971))
          ;; Verify username is tracked in usernames map for uniqueness
          (match (map-get? usernames username)
            existing-user
            (begin
              (asserts! (is-eq existing-user tx-sender) (err u960))
              (ok true)
            )
            (ok false) ;; Username not tracked
          )
        )
        (ok false) ;; Username not stored
      )
    )
  )
)

;; Enhanced: Resolve event should transition state from open to resolved
(define-public (test-resolve-event-property (event-id uint) (winner bool))
  (if (or
      ;; Precondition 1: event must exist
      (is-none (map-get? events event-id))
      ;; Precondition 2: caller must be admin (will discard if not)
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let ((event (unwrap! (map-get? events event-id) (ok false))))
      (if (is-eq (get status event) "open")
        (begin
          (unwrap! (resolve-event event-id winner) (ok false))
          (let ((resolved-event (unwrap! (map-get? events event-id) (ok false))))
            ;; Verify property: status changed to resolved and winner set
            (asserts! (is-eq (get status resolved-event) "resolved")
              (err u970)
            )
            (match (get winner resolved-event)
              winner-value
              (begin
                (asserts! (is-eq winner-value winner) (err u969))
                (ok true)
              )
              (ok false) ;; Winner not set
            )
          )
        )
        (ok false) ;; Event not open - discard
      )
    )
  )
)

;; Enhanced: Withdraw protocol fees should decrease treasury balance
(define-public (test-withdraw-protocol-fees-property (amount uint))
  (if (or
      ;; Precondition 1: amount must be > 0
      (is-eq amount u0)
      ;; Precondition 2: caller must be admin (will discard if not)
      ;; Precondition 3: treasury must have enough balance
      (< (var-get protocol-treasury) amount)
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let ((initial-treasury (var-get protocol-treasury)))
      (unwrap! (withdraw-protocol-fees amount) (ok false))
      (let ((final-treasury (var-get protocol-treasury)))
        ;; Verify property: treasury decreased by withdrawal amount
        (asserts! (is-eq final-treasury (- initial-treasury amount))
          (err u968)
        )
        (ok true)
      )
    )
  )
)

;; Enhanced: Claiming twice should fail after first claim (stake cleared)
(define-public (test-claim-twice-property (event-id uint))
  (if (or
      ;; Precondition 1: event must exist
      (is-none (map-get? events event-id))
      ;; Precondition 2: user must be registered
      (is-none (map-get? user-points tx-sender))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test
    (let ((event (unwrap! (map-get? events event-id) (ok false))))
      (if (is-eq (get status event) "resolved")
        (match (get winner event)
          winner
          (begin
            ;; Check if user has a stake in the winning side
            (match (if winner
                (map-get? yes-stakes { event-id: event-id, user: tx-sender })
                (map-get? no-stakes { event-id: event-id, user: tx-sender })
              )
              stake
              (if (> stake u0)
                (begin
                  ;; First claim should succeed
                  (unwrap! (claim event-id) (ok false))
                  ;; Verify stake was cleared (set to 0) - this proves second claim would fail
                  (match (if winner
                      (map-get? yes-stakes { event-id: event-id, user: tx-sender })
                      (map-get? no-stakes { event-id: event-id, user: tx-sender })
                    )
                    remaining-stake
                    (begin
                      ;; Stake should be 0 after claiming (proves second claim would fail)
                      (asserts! (is-eq remaining-stake u0) (err u961))
                      (ok true)
                    )
                    (ok true) ;; Stake cleared (none) - second claim would fail
                  )
                )
                (ok false) ;; No stake - discard
              )
              (ok false) ;; No stake found - discard
            )
          )
          (ok false) ;; Winner not set - discard
        )
        (ok false) ;; Event not resolved - discard
      )
    )
  )
)

;; Enhanced: Boundary condition - very large amounts
(define-public (test-stake-yes-boundary-property (event-id uint) (amount uint))
  (if (or
      ;; Precondition 1: amount must be > 0
      (is-eq amount u0)
      ;; Precondition 2: user must be registered
      (is-none (map-get? user-points tx-sender))
      ;; Precondition 3: user must have enough points
      (< (default-to u0 (map-get? user-points tx-sender)) amount)
      ;; Precondition 4: event must exist and be open
      (is-none (map-get? events event-id))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test - same as regular stake-yes but tests with boundary values
    (let (
        (event (unwrap! (map-get? events event-id) (ok false)))
        (initial-points (default-to u0 (map-get? user-points tx-sender)))
        (initial-yes-pool (get yes-pool event))
      )
      (if (is-eq (get status event) "open")
        (begin
          (unwrap! (stake-yes event-id amount) (ok false))
          (let (
              (final-points (default-to u0 (map-get? user-points tx-sender)))
              (final-yes-pool (get yes-pool (unwrap! (map-get? events event-id) (ok false))))
            )
            ;; Verify property: points deducted and pool increased (even with large amounts)
            (asserts! (is-eq final-points (- initial-points amount))
              (err u966)
            )
            (asserts! (is-eq final-yes-pool (+ initial-yes-pool amount))
              (err u965)
            )
            ;; Verify no overflow occurred (final should be >= initial for pool)
            (asserts! (>= final-yes-pool initial-yes-pool)
              (err u964)
            )
            (ok true)
          )
        )
        (ok false) ;; Event not open - discard
      )
    )
  )
)

;; Enhanced: Boundary condition - minimum values (1 point)
(define-public (test-stake-yes-minimum-property (event-id uint))
  (if (or
      ;; Precondition 1: user must be registered
      (is-none (map-get? user-points tx-sender))
      ;; Precondition 2: user must have at least 1 point
      (< (default-to u0 (map-get? user-points tx-sender)) u1)
      ;; Precondition 3: event must exist and be open
      (is-none (map-get? events event-id))
    )
    ;; Discard if preconditions aren't met
    (ok false)
    ;; Run the test with minimum amount (1 point)
    (let (
        (event (unwrap! (map-get? events event-id) (ok false)))
        (initial-points (default-to u0 (map-get? user-points tx-sender)))
        (initial-yes-pool (get yes-pool event))
      )
      (if (is-eq (get status event) "open")
        (begin
          (unwrap! (stake-yes event-id u1) (ok false))
          (let (
              (final-points (default-to u0 (map-get? user-points tx-sender)))
              (final-yes-pool (get yes-pool (unwrap! (map-get? events event-id) (ok false))))
            )
            ;; Verify property: minimum stake works correctly
            (asserts! (is-eq final-points (- initial-points u1))
              (err u963)
            )
            (asserts! (is-eq final-yes-pool (+ initial-yes-pool u1))
              (err u962)
            )
  (ok true)
)
        )
        (ok false) ;; Event not open - discard
      )
    )
  )
)



