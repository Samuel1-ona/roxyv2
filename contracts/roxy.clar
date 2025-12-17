;; title: roxy
;; version: 1.0.0
;; summary: Bitcoin L2 Prediction Market Game with Points System and Marketplace
;; description: A collaborative prediction market where users predict outcomes, earn points, and trade points on a marketplace

;; traits
;;

;; token definitions
;;

;; constants
(define-constant STARTING_POINTS u1000)
(define-constant MIN_EARNED_FOR_SELL u10000)
(define-constant LISTING_FEE u10000000) ;; 10 STX in micro-STX
(define-constant PROTOCOL_FEE_BPS u200) ;; 2% = 200 basis points
(define-constant BPS_DENOMINATOR u10000)

;; error constants
(define-constant ERR-USER-ALREADY-REGISTERED (err u1))
(define-constant ERR-NOT-ADMIN (err u2))
(define-constant ERR-EVENT-ID-EXISTS (err u3))
(define-constant ERR-INVALID-AMOUNT (err u4))
(define-constant ERR-EVENT-NOT-OPEN (err u5))
(define-constant ERR-INSUFFICIENT-POINTS (err u6))
(define-constant ERR-USER-NOT-REGISTERED (err u7))
(define-constant ERR-EVENT-NOT-FOUND (err u8))
(define-constant ERR-EVENT-MUST-BE-OPEN (err u9))
(define-constant ERR-EVENT-MUST-BE-RESOLVED (err u10))
(define-constant ERR-NO-WINNERS (err u11))
(define-constant ERR-NO-STAKE-FOUND (err u12))
(define-constant ERR-WINNER-NOT-SET (err u13))
(define-constant ERR-INSUFFICIENT-EARNED-POINTS (err u14))
(define-constant ERR-LISTING-NOT-ACTIVE (err u15))
(define-constant ERR-LISTING-NOT-FOUND (err u16))
(define-constant ERR-ONLY-SELLER-CAN-CANCEL (err u17))
(define-constant ERR-INSUFFICIENT-AVAILABLE-POINTS (err u18))
(define-constant ERR-GUILD-ID-EXISTS (err u19))
(define-constant ERR-GUILD-NOT-FOUND (err u20))
(define-constant ERR-ALREADY-A-MEMBER (err u21))
(define-constant ERR-NOT-A-MEMBER (err u22))
(define-constant ERR-HAS-DEPOSITS (err u23))
(define-constant ERR-INSUFFICIENT-DEPOSITS (err u24))
(define-constant ERR-INSUFFICIENT-TREASURY (err u25))
(define-constant ERR-USERNAME-TAKEN (err u26))

;; data vars
(define-data-var admin principal tx-sender)
(define-data-var next-event-id uint u1)
(define-data-var next-listing-id uint u1)
(define-data-var protocol-treasury uint u0)
(define-data-var total-yes-stakes uint u0) ;; Total YES stakes across all events
(define-data-var total-no-stakes uint u0) ;; Total NO stakes across all events
(define-data-var total-guild-yes-stakes uint u0) ;; Total guild YES stakes across all events
(define-data-var total-guild-no-stakes uint u0) ;; Total guild NO stakes across all events
(define-data-var total-admin-minted-points uint u0) ;; Total points minted by admin
(define-constant ADMIN_POINT_PRICE u1000) ;; 1000 micro-STX per point (1 STX = 1000 points)

;; data maps
;; User Point System
(define-map user-points
  principal
  uint
)
(define-map earned-points
  principal
  uint
)
;; Points earned from predictions (used for selling threshold)
(define-map user-names
  principal
  (string-ascii 50)
)
;; User names
(define-map usernames
  (string-ascii 50)
  principal
)
;; Track username for uniqueness (username -> user)

;; Prediction Event Registry
(define-map events
  uint
  {
    yes-pool: uint,
    no-pool: uint,
    status: (string-ascii 20), ;; "open", "closed", "resolved"
    winner: (optional bool),
    creator: principal,
    metadata: (string-ascii 200),
  }
)

;; User Staking System
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

;; Point Marketplace
(define-map listings
  uint
  {
    seller: principal,
    points: uint,
    price-stx: uint,
    active: bool,
  }
)

;; Transaction Log (for event tracking - Clarity doesn't have native events)
;; Maps: (block-height, tx-index) -> transaction log entry
(define-data-var next-log-id uint u1)
(define-map transaction-logs
  uint
  {
    action: (string-ascii 30), ;; "register", "create-event", "stake-yes", "stake-no", "resolve", "claim", "create-listing", "buy-listing", "cancel-listing"
    user: principal,
    event-id: (optional uint),
    listing-id: (optional uint),
    amount: (optional uint),
    metadata: (string-ascii 200),
  }
)

;; Guild System (Collaborative Predictions)
(define-data-var next-guild-id uint u1)
(define-map guilds
  uint
  {
    creator: principal,
    name: (string-ascii 50),
    total-points: uint,
    member-count: uint,
  }
)
(define-map guild-members
  {
    guild-id: uint,
    user: principal,
  }
  bool
)
;; Is user a member of guild
(define-map guild-deposits
  {
    guild-id: uint,
    user: principal,
  }
  uint
)
;; User's contribution to guild pool
(define-map guild-yes-stakes
  {
    guild-id: uint,
    event-id: uint,
  }
  uint
)
;; Guild's YES stake on event
(define-map guild-no-stakes
  {
    guild-id: uint,
    event-id: uint,
  }
  uint
)
;; Guild's NO stake on event

;; Leaderboard System
;; User Leaderboard Statistics
(define-map user-stats
  principal
  {
    total-predictions: uint,
    wins: uint,
    losses: uint,
    total-points-earned: uint,
    win-rate: uint, ;; Stored as percentage (0-10000, where 10000 = 100%)
  }
)

;; Guild Leaderboard Statistics
(define-map guild-stats
  uint
  {
    total-predictions: uint,
    wins: uint,
    losses: uint,
    total-points-earned: uint,
    win-rate: uint, ;; Stored as percentage (0-10000, where 10000 = 100%)
  }
)

;; public functions

;; ============================================================================
;; 1. register (username)
;; ============================================================================
;; Purpose: Register a new user in the system.
;;
;; Details:
;;   - Takes a username (up to 50 ASCII characters)
;;   - Checks if the user is already registered (error u1 if yes)
;;   - Checks if the username is already taken (error u26 if yes)
;;   - Grants 1,000 starting points (non-sellable)
;;   - Sets earned-points to 0 (starting points don't count toward selling threshold)
;;   - Stores the username and tracks it for uniqueness
;;   - Returns (ok true) on success
;;
;; Use case: First-time user onboarding.
;;
;; Parameters:
;;   - username: (string-ascii 50) - User's chosen username (must be unique)
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-USER-ALREADY-REGISTERED if user already registered
;;   - ERR-USERNAME-TAKEN if username is already taken by another user
;; ============================================================================
(define-public (register (username (string-ascii 50)))
  (let ((user tx-sender))
    (match (map-get? user-points user)
      existing
      ERR-USER-ALREADY-REGISTERED ;; User already registered
      (begin
        ;; Track username for uniqueness
        (match (map-get? usernames username)
          existing-user
          ERR-USERNAME-TAKEN ;; Username already taken
          (begin
            (map-set user-points user STARTING_POINTS)
            (map-set earned-points user u0) ;; Starting points don't count as earned
            (map-set user-names user username)
            (map-set usernames username user) ;; Store username -> user mapping for uniqueness
            ;; Emit event
            (print {
              event: "user-registered",
              user: user,
              username: username,
              points: STARTING_POINTS,
            })
            ;; Log transaction
            (let ((log-id (var-get next-log-id)))
              (map-set transaction-logs log-id {
                action: "register",
                user: user,
                event-id: none,
                listing-id: none,
                amount: (some STARTING_POINTS),
                metadata: username,
              })
              (var-set next-log-id (+ log-id u1))
            )
            (ok true)
          )
        )
      )
    )
  )
)

;; ============================================================================
;; 2. create-event (event-id, metadata)
;; ============================================================================
;; Purpose: Create a new prediction event (admin only).
;;
;; Details:
;;   - Verifies caller is admin (error u2 if not)
;;   - Checks if event ID already exists (error u3 if yes)
;;   - Initializes event with:
;;     * yes-pool: 0, no-pool: 0
;;     * status: "open"
;;     * winner: none
;;     * creator: admin
;;     * metadata: provided metadata
;;   - Returns (ok true) on success
;;
;; Use case: Admin creates prediction events (e.g., "Will Bitcoin reach $100k by 2025?").
;;
;; Parameters:
;;   - event-id: uint - Unique identifier for the event
;;   - metadata: (string-ascii 200) - Event description/metadata
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-NOT-ADMIN if caller is not admin
;;   - ERR-EVENT-ID-EXISTS if event ID already exists
;; ============================================================================
(define-public (create-event
    (event-id uint)
    (metadata (string-ascii 200))
  )
  (let ((caller tx-sender))
    (asserts! (is-eq caller (var-get admin)) ERR-NOT-ADMIN)
    ;; Only admin can create events
    (match (map-get? events event-id)
      existing
      ERR-EVENT-ID-EXISTS ;; Event ID already exists
      (begin
        (map-set events event-id {
          yes-pool: u0,
          no-pool: u0,
          status: "open",
          winner: none,
          creator: caller,
          metadata: metadata,
        })
        ;; Emit event
        (print {
          event: "event-created",
          event-id: event-id,
          creator: caller,
          metadata: metadata,
        })
        ;; Log transaction
        (let ((log-id (var-get next-log-id)))
          (map-set transaction-logs log-id {
            action: "create-event",
            user: caller,
            event-id: (some event-id),
            listing-id: none,
            amount: none,
            metadata: metadata,
          })
          (var-set next-log-id (+ log-id u1))
        )
        (ok true)
      )
    )
  )
)

;; ============================================================================
;; 3. stake-yes (event-id, amount)
;; ============================================================================
;; Purpose: Stake points on the YES outcome of an event.
;;
;; Details:
;;   - Validates amount > 0 (error u4)
;;   - Verifies event exists and is "open" (errors u8, u5)
;;   - Checks user has enough points (error u6)
;;   - Deducts points from user balance
;;   - Adds points to the event's YES pool
;;   - Records/updates the user's YES stake for the event
;;   - Returns (ok true) on success
;;
;; Use case: User predicts "YES" on an event.
;;
;; Parameters:
;;   - event-id: uint - The event to stake on
;;   - amount: uint - Number of points to stake
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-INVALID-AMOUNT if amount <= 0
;;   - ERR-EVENT-NOT-OPEN if event is not open
;;   - ERR-INSUFFICIENT-POINTS if insufficient points
;;   - ERR-USER-NOT-REGISTERED if user not registered
;;   - ERR-EVENT-NOT-FOUND if event not found
;; ============================================================================
(define-public (stake-yes
    (event-id uint)
    (amount uint)
  )
  (let ((user tx-sender))
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    ;; Amount must be greater than 0
    (match (map-get? events event-id)
      event
      (begin
        (asserts! (is-eq (get status event) "open") ERR-EVENT-NOT-OPEN) ;; Event must be open
        (match (map-get? user-points user)
          current-points
          (begin
            (asserts! (>= current-points amount) ERR-INSUFFICIENT-POINTS) ;; Insufficient points
            ;; Deduct points from user
            (map-set user-points user (- current-points amount))
            ;; Add to YES pool
            (let (
                (new-yes-pool (+ (get yes-pool event) amount))
                (new-no-pool (get no-pool event))
              )
              (map-set events event-id {
                yes-pool: new-yes-pool,
                no-pool: new-no-pool,
                status: (get status event),
                winner: (get winner event),
                creator: (get creator event),
                metadata: (get metadata event),
              })
              ;; Record user's stake
              (match (map-get? yes-stakes {
                event-id: event-id,
                user: user,
              })
                existing-stake (map-set yes-stakes {
                  event-id: event-id,
                  user: user,
                }
                  (+ existing-stake amount)
                )
                (begin
                  (map-set yes-stakes {
                    event-id: event-id,
                    user: user,
                  }
                    amount
                  )
                  ;; Track new prediction for leaderboard
                  (match (map-get? user-stats user)
                    stats (map-set user-stats user {
                      total-predictions: (+ (get total-predictions stats) u1),
                      wins: (get wins stats),
                      losses: (get losses stats),
                      total-points-earned: (get total-points-earned stats),
                      win-rate: (get win-rate stats),
                    })
                    (map-set user-stats user {
                      total-predictions: u1,
                      wins: u0,
                      losses: u0,
                      total-points-earned: u0,
                      win-rate: u0,
                    })
                  )
                )
              )
              ;; Update total YES stakes
              (var-set total-yes-stakes (+ (var-get total-yes-stakes) amount))
              ;; Emit event
              (print {
                event: "staked-yes",
                event-id: event-id,
                user: user,
                amount: amount,
                yes-pool: new-yes-pool,
                no-pool: new-no-pool,
              })
              ;; Log transaction
              (let ((log-id (var-get next-log-id)))
                (map-set transaction-logs log-id {
                  action: "stake-yes",
                  user: user,
                  event-id: (some event-id),
                  listing-id: none,
                  amount: (some amount),
                  metadata: "stake-yes",
                })
                (var-set next-log-id (+ log-id u1))
              )
              (ok true)
            )
          )
          ERR-USER-NOT-REGISTERED ;; User not registered
        )
      )
      ERR-EVENT-NOT-FOUND ;; Event not found
    )
  )
)

;; ============================================================================
;; 4. stake-no (event-id, amount)
;; ============================================================================
;; Purpose: Stake points on the NO outcome of an event.
;;
;; Details:
;;   - Same logic as stake-yes, but:
;;     * Adds to the NO pool instead
;;     * Records stake in no-stakes map
;;   - Returns (ok true) on success
;;
;; Use case: User predicts "NO" on an event.
;;
;; Parameters:
;;   - event-id: uint - The event to stake on
;;   - amount: uint - Number of points to stake
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-INVALID-AMOUNT if amount <= 0
;;   - ERR-EVENT-NOT-OPEN if event is not open
;;   - ERR-INSUFFICIENT-POINTS if insufficient points
;;   - ERR-USER-NOT-REGISTERED if user not registered
;;   - ERR-EVENT-NOT-FOUND if event not found
;; ============================================================================
(define-public (stake-no
    (event-id uint)
    (amount uint)
  )
  (let ((user tx-sender))
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    ;; Amount must be greater than 0
    (match (map-get? events event-id)
      event
      (begin
        (asserts! (is-eq (get status event) "open") ERR-EVENT-NOT-OPEN) ;; Event must be open
        (match (map-get? user-points user)
          current-points
          (begin
            (asserts! (>= current-points amount) ERR-INSUFFICIENT-POINTS) ;; Insufficient points
            ;; Deduct points from user
            (map-set user-points user (- current-points amount))
            ;; Add to NO pool
            (let (
                (new-yes-pool (get yes-pool event))
                (new-no-pool (+ (get no-pool event) amount))
              )
              (map-set events event-id {
                yes-pool: new-yes-pool,
                no-pool: new-no-pool,
                status: (get status event),
                winner: (get winner event),
                creator: (get creator event),
                metadata: (get metadata event),
              })
              ;; Record user's stake
              (match (map-get? no-stakes {
                event-id: event-id,
                user: user,
              })
                existing-stake (map-set no-stakes {
                  event-id: event-id,
                  user: user,
                }
                  (+ existing-stake amount)
                )
                (begin
                  (map-set no-stakes {
                    event-id: event-id,
                    user: user,
                  }
                    amount
                  )
                  ;; Track new prediction for leaderboard
                  (match (map-get? user-stats user)
                    stats (map-set user-stats user {
                      total-predictions: (+ (get total-predictions stats) u1),
                      wins: (get wins stats),
                      losses: (get losses stats),
                      total-points-earned: (get total-points-earned stats),
                      win-rate: (get win-rate stats),
                    })
                    (map-set user-stats user {
                      total-predictions: u1,
                      wins: u0,
                      losses: u0,
                      total-points-earned: u0,
                      win-rate: u0,
                    })
                  )
                )
              )
              ;; Update total NO stakes
              (var-set total-no-stakes (+ (var-get total-no-stakes) amount))
              ;; Emit event
              (print {
                event: "staked-no",
                event-id: event-id,
                user: user,
                amount: amount,
                yes-pool: new-yes-pool,
                no-pool: new-no-pool,
              })
              ;; Log transaction
              (let ((log-id (var-get next-log-id)))
                (map-set transaction-logs log-id {
                  action: "stake-no",
                  user: user,
                  event-id: (some event-id),
                  listing-id: none,
                  amount: (some amount),
                  metadata: "stake-yes",
                })
                (var-set next-log-id (+ log-id u1))
              )
              (ok true)
            )
          )
          ERR-USER-NOT-REGISTERED ;; User not registered
        )
      )
      ERR-EVENT-NOT-FOUND ;; Event not found
    )
  )
)

;; ============================================================================
;; 5. resolve-event (event-id, winner)
;; ============================================================================
;; Purpose: Mark an event as resolved and set the winner (admin only).
;;
;; Details:
;;   - Verifies caller is admin (error u2)
;;   - Verifies event exists (error u8)
;;   - Verifies event is "open" (error u9)
;;   - Sets status: "resolved" and winner: (some winner)
;;   - Returns (ok true) on success
;;
;; Use case: Admin resolves an event after the outcome is known.
;;
;; Parameters:
;;   - event-id: uint - The event to resolve
;;   - winner: bool - true if YES won, false if NO won
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-NOT-ADMIN if caller is not admin
;;   - ERR-EVENT-NOT-FOUND if event not found
;;   - ERR-EVENT-MUST-BE-OPEN if event must be open to resolve
;; ============================================================================
(define-public (resolve-event
    (event-id uint)
    (winner bool)
  )
  (let ((caller tx-sender))
    (asserts! (is-eq caller (var-get admin)) ERR-NOT-ADMIN)
    ;; Only admin can resolve
    (match (map-get? events event-id)
      event
      (begin
        (asserts! (is-eq (get status event) "open") ERR-EVENT-MUST-BE-OPEN) ;; Event must be open to resolve
        (let (
            (yes-pool (get yes-pool event))
            (no-pool (get no-pool event))
          )
          (map-set events event-id {
            yes-pool: yes-pool,
            no-pool: no-pool,
            status: "resolved",
            winner: (some winner),
            creator: (get creator event),
            metadata: (get metadata event),
          })
          ;; Log transaction
          (let (
              (log-id (var-get next-log-id))
              (winner-str (if winner
                "yes"
                "no"
              ))
            )
            (map-set transaction-logs log-id {
              action: "resolve",
              user: caller,
              event-id: (some event-id),
              listing-id: none,
              amount: none,
              metadata: (if winner
                "winner-yes"
                "winner-no"
              ),
            })
            (var-set next-log-id (+ log-id u1))
          )
          (ok true)
        )
      )
      ERR-EVENT-NOT-FOUND ;; Event not found
    )
  )
)

;; ============================================================================
;; 6. claim (event-id)
;; ============================================================================
;; Purpose: Claim rewards from a resolved event if the user won.
;;
;; Details:
;;   - Verifies event exists and is "resolved" (errors u8, u10)
;;   - Verifies winner is set (error u13)
;;   - Calculates:
;;     * total-pool = yes-pool + no-pool
;;     * winning-pool = yes-pool if winner is true, else no-pool
;;     * reward = (user_stake * total_pool) / winning_pool
;;     * This ensures better precision with integer division
;;   - If the user has a stake in the winning side:
;;     * Adds reward to user-points
;;     * Adds reward to earned-points (counts toward selling threshold)
;;     * Clears the stake (sets to 0)
;;     * Returns (ok reward) with the reward amount
;;
;; Errors:
;;   - u11 if winning pool is empty
;;   - u12 if user has no stake or stake is 0
;;   - u7 if user not registered
;;
;; Use case: Winner claims their share of the pool.
;;
;; Parameters:
;;   - event-id: uint - The event to claim rewards from
;;
;; Returns:
;;   - (ok reward) with reward amount on success
;;   - ERR-USER-NOT-REGISTERED if user not registered
;;   - ERR-EVENT-NOT-FOUND if event not found
;;   - ERR-EVENT-MUST-BE-RESOLVED if event must be resolved
;;   - ERR-NO-WINNERS if no winners (pool is empty)
;;   - ERR-NO-STAKE-FOUND if no stake found
;;   - ERR-WINNER-NOT-SET if winner not set
;; ============================================================================
(define-public (claim (event-id uint))
  (let ((user tx-sender))
    (match (map-get? events event-id)
      event
      (begin
        (asserts! (is-eq (get status event) "resolved")
          ERR-EVENT-MUST-BE-RESOLVED
        )
        ;; Event must be resolved
        (match (get winner event)
          winner
          (begin
            (let (
                (yes-pool (get yes-pool event))
                (no-pool (get no-pool event))
                (total-pool (+ yes-pool no-pool))
                (winning-pool (if winner
                  yes-pool
                  no-pool
                ))
              )
              (if (is-eq winning-pool u0)
                ERR-NO-WINNERS ;; No winners (pool is empty)
                (begin
                  (if winner
                    ;; User staked YES
                    (match (map-get? yes-stakes {
                      event-id: event-id,
                      user: user,
                    })
                      stake
                      (begin
                        (if (> stake u0)
                          (let ((reward (/ (* stake total-pool) winning-pool)))
                            ;; Add reward to user points
                            (match (map-get? user-points user)
                              current-points
                              (begin
                                (let ((new-total-points (+ current-points reward)))
                                  (map-set user-points user new-total-points)
                                  ;; Update earned points for selling threshold
                                  (match (map-get? earned-points user)
                                    current-earned (begin
                                      (let ((new-earned-points (+ current-earned reward)))
                                        (map-set earned-points user
                                          new-earned-points
                                        )
                                        ;; Update total YES stakes (subtract before clearing)
                                        (var-set total-yes-stakes
                                          (- (var-get total-yes-stakes) stake)
                                        )
                                        ;; Clear the stake
                                        (map-set yes-stakes {
                                          event-id: event-id,
                                          user: user,
                                        }
                                          u0
                                        )
                                        ;; Update leaderboard stats (WIN)
                                        (match (map-get? user-stats user)
                                          stats (begin
                                            (let (
                                                (new-wins (+ (get wins stats) u1))
                                                (new-total-earned (+
                                                  (get total-points-earned stats)
                                                  reward
                                                ))
                                                (new-win-rate (/ (* new-wins u10000)
                                                  (+ new-wins (get losses stats))
                                                ))
                                              )
                                              (map-set user-stats user {
                                                total-predictions: (get total-predictions stats),
                                                wins: new-wins,
                                                losses: (get losses stats),
                                                total-points-earned: new-total-earned,
                                                win-rate: new-win-rate,
                                              })
                                            )
                                          )
                                          (map-set user-stats user {
                                            total-predictions: u1,
                                            wins: u1,
                                            losses: u0,
                                            total-points-earned: reward,
                                            win-rate: u10000,
                                          })
                                        )
                                        ;; Emit event
                                        (print {
                                          event: "reward-claimed",
                                          event-id: event-id,
                                          user: user,
                                          reward: reward,
                                          total-points: new-total-points,
                                          earned-points: new-earned-points,
                                        })
                                        ;; Log transaction
                                        (let ((log-id (var-get next-log-id)))
                                          (map-set transaction-logs log-id {
                                            action: "claim",
                                            user: user,
                                            event-id: (some event-id),
                                            listing-id: none,
                                            amount: (some reward),
                                            metadata: "reward-claimed",
                                          })
                                          (var-set next-log-id (+ log-id u1))
                                        )
                                        (ok reward)
                                      )
                                    )
                                    (begin
                                      (map-set earned-points user reward)
                                      ;; Update total YES stakes (subtract before clearing)
                                      (var-set total-yes-stakes
                                        (- (var-get total-yes-stakes) stake)
                                      )
                                      ;; Clear the stake
                                      (map-set yes-stakes {
                                        event-id: event-id,
                                        user: user,
                                      }
                                        u0
                                      )
                                      ;; Update leaderboard stats (WIN)
                                      (match (map-get? user-stats user)
                                        stats (begin
                                          (let (
                                              (new-wins (+ (get wins stats) u1))
                                              (new-total-earned (+ (get total-points-earned stats)
                                                reward
                                              ))
                                              (new-win-rate (/ (* new-wins u10000)
                                                (+ new-wins (get losses stats))
                                              ))
                                            )
                                            (map-set user-stats user {
                                              total-predictions: (get total-predictions stats),
                                              wins: new-wins,
                                              losses: (get losses stats),
                                              total-points-earned: new-total-earned,
                                              win-rate: new-win-rate,
                                            })
                                          )
                                        )
                                        (map-set user-stats user {
                                          total-predictions: u1,
                                          wins: u1,
                                          losses: u0,
                                          total-points-earned: reward,
                                          win-rate: u10000,
                                        })
                                      )
                                      ;; Emit event
                                      (print {
                                        event: "reward-claimed",
                                        event-id: event-id,
                                        user: user,
                                        reward: reward,
                                        total-points: new-total-points,
                                        earned-points: reward,
                                      })
                                      ;; Log transaction
                                      (let ((log-id (var-get next-log-id)))
                                        (map-set transaction-logs log-id {
                                          action: "claim",
                                          user: user,
                                          event-id: (some event-id),
                                          listing-id: none,
                                          amount: (some reward),
                                          metadata: "reward-claimed",
                                        })
                                        (var-set next-log-id (+ log-id u1))
                                      )
                                      (ok reward)
                                    )
                                  )
                                )
                              )
                              ERR-USER-NOT-REGISTERED ;; User not registered
                            )
                          )
                          (begin
                            ;; Check if user had NO stake (they lost)
                            (match (map-get? no-stakes {
                              event-id: event-id,
                              user: user,
                            })
                              no-stake
                              (begin
                                (if (> no-stake u0)
                                  (begin
                                    ;; User had NO stake but YES won - clear stake and track loss
                                    ;; Update total NO stakes (subtract before clearing)
                                    (var-set total-no-stakes
                                      (- (var-get total-no-stakes) no-stake)
                                    )
                                    (map-set no-stakes {
                                      event-id: event-id,
                                      user: user,
                                    }
                                      u0
                                    )
                                    ;; Update leaderboard stats (LOSS)
                                    (match (map-get? user-stats user)
                                      stats (begin
                                        (let (
                                            (new-losses (+ (get losses stats) u1))
                                            (total-games (+ (get wins stats) new-losses))
                                            (new-win-rate (if (is-eq total-games u0)
                                              u0
                                              (/ (* (get wins stats) u10000)
                                                total-games
                                              )
                                            ))
                                          )
                                          (map-set user-stats user {
                                            total-predictions: (get total-predictions stats),
                                            wins: (get wins stats),
                                            losses: new-losses,
                                            total-points-earned: (get total-points-earned stats),
                                            win-rate: new-win-rate,
                                          })
                                        )
                                      )
                                      (map-set user-stats user {
                                        total-predictions: u1,
                                        wins: u0,
                                        losses: u1,
                                        total-points-earned: u0,
                                        win-rate: u0,
                                      })
                                    )
                                    ;; Return success with 0 reward to indicate loss tracked (state changes persist)
                                    (ok u0)
                                  )
                                  ERR-NO-STAKE-FOUND ;; No stake found
                                )
                              )
                              ERR-NO-STAKE-FOUND ;; No stake found
                            )
                          )
                        )
                      )
                      ERR-NO-STAKE-FOUND ;; No stake found
                    )
                    ;; User staked NO
                    (let ((no-stake-opt (map-get? no-stakes {
                        event-id: event-id,
                        user: user,
                      })))
                      (if (is-some no-stake-opt)
                        (let ((stake (unwrap! no-stake-opt ERR-NO-STAKE-FOUND)))
                          (if (> stake u0)
                            (let ((reward (/ (* stake total-pool) winning-pool)))
                              ;; Add reward to user points
                              (match (map-get? user-points user)
                                current-points
                                (begin
                                  (let ((new-total-points (+ current-points reward)))
                                    (map-set user-points user new-total-points)
                                    ;; Update earned points for selling threshold
                                    (match (map-get? earned-points user)
                                      current-earned (begin
                                        (let ((new-earned-points (+ current-earned reward)))
                                          (map-set earned-points user
                                            new-earned-points
                                          )
                                          ;; Update total NO stakes (subtract before clearing)
                                          (var-set total-no-stakes
                                            (- (var-get total-no-stakes) stake)
                                          )
                                          ;; Clear the stake
                                          (map-set no-stakes {
                                            event-id: event-id,
                                            user: user,
                                          }
                                            u0
                                          )
                                          ;; Update leaderboard stats (WIN)
                                          (match (map-get? user-stats user)
                                            stats (begin
                                              (let (
                                                  (new-wins (+ (get wins stats) u1))
                                                  (new-total-earned (+
                                                    (get total-points-earned
                                                      stats
                                                    )
                                                    reward
                                                  ))
                                                  (new-win-rate (/ (* new-wins u10000)
                                                    (+ new-wins
                                                      (get losses stats)
                                                    )))
                                                )
                                                (map-set user-stats user {
                                                  total-predictions: (get total-predictions stats),
                                                  wins: new-wins,
                                                  losses: (get losses stats),
                                                  total-points-earned: new-total-earned,
                                                  win-rate: new-win-rate,
                                                })
                                              )
                                            )
                                            (map-set user-stats user {
                                              total-predictions: u1,
                                              wins: u1,
                                              losses: u0,
                                              total-points-earned: reward,
                                              win-rate: u10000,
                                            })
                                          )
                                          ;; Emit event
                                          (print {
                                            event: "reward-claimed",
                                            event-id: event-id,
                                            user: user,
                                            reward: reward,
                                            total-points: new-total-points,
                                            earned-points: new-earned-points,
                                          })
                                          ;; Log transaction
                                          (let ((log-id (var-get next-log-id)))
                                            (map-set transaction-logs log-id {
                                              action: "claim",
                                              user: user,
                                              event-id: (some event-id),
                                              listing-id: none,
                                              amount: (some reward),
                                              metadata: "reward-claimed",
                                            })
                                            (var-set next-log-id (+ log-id u1))
                                          )
                                          (ok reward)
                                        )
                                      )
                                      (begin
                                        (map-set earned-points user reward)
                                        ;; Update total NO stakes (subtract before clearing)
                                        (var-set total-no-stakes
                                          (- (var-get total-no-stakes) stake)
                                        )
                                        ;; Clear the stake
                                        (map-set no-stakes {
                                          event-id: event-id,
                                          user: user,
                                        }
                                          u0
                                        )
                                        ;; Update leaderboard stats (WIN)
                                        (match (map-get? user-stats user)
                                          stats (begin
                                            (let (
                                                (new-wins (+ (get wins stats) u1))
                                                (new-total-earned (+
                                                  (get total-points-earned stats)
                                                  reward
                                                ))
                                                (new-win-rate (/ (* new-wins u10000)
                                                  (+ new-wins (get losses stats))
                                                ))
                                              )
                                              (map-set user-stats user {
                                                total-predictions: (get total-predictions stats),
                                                wins: new-wins,
                                                losses: (get losses stats),
                                                total-points-earned: new-total-earned,
                                                win-rate: new-win-rate,
                                              })
                                            )
                                          )
                                          (map-set user-stats user {
                                            total-predictions: u1,
                                            wins: u1,
                                            losses: u0,
                                            total-points-earned: reward,
                                            win-rate: u10000,
                                          })
                                        )
                                        ;; Emit event
                                        (print {
                                          event: "reward-claimed",
                                          event-id: event-id,
                                          user: user,
                                          reward: reward,
                                          total-points: new-total-points,
                                          earned-points: reward,
                                        })
                                        ;; Log transaction
                                        (let ((log-id (var-get next-log-id)))
                                          (map-set transaction-logs log-id {
                                            action: "claim",
                                            user: user,
                                            event-id: (some event-id),
                                            listing-id: none,
                                            amount: (some reward),
                                            metadata: "reward-claimed",
                                          })
                                          (var-set next-log-id (+ log-id u1))
                                        )
                                        (ok reward)
                                      )
                                    )
                                  )
                                )
                                ERR-USER-NOT-REGISTERED ;; User not registered
                              )
                            )
                            (begin
                              ;; User had NO stake but it's 0, check if user had YES stake (they lost)
                              (match (map-get? yes-stakes {
                                event-id: event-id,
                                user: user,
                              })
                                yes-stake
                                (begin
                                  (if (> yes-stake u0)
                                    (begin
                                      ;; User had YES stake but NO won - clear stake and track loss
                                      ;; Update total YES stakes (subtract before clearing)
                                      (var-set total-yes-stakes
                                        (- (var-get total-yes-stakes) yes-stake)
                                      )
                                      (map-set yes-stakes {
                                        event-id: event-id,
                                        user: user,
                                      }
                                        u0
                                      )
                                      ;; Update leaderboard stats (LOSS)
                                      (match (map-get? user-stats user)
                                        stats (begin
                                          (let (
                                              (new-losses (+ (get losses stats) u1))
                                              (total-games (+ (get wins stats) new-losses))
                                              (new-win-rate (if (is-eq total-games u0)
                                                u0
                                                (/ (* (get wins stats) u10000)
                                                  total-games
                                                )
                                              ))
                                            )
                                            (map-set user-stats user {
                                              total-predictions: (get total-predictions stats),
                                              wins: (get wins stats),
                                              losses: new-losses,
                                              total-points-earned: (get total-points-earned stats),
                                              win-rate: new-win-rate,
                                            })
                                          )
                                        )
                                        (map-set user-stats user {
                                          total-predictions: u1,
                                          wins: u0,
                                          losses: u1,
                                          total-points-earned: u0,
                                          win-rate: u0,
                                        })
                                      )
                                      ;; Return success with 0 reward to indicate loss tracked (state changes persist)
                                      (ok u0)
                                    )
                                    ERR-NO-STAKE-FOUND ;; No stake found
                                  )
                                )
                                ERR-NO-STAKE-FOUND ;; No stake found
                              )
                            )
                          )
                        )
                        (begin
                          ;; No NO stake found, check if user had YES stake (they lost)
                          (let ((yes-stake-opt (map-get? yes-stakes {
                              event-id: event-id,
                              user: user,
                            })))
                            (if (is-some yes-stake-opt)
                              (let ((yes-stake (unwrap! yes-stake-opt ERR-NO-STAKE-FOUND)))
                                (if (> yes-stake u0)
                                  (begin
                                    ;; User had YES stake but NO won - clear stake and track loss
                                    ;; Update total YES stakes (subtract before clearing)
                                    (var-set total-yes-stakes
                                      (- (var-get total-yes-stakes) yes-stake)
                                    )
                                    (map-set yes-stakes {
                                      event-id: event-id,
                                      user: user,
                                    }
                                      u0
                                    )
                                    ;; Update leaderboard stats (LOSS)
                                    (match (map-get? user-stats user)
                                      stats (begin
                                        (let (
                                            (new-losses (+ (get losses stats) u1))
                                            (total-games (+ (get wins stats) new-losses))
                                            (new-win-rate (if (is-eq total-games u0)
                                              u0
                                              (/ (* (get wins stats) u10000)
                                                total-games
                                              )
                                            ))
                                          )
                                          (map-set user-stats user {
                                            total-predictions: (get total-predictions stats),
                                            wins: (get wins stats),
                                            losses: new-losses,
                                            total-points-earned: (get total-points-earned stats),
                                            win-rate: new-win-rate,
                                          })
                                        )
                                      )
                                      (map-set user-stats user {
                                        total-predictions: u1,
                                        wins: u0,
                                        losses: u1,
                                        total-points-earned: u0,
                                        win-rate: u0,
                                      })
                                    )
                                    ;; Return success with 0 reward to indicate loss tracked (state changes persist)
                                    (ok u0)
                                  )
                                  ERR-NO-STAKE-FOUND ;; No stake found
                                )
                              )
                              ERR-NO-STAKE-FOUND ;; No stake found
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
          ERR-WINNER-NOT-SET ;; Winner not set
        )
      )
      ERR-EVENT-NOT-FOUND ;; Event not found
    )
  )
)

;; ============================================================================
;; 7. create-listing (points, price-stx)
;; ============================================================================
;; Purpose: Create a marketplace listing to sell points.
;;
;; Details:
;;   - Validates points > 0 and price-stx > 0 (error u4)
;;   - Checks user has earned >= 10,000 points (error u14)
;;   - Checks user has enough points to list (error u6)
;;   - Transfers 10 STX listing fee from seller to contract
;;   - Locks points by deducting from seller's balance
;;   - Creates listing with:
;;     * seller: tx-sender
;;     * points: amount
;;     * price-stx: price
;;     * active: true
;;   - Auto-increments next-listing-id
;;   - Returns (ok listing-id) on success
;;
;; Use case: User lists points for sale on the marketplace.
;;
;; Parameters:
;;   - points: uint - Number of points to sell
;;   - price-stx: uint - Price in micro-STX (1 STX = 1,000,000 micro-STX)
;;
;; Returns:
;;   - (ok listing-id) with the new listing ID on success
;;   - ERR-INVALID-AMOUNT if points or price <= 0
;;   - ERR-INSUFFICIENT-POINTS if insufficient points
;;   - ERR-USER-NOT-REGISTERED if user not registered
;;   - ERR-INSUFFICIENT-EARNED-POINTS if must have earned >= 10,000 points
;; ============================================================================
(define-public (create-listing
    (points uint)
    (price-stx uint)
  )
  (let ((seller tx-sender))
    (asserts! (> points u0) ERR-INVALID-AMOUNT)
    ;; Points must be greater than 0
    (asserts! (> price-stx u0) ERR-INVALID-AMOUNT)
    ;; Price must be greater than 0
    ;; Check if user can sell (earned-points >= 10,000)
    (match (map-get? earned-points seller)
      earned
      (begin
        (asserts! (>= earned MIN_EARNED_FOR_SELL) ERR-INSUFFICIENT-EARNED-POINTS) ;; Must have earned at least 10,000 points
        (match (map-get? user-points seller)
          current-points
          (begin
            (asserts! (>= current-points points) ERR-INSUFFICIENT-POINTS) ;; Insufficient points
            ;; Transfer STX listing fee to contract
            (try! (stx-transfer? LISTING_FEE seller (as-contract tx-sender)))
            ;; Add listing fee to protocol treasury
            (var-set protocol-treasury
              (+ (var-get protocol-treasury) LISTING_FEE)
            )
            ;; Lock seller's points by deducting them
            (map-set user-points seller (- current-points points))
            ;; Create listing
            (let ((listing-id (var-get next-listing-id)))
              (map-set listings listing-id {
                seller: seller,
                points: points,
                price-stx: price-stx,
                active: true,
              })
              (var-set next-listing-id (+ listing-id u1))
              ;; Emit event
              (print {
                event: "listing-created",
                listing-id: listing-id,
                seller: seller,
                points: points,
                price-stx: price-stx,
              })
              ;; Log transaction
              (let ((log-id (var-get next-log-id)))
                (map-set transaction-logs log-id {
                  action: "create-listing",
                  user: seller,
                  event-id: none,
                  listing-id: (some listing-id),
                  amount: (some points),
                  metadata: "listing-created",
                })
                (var-set next-log-id (+ log-id u1))
              )
              (ok listing-id)
            )
          )
          ERR-USER-NOT-REGISTERED ;; User not registered
        )
      )
      ERR-INSUFFICIENT-EARNED-POINTS ;; Must have earned at least 10,000 points
    )
  )
)

;; ============================================================================
;; 8. buy-listing (listing-id, points-to-buy)
;; ============================================================================
;; Purpose: Buy points from a marketplace listing (supports partial purchases).
;;
;; Details:
;;   - Verifies listing exists and is active (errors u16, u15)
;;   - Validates points-to-buy > 0 and <= available points (errors u4, u18)
;;   - Calculates proportional price based on points-to-buy:
;;     * price-per-point = total-price / total-points
;;     * actual-price = price-per-point * points-to-buy
;;   - Calculates:
;;     * protocol-fee = actual-price * 2%
;;     * seller-amount = actual-price - protocol-fee
;;   - Transfers:
;;     * 98% of STX from buyer to seller
;;     * 2% protocol fee to contract treasury
;;   - Adds points to buyer's balance
;;   - Updates listing:
;;     * If partial purchase: Reduces points, adjusts price, keeps active
;;     * If full purchase: Deactivates listing (active: false)
;;   - Updates protocol treasury balance
;;   - Returns (ok true) on success
;;
;; Use case: Buyer purchases points from a listing (partial or full).
;;
;; Parameters:
;;   - listing-id: uint - The listing to purchase from
;;   - points-to-buy: uint - Number of points to buy (must be <= available points)
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-INVALID-AMOUNT if points-to-buy <= 0
;;   - ERR-LISTING-NOT-ACTIVE if listing not active
;;   - ERR-LISTING-NOT-FOUND if listing not found
;;   - ERR-INSUFFICIENT-AVAILABLE-POINTS if points-to-buy > available points
;; ============================================================================
(define-public (buy-listing
    (listing-id uint)
    (points-to-buy uint)
  )
  (let ((buyer tx-sender))
    (asserts! (> points-to-buy u0) ERR-INVALID-AMOUNT)
    ;; Points to buy must be greater than 0
    (match (map-get? listings listing-id)
      listing
      (begin
        (asserts! (get active listing) ERR-LISTING-NOT-ACTIVE) ;; Listing must be active
        (let (
            (seller (get seller listing))
            (total-points (get points listing))
            (total-price-stx (get price-stx listing))
          )
          (asserts! (>= total-points points-to-buy)
            ERR-INSUFFICIENT-AVAILABLE-POINTS
          )
          ;; Not enough points available
          ;; Calculate proportional price
          (let (
              (price-per-point (/ total-price-stx total-points))
              (actual-price-stx (* price-per-point points-to-buy))
              (protocol-fee (/ (* actual-price-stx PROTOCOL_FEE_BPS) BPS_DENOMINATOR))
              (seller-amount (- actual-price-stx protocol-fee))
              (remaining-points (- total-points points-to-buy))
              (remaining-price-stx (- total-price-stx actual-price-stx))
            )
            ;; Transfer STX from buyer to seller (98%)
            (try! (stx-transfer? seller-amount buyer seller))
            ;; Transfer protocol fee (2%) to contract treasury
            (try! (stx-transfer? protocol-fee buyer (as-contract tx-sender)))
            (var-set protocol-treasury
              (+ (var-get protocol-treasury) protocol-fee)
            )
            ;; Transfer points to buyer
            (match (map-get? user-points buyer)
              buyer-points
              (map-set user-points buyer (+ buyer-points points-to-buy))
              (map-set user-points buyer points-to-buy) ;; Buyer not registered, but we'll give them points anyway
            )
            ;; Emit event
            (print {
              event: "listing-bought",
              listing-id: listing-id,
              buyer: buyer,
              seller: seller,
              points: points-to-buy,
              price-stx: actual-price-stx,
              protocol-fee: protocol-fee,
            })
            ;; Log transaction
            (let ((log-id (var-get next-log-id)))
              (map-set transaction-logs log-id {
                action: "buy-listing",
                user: buyer,
                event-id: none,
                listing-id: (some listing-id),
                amount: (some points-to-buy),
                metadata: "listing-bought",
              })
              (var-set next-log-id (+ log-id u1))
            )
            ;; Update listing: partial purchase keeps it active, full purchase deactivates
            (if (is-eq remaining-points u0)
              ;; Full purchase - deactivate listing
              (map-set listings listing-id {
                seller: seller,
                points: u0,
                price-stx: u0,
                active: false,
              })
              ;; Partial purchase - update listing with remaining points and price
              (map-set listings listing-id {
                seller: seller,
                points: remaining-points,
                price-stx: remaining-price-stx,
                active: true,
              })
            )
            (ok true)
          )
        )
      )
      ERR-LISTING-NOT-FOUND ;; Listing not found
    )
  )
)

;; ============================================================================
;; 9. cancel-listing (listing-id)
;; ============================================================================
;; Purpose: Cancel a listing and return points to the seller.
;;
;; Details:
;;   - Verifies listing exists (error u16)
;;   - Verifies caller is the seller (error u17)
;;   - Verifies listing is active (error u15)
;;   - Returns points to seller's balance
;;   - Deactivates listing
;;   - Returns (ok true) on success
;;
;; Use case: Seller cancels their listing before it's sold.
;;
;; Parameters:
;;   - listing-id: uint - The listing to cancel
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-LISTING-NOT-ACTIVE if listing not active
;;   - ERR-LISTING-NOT-FOUND if listing not found
;;   - ERR-ONLY-SELLER-CAN-CANCEL if only seller can cancel
;; ============================================================================
(define-public (cancel-listing (listing-id uint))
  (let ((caller tx-sender))
    (match (map-get? listings listing-id)
      listing
      (begin
        (asserts! (is-eq caller (get seller listing)) ERR-ONLY-SELLER-CAN-CANCEL) ;; Only seller can cancel
        (asserts! (get active listing) ERR-LISTING-NOT-ACTIVE) ;; Listing must be active
        (let ((points (get points listing)))
          ;; Return points to seller
          (match (map-get? user-points caller)
            seller-points (map-set user-points caller (+ seller-points points))
            (map-set user-points caller points)
          )
          ;; Emit event
          (print {
            event: "listing-cancelled",
            listing-id: listing-id,
            seller: caller,
            points: points,
          })
          ;; Log transaction
          (let ((log-id (var-get next-log-id)))
            (map-set transaction-logs log-id {
              action: "cancel-listing",
              user: caller,
              event-id: none,
              listing-id: (some listing-id),
              amount: (some points),
              metadata: "cancelled",
            })
            (var-set next-log-id (+ log-id u1))
          )
          ;; Deactivate listing
          (map-set listings listing-id {
            seller: caller,
            points: points,
            price-stx: (get price-stx listing),
            active: false,
          })
          (ok true)
        )
      )
      ERR-LISTING-NOT-FOUND ;; Listing not found
    )
  )
)

;; ============================================================================
;; 10. withdraw-protocol-fees (amount)
;; ============================================================================
;; Purpose: Withdraw protocol fees from the treasury (admin only).
;;
;; Details:
;;   - Verifies caller is admin (error u2)
;;   - Validates amount > 0 (error u4)
;;   - Checks treasury has sufficient balance (error u25)
;;   - Transfers STX from contract to admin
;;   - Updates protocol-treasury balance
;;   - Returns (ok true) on success
;;
;; Use case: Admin withdraws accumulated protocol fees for dev funding, rewards, or governance.
;;
;; Parameters:
;;   - amount: uint - Amount in micro-STX to withdraw
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-NOT-ADMIN if caller is not admin
;;   - ERR-INVALID-AMOUNT if amount <= 0
;;   - ERR-INSUFFICIENT-TREASURY if treasury balance is insufficient
;; ============================================================================
(define-public (withdraw-protocol-fees (amount uint))
  (let (
      (caller tx-sender)
      (admin-principal (var-get admin))
    )
    (asserts! (is-eq caller admin-principal) ERR-NOT-ADMIN)
    ;; Only admin can withdraw
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    ;; Amount must be greater than 0
    (let ((treasury-balance (var-get protocol-treasury)))
      (asserts! (>= treasury-balance amount) ERR-INSUFFICIENT-TREASURY)
      ;; Insufficient treasury balance
      ;; Update protocol treasury balance
      (var-set protocol-treasury (- treasury-balance amount))
      ;; Transfer STX from contract to admin
      (try! (stx-transfer? amount (as-contract tx-sender) admin-principal))
      ;; Emit event
      (print {
        event: "protocol-fees-withdrawn",
        admin: admin-principal,
        amount: amount,
        remaining-balance: (- treasury-balance amount),
      })
      ;; Log transaction
      (let ((log-id (var-get next-log-id)))
        (map-set transaction-logs log-id {
          action: "withdraw-protocol-fees",
          user: admin-principal,
          event-id: none,
          listing-id: none,
          amount: (some amount),
          metadata: "protocol-fees-withdrawn",
        })
        (var-set next-log-id (+ log-id u1))
      )
      (ok true)
    )
  )
)

;; ============================================================================
;; 10b. mint-admin-points (points)
;; ============================================================================
;; Purpose: Admin mints points to themselves for selling to users who need points.
;;
;; Details:
;;   - Only callable by admin
;;   - Mints points directly to admin's user-points balance
;;   - Does NOT add to earned-points (won't affect leaderboard)
;;   - No fee charged
;;
;; Parameters:
;;   - points: uint - Number of points to mint
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-NOT-ADMIN if caller is not admin
;;   - ERR-INVALID-AMOUNT if points <= 0
;; ============================================================================
(define-public (mint-admin-points (points uint))
  (let (
      (caller tx-sender)
      (admin-principal (var-get admin))
    )
    (asserts! (is-eq caller admin-principal) ERR-NOT-ADMIN)
    (asserts! (> points u0) ERR-INVALID-AMOUNT)
    ;; Add points to admin's balance
    (match (map-get? user-points admin-principal)
      current-points
      (map-set user-points admin-principal (+ current-points points))
      (map-set user-points admin-principal points)
    )
    ;; Track total minted points
    (var-set total-admin-minted-points (+ (var-get total-admin-minted-points) points))
    ;; Emit event
    (print {
      event: "admin-points-minted",
      admin: admin-principal,
      points: points,
    })
    ;; Log transaction
    (let ((log-id (var-get next-log-id)))
      (map-set transaction-logs log-id {
        action: "mint-admin-points",
        user: admin-principal,
        event-id: none,
        listing-id: none,
        amount: (some points),
        metadata: "admin-points-minted",
      })
      (var-set next-log-id (+ log-id u1))
    )
    (ok true)
  )
)

;; ============================================================================
;; 10c. buy-admin-points (points-to-buy)
;; ============================================================================
;; Purpose: Users buy points directly from admin at a fixed rate, no fees.
;;
;; Details:
;;   - Anyone can call this to buy points from admin
;;   - Fixed price: 1 STX per 1000 points (1000 micro-STX per point)
;;   - STX goes directly into the contract (protocol treasury)
;;   - Points deducted from admin's balance, added to buyer's balance
;;   - No protocol fee charged
;;   - Does NOT add to buyer's earned-points (won't affect leaderboard)
;;
;; Parameters:
;;   - points-to-buy: uint - Number of points to buy
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-INVALID-AMOUNT if points-to-buy <= 0
;;   - ERR-INSUFFICIENT-POINTS if admin doesn't have enough points
;; ============================================================================


(define-public (buy-admin-points (points-to-buy uint))
  (let (
      (buyer tx-sender)
      (admin-principal (var-get admin))
      (total-price (* points-to-buy ADMIN_POINT_PRICE))
    )
    (asserts! (> points-to-buy u0) ERR-INVALID-AMOUNT)
    ;; Check admin has enough points
    (match (map-get? user-points admin-principal)
      admin-points
      (begin
        (asserts! (>= admin-points points-to-buy) ERR-INSUFFICIENT-POINTS)
        ;; Transfer STX from buyer to contract (no fee, all goes to treasury)
        (try! (stx-transfer? total-price buyer (as-contract tx-sender)))
        ;; Add to protocol treasury
        (var-set protocol-treasury (+ (var-get protocol-treasury) total-price))
        ;; Deduct points from admin
        (map-set user-points admin-principal (- admin-points points-to-buy))
        ;; Add points to buyer
        (match (map-get? user-points buyer)
          buyer-points
          (map-set user-points buyer (+ buyer-points points-to-buy))
          (map-set user-points buyer points-to-buy)
        )
        ;; Emit event
        (print {
          event: "admin-points-bought",
          buyer: buyer,
          points: points-to-buy,
          price-stx: total-price,
        })
        ;; Log transaction
        (let ((log-id (var-get next-log-id)))
          (map-set transaction-logs log-id {
            action: "buy-admin-points",
            user: buyer,
            event-id: none,
            listing-id: none,
            amount: (some points-to-buy),
            metadata: "admin-points-bought",
          })
          (var-set next-log-id (+ log-id u1))
        )
        (ok true)
      )
      ERR-INSUFFICIENT-POINTS ;; Admin has no points
    )
  )
)

;; ============================================================================
;; 11. create-guild (guild-id, name)
;; ============================================================================
;; Purpose: Create a new guild for collaborative predictions.
;;
;; Details:
;;   - Checks if guild ID already exists (error u19 if yes)
;;   - Creates guild with creator as first member
;;   - Initializes guild with 0 points
;;   - Returns (ok true) on success
;;
;; Use case: User creates a guild for collaborative predictions.
;;
;; Parameters:
;;   - guild-id: uint - Unique identifier for the guild
;;   - name: (string-ascii 50) - Guild name
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-GUILD-ID-EXISTS if guild ID already exists
;; ============================================================================
(define-public (create-guild
    (guild-id uint)
    (name (string-ascii 50))
  )
  (let ((creator tx-sender))
    (match (map-get? guilds guild-id)
      existing
      ERR-GUILD-ID-EXISTS ;; Guild ID already exists
      (begin
        (map-set guilds guild-id {
          creator: creator,
          name: name,
          total-points: u0,
          member-count: u1,
        })
        (map-set guild-members {
          guild-id: guild-id,
          user: creator,
        }
          true
        )
        (map-set guild-deposits {
          guild-id: guild-id,
          user: creator,
        }
          u0
        )
        ;; Emit event
        (print {
          event: "guild-created",
          guild-id: guild-id,
          creator: creator,
          name: name,
        })
        (ok true)
      )
    )
  )
)

;; ============================================================================
;; 12. join-guild (guild-id)
;; ============================================================================
;; Purpose: Join an existing guild.
;;
;; Details:
;;   - Verifies guild exists (error u20 if not)
;;   - Checks user is not already a member (error u21 if already member)
;;   - Adds user as member
;;   - Initializes user's deposit to 0
;;   - Increments member count
;;   - Returns (ok true) on success
;;
;; Use case: User joins a guild to participate in collaborative predictions.
;;
;; Parameters:
;;   - guild-id: uint - The guild to join
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-GUILD-NOT-FOUND if guild not found
;;   - ERR-ALREADY-A-MEMBER if already a member
;; ============================================================================
(define-public (join-guild (guild-id uint))
  (let ((user tx-sender))
    (match (map-get? guilds guild-id)
      guild
      (begin
        (if (is-member? guild-id user)
          ERR-ALREADY-A-MEMBER ;; Already a member
          (begin
            (map-set guild-members {
              guild-id: guild-id,
              user: user,
            }
              true
            )
            (map-set guild-deposits {
              guild-id: guild-id,
              user: user,
            }
              u0
            )
            (map-set guilds guild-id {
              creator: (get creator guild),
              name: (get name guild),
              total-points: (get total-points guild),
              member-count: (+ (get member-count guild) u1),
            })
            (print {
              event: "guild-joined",
              guild-id: guild-id,
              user: user,
            })
            (ok true)
          )
        )
      )
      ERR-GUILD-NOT-FOUND ;; Guild not found
    )
  )
)

;; ============================================================================
;; 13. leave-guild (guild-id)
;; ============================================================================
;; Purpose: Leave a guild (can only withdraw own deposits first).
;;
;; Details:
;;   - Verifies guild exists (error u20 if not)
;;   - Checks user is a member (error u22 if not)
;;   - Checks user has withdrawn all deposits (error u23 if has deposits)
;;   - Removes user from guild
;;   - Decrements member count
;;   - Returns (ok true) on success
;;
;; Use case: User leaves a guild (must withdraw deposits first).
;;
;; Parameters:
;;   - guild-id: uint - The guild to leave
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-GUILD-NOT-FOUND if guild not found
;;   - ERR-NOT-A-MEMBER if not a member
;;   - ERR-HAS-DEPOSITS if has deposits (must withdraw first)
;; ============================================================================
(define-public (leave-guild (guild-id uint))
  (let ((user tx-sender))
    (match (map-get? guilds guild-id)
      guild
      (begin
        (if (is-member? guild-id user)
          (begin
            (match (map-get? guild-deposits {
              guild-id: guild-id,
              user: user,
            })
              deposit (if (is-eq deposit u0)
                (begin
                  (map-set guild-members {
                    guild-id: guild-id,
                    user: user,
                  }
                    false
                  )
                  (map-set guilds guild-id {
                    creator: (get creator guild),
                    name: (get name guild),
                    total-points: (get total-points guild),
                    member-count: (- (get member-count guild) u1),
                  })
                  (print {
                    event: "guild-left",
                    guild-id: guild-id,
                    user: user,
                  })
                  (ok true)
                )
                ERR-HAS-DEPOSITS ;; Has deposits, must withdraw first
              )
              (begin
                (map-set guild-members {
                  guild-id: guild-id,
                  user: user,
                }
                  false
                )
                (map-set guilds guild-id {
                  creator: (get creator guild),
                  name: (get name guild),
                  total-points: (get total-points guild),
                  member-count: (- (get member-count guild) u1),
                })
                (print {
                  event: "guild-left",
                  guild-id: guild-id,
                  user: user,
                })
                (ok true)
              )
            )
          )
          ERR-NOT-A-MEMBER ;; Not a member
        )
      )
      ERR-GUILD-NOT-FOUND ;; Guild not found
    )
  )
)

;; ============================================================================
;; 14. deposit-to-guild (guild-id, amount)
;; ============================================================================
;; Purpose: Deposit points to guild pool for collaborative predictions.
;;
;; Details:
;;   - Verifies guild exists (error u20 if not)
;;   - Checks user is a member (error u22 if not)
;;   - Validates amount > 0 (error u4)
;;   - Checks user has enough points (error u6)
;;   - Deducts points from user
;;   - Adds to guild pool
;;   - Updates user's deposit record
;;   - Returns (ok true) on success
;;
;; Use case: Guild member deposits points to guild pool for predictions.
;;
;; Parameters:
;;   - guild-id: uint - The guild to deposit to
;;   - amount: uint - Points to deposit
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-INVALID-AMOUNT if amount <= 0
;;   - ERR-INSUFFICIENT-POINTS if insufficient points
;;   - ERR-GUILD-NOT-FOUND if guild not found
;;   - ERR-NOT-A-MEMBER if not a member
;; ============================================================================
(define-public (deposit-to-guild
    (guild-id uint)
    (amount uint)
  )
  (let ((user tx-sender))
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    ;; Amount must be greater than 0
    (match (map-get? guilds guild-id)
      guild
      (begin
        (if (is-member? guild-id user)
          (begin
            (match (map-get? user-points user)
              current-points
              (begin
                (asserts! (>= current-points amount) ERR-INSUFFICIENT-POINTS) ;; Insufficient points
                ;; Deduct from user
                (map-set user-points user (- current-points amount))
                ;; Add to guild pool
                (match (map-get? guild-deposits {
                  guild-id: guild-id,
                  user: user,
                })
                  existing-deposit (begin
                    (map-set guild-deposits {
                      guild-id: guild-id,
                      user: user,
                    }
                      (+ existing-deposit amount)
                    )
                    (map-set guilds guild-id {
                      creator: (get creator guild),
                      name: (get name guild),
                      total-points: (+ (get total-points guild) amount),
                      member-count: (get member-count guild),
                    })
                  )
                  (begin
                    (map-set guild-deposits {
                      guild-id: guild-id,
                      user: user,
                    }
                      amount
                    )
                    (map-set guilds guild-id {
                      creator: (get creator guild),
                      name: (get name guild),
                      total-points: (+ (get total-points guild) amount),
                      member-count: (get member-count guild),
                    })
                  )
                )
                ;; Emit event
                (print {
                  event: "guild-deposit",
                  guild-id: guild-id,
                  user: user,
                  amount: amount,
                })
                (ok true)
              )
              ERR-USER-NOT-REGISTERED ;; User not registered
            )
          )
          ERR-NOT-A-MEMBER ;; Not a member
        )
      )
      ERR-GUILD-NOT-FOUND ;; Guild not found
    )
  )
)

;; ============================================================================
;; 15. withdraw-from-guild (guild-id, amount)
;; ============================================================================
;; Purpose: Withdraw own deposits from guild pool.
;;
;; Details:
;;   - Verifies guild exists (error u20 if not)
;;   - Checks user is a member (error u22 if not)
;;   - Validates amount > 0 (error u4)
;;   - Checks user has enough deposits (error u24)
;;   - Checks guild has enough points (error u6)
;;   - Deducts from guild pool
;;   - Updates user's deposit record
;;   - Returns points to user
;;   - Returns (ok true) on success
;;
;; Use case: Guild member withdraws their deposited points.
;;
;; Parameters:
;;   - guild-id: uint - The guild to withdraw from
;;   - amount: uint - Points to withdraw
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-INVALID-AMOUNT if amount <= 0
;;   - ERR-INSUFFICIENT-POINTS if guild has insufficient points
;;   - ERR-GUILD-NOT-FOUND if guild not found
;;   - ERR-NOT-A-MEMBER if not a member
;;   - ERR-INSUFFICIENT-DEPOSITS if user has insufficient deposits
;; ============================================================================
(define-public (withdraw-from-guild
    (guild-id uint)
    (amount uint)
  )
  (let ((user tx-sender))
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    ;; Amount must be greater than 0
    (match (map-get? guilds guild-id)
      guild
      (begin
        (if (is-member? guild-id user)
          (begin
            (match (map-get? guild-deposits {
              guild-id: guild-id,
              user: user,
            })
              user-deposit
              (begin
                (asserts! (>= user-deposit amount) ERR-INSUFFICIENT-DEPOSITS) ;; Insufficient deposits
                (asserts! (>= (get total-points guild) amount)
                  ERR-INSUFFICIENT-POINTS
                )
                ;; Guild has insufficient points
                ;; Deduct from guild pool
                (map-set guilds guild-id {
                  creator: (get creator guild),
                  name: (get name guild),
                  total-points: (- (get total-points guild) amount),
                  member-count: (get member-count guild),
                })
                ;; Update user's deposit record
                (map-set guild-deposits {
                  guild-id: guild-id,
                  user: user,
                }
                  (- user-deposit amount)
                )
                ;; Return points to user
                (match (map-get? user-points user)
                  current-points (map-set user-points user (+ current-points amount))
                  (map-set user-points user amount)
                )
                ;; Emit event
                (print {
                  event: "guild-withdraw",
                  guild-id: guild-id,
                  user: user,
                  amount: amount,
                })
                (ok true)
              )
              ERR-INSUFFICIENT-DEPOSITS ;; No deposits
            )
          )
          ERR-NOT-A-MEMBER ;; Not a member
        )
      )
      ERR-GUILD-NOT-FOUND ;; Guild not found
    )
  )
)

;; ============================================================================
;; 16. guild-stake-yes (guild-id, event-id, amount)
;; ============================================================================
;; Purpose: Guild stakes points on YES outcome of an event.
;;
;; Details:
;;   - Verifies guild exists (error u20 if not)
;;   - Checks user is a member (error u22 if not)
;;   - Validates amount > 0 (error u4)
;;   - Verifies event exists and is "open" (errors u8, u5)
;;   - Checks guild has enough points (error u6)
;;   - Deducts points from guild pool
;;   - Adds points to event's YES pool
;;   - Records guild's YES stake
;;   - Returns (ok true) on success
;;
;; Use case: Guild member stakes guild points on YES outcome.
;;
;; Parameters:
;;   - guild-id: uint - The guild staking
;;   - event-id: uint - The event to stake on
;;   - amount: uint - Points to stake
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-INVALID-AMOUNT if amount <= 0
;;   - ERR-EVENT-NOT-OPEN if event is not open
;;   - ERR-INSUFFICIENT-POINTS if insufficient points
;;   - ERR-EVENT-NOT-FOUND if event not found
;;   - ERR-GUILD-NOT-FOUND if guild not found
;;   - ERR-NOT-A-MEMBER if not a member
;; ============================================================================
(define-public (guild-stake-yes
    (guild-id uint)
    (event-id uint)
    (amount uint)
  )
  (let ((user tx-sender))
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    ;; Amount must be greater than 0
    (match (map-get? guilds guild-id)
      guild
      (begin
        (if (is-member? guild-id user)
          (begin
            (asserts! (>= (get total-points guild) amount)
              ERR-INSUFFICIENT-POINTS
            )
            ;; Insufficient guild points
            (match (map-get? events event-id)
              event
              (begin
                (asserts! (is-eq (get status event) "open") ERR-EVENT-NOT-OPEN) ;; Event must be open
                ;; Deduct from guild pool
                (map-set guilds guild-id {
                  creator: (get creator guild),
                  name: (get name guild),
                  total-points: (- (get total-points guild) amount),
                  member-count: (get member-count guild),
                })
                ;; Add to YES pool
                (let (
                    (new-yes-pool (+ (get yes-pool event) amount))
                    (new-no-pool (get no-pool event))
                  )
                  (map-set events event-id {
                    yes-pool: new-yes-pool,
                    no-pool: new-no-pool,
                    status: (get status event),
                    winner: (get winner event),
                    creator: (get creator event),
                    metadata: (get metadata event),
                  })
                  ;; Record guild's stake
                  (match (map-get? guild-yes-stakes {
                    guild-id: guild-id,
                    event-id: event-id,
                  })
                    existing-stake (map-set guild-yes-stakes {
                      guild-id: guild-id,
                      event-id: event-id,
                    }
                      (+ existing-stake amount)
                    )
                    (begin
                      (map-set guild-yes-stakes {
                        guild-id: guild-id,
                        event-id: event-id,
                      }
                        amount
                      )
                      ;; Track new prediction for guild leaderboard
                      (match (map-get? guild-stats guild-id)
                        stats (map-set guild-stats guild-id {
                          total-predictions: (+ (get total-predictions stats) u1),
                          wins: (get wins stats),
                          losses: (get losses stats),
                          total-points-earned: (get total-points-earned stats),
                          win-rate: (get win-rate stats),
                        })
                        (map-set guild-stats guild-id {
                          total-predictions: u1,
                          wins: u0,
                          losses: u0,
                          total-points-earned: u0,
                          win-rate: u0,
                        })
                      )
                    )
                  )
                  ;; Update total guild YES stakes
                  (var-set total-guild-yes-stakes
                    (+ (var-get total-guild-yes-stakes) amount)
                  )
                  ;; Emit event
                  (print {
                    event: "guild-staked-yes",
                    guild-id: guild-id,
                    event-id: event-id,
                    amount: amount,
                    yes-pool: new-yes-pool,
                    no-pool: new-no-pool,
                  })
                  (ok true)
                )
              )
              ERR-EVENT-NOT-FOUND ;; Event not found
            )
          )
          ERR-NOT-A-MEMBER ;; Not a member
        )
      )
      ERR-GUILD-NOT-FOUND ;; Guild not found
    )
  )
)

;; ============================================================================
;; 17. guild-stake-no (guild-id, event-id, amount)
;; ============================================================================
;; Purpose: Guild stakes points on NO outcome of an event.
;;
;; Details:
;;   - Same logic as guild-stake-yes, but stakes on NO
;;   - Returns (ok true) on success
;;
;; Use case: Guild member stakes guild points on NO outcome.
;;
;; Parameters:
;;   - guild-id: uint - The guild staking
;;   - event-id: uint - The event to stake on
;;   - amount: uint - Points to stake
;;
;; Returns:
;;   - (ok true) on success
;;   - ERR-INVALID-AMOUNT if amount <= 0
;;   - ERR-EVENT-NOT-OPEN if event is not open
;;   - ERR-INSUFFICIENT-POINTS if insufficient points
;;   - ERR-EVENT-NOT-FOUND if event not found
;;   - ERR-GUILD-NOT-FOUND if guild not found
;;   - ERR-NOT-A-MEMBER if not a member
;; ============================================================================
(define-public (guild-stake-no
    (guild-id uint)
    (event-id uint)
    (amount uint)
  )
  (let ((user tx-sender))
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    ;; Amount must be greater than 0
    (match (map-get? guilds guild-id)
      guild
      (begin
        (if (is-member? guild-id user)
          (begin
            (asserts! (>= (get total-points guild) amount)
              ERR-INSUFFICIENT-POINTS
            )
            ;; Insufficient guild points
            (match (map-get? events event-id)
              event
              (begin
                (asserts! (is-eq (get status event) "open") ERR-EVENT-NOT-OPEN) ;; Event must be open
                ;; Deduct from guild pool
                (map-set guilds guild-id {
                  creator: (get creator guild),
                  name: (get name guild),
                  total-points: (- (get total-points guild) amount),
                  member-count: (get member-count guild),
                })
                ;; Add to NO pool
                (let (
                    (new-yes-pool (get yes-pool event))
                    (new-no-pool (+ (get no-pool event) amount))
                  )
                  (map-set events event-id {
                    yes-pool: new-yes-pool,
                    no-pool: new-no-pool,
                    status: (get status event),
                    winner: (get winner event),
                    creator: (get creator event),
                    metadata: (get metadata event),
                  })
                  ;; Record guild's stake
                  (match (map-get? guild-no-stakes {
                    guild-id: guild-id,
                    event-id: event-id,
                  })
                    existing-stake (map-set guild-no-stakes {
                      guild-id: guild-id,
                      event-id: event-id,
                    }
                      (+ existing-stake amount)
                    )
                    (begin
                      (map-set guild-no-stakes {
                        guild-id: guild-id,
                        event-id: event-id,
                      }
                        amount
                      )
                      ;; Track new prediction for guild leaderboard
                      (match (map-get? guild-stats guild-id)
                        stats (map-set guild-stats guild-id {
                          total-predictions: (+ (get total-predictions stats) u1),
                          wins: (get wins stats),
                          losses: (get losses stats),
                          total-points-earned: (get total-points-earned stats),
                          win-rate: (get win-rate stats),
                        })
                        (map-set guild-stats guild-id {
                          total-predictions: u1,
                          wins: u0,
                          losses: u0,
                          total-points-earned: u0,
                          win-rate: u0,
                        })
                      )
                    )
                  )
                  ;; Update total guild NO stakes
                  (var-set total-guild-no-stakes
                    (+ (var-get total-guild-no-stakes) amount)
                  )
                  ;; Emit event
                  (print {
                    event: "guild-staked-no",
                    guild-id: guild-id,
                    event-id: event-id,
                    amount: amount,
                    yes-pool: new-yes-pool,
                    no-pool: new-no-pool,
                  })
                  (ok true)
                )
              )
              ERR-EVENT-NOT-FOUND ;; Event not found
            )
          )
          ERR-NOT-A-MEMBER ;; Not a member
        )
      )
      ERR-GUILD-NOT-FOUND ;; Guild not found
    )
  )
)

;; ============================================================================
;; 18. guild-claim (guild-id, event-id)
;; ============================================================================
;; Purpose: Claim rewards for guild from a resolved event if guild won.
;;
;; Details:
;;   - Verifies guild exists (error u20 if not)
;;   - Checks user is a member (error u22 if not)
;;   - Verifies event exists and is "resolved" (errors u8, u10)
;;   - Verifies winner is set (error u13)
;;   - Calculates reward proportionally
;;   - If guild has a stake in the winning side:
;;     * Adds reward to guild pool
;;     * Clears the stake
;;     * Returns (ok reward) with the reward amount
;;
;; Use case: Guild member claims rewards for the guild.
;;
;; Parameters:
;;   - guild-id: uint - The guild claiming rewards
;;   - event-id: uint - The event to claim rewards from
;;
;; Returns:
;;   - (ok reward) with reward amount on success
;;   - ERR-EVENT-NOT-FOUND if event not found
;;   - ERR-EVENT-MUST-BE-RESOLVED if event must be resolved
;;   - ERR-NO-WINNERS if no winners (pool is empty)
;;   - ERR-NO-STAKE-FOUND if no stake found
;;   - ERR-WINNER-NOT-SET if winner not set
;;   - ERR-GUILD-NOT-FOUND if guild not found
;;   - ERR-NOT-A-MEMBER if not a member
;; ============================================================================
(define-public (guild-claim
    (guild-id uint)
    (event-id uint)
  )
  (let ((user tx-sender))
    (match (map-get? guilds guild-id)
      guild
      (begin
        (if (is-member? guild-id user)
          (begin
            (match (map-get? events event-id)
              event
              (begin
                (asserts! (is-eq (get status event) "resolved")
                  ERR-EVENT-MUST-BE-RESOLVED
                )
                ;; Event must be resolved
                (match (get winner event)
                  winner
                  (begin
                    (let (
                        (yes-pool (get yes-pool event))
                        (no-pool (get no-pool event))
                        (total-pool (+ yes-pool no-pool))
                        (winning-pool (if winner
                          yes-pool
                          no-pool
                        ))
                      )
                      (if (is-eq winning-pool u0)
                        ERR-NO-WINNERS ;; No winners (pool is empty)
                        (begin
                          (if winner
                            ;; Guild staked YES
                            (match (map-get? guild-yes-stakes {
                              guild-id: guild-id,
                              event-id: event-id,
                            })
                              stake (begin
                                (if (> stake u0)
                                  (let ((reward (/ (* stake total-pool) winning-pool)))
                                    ;; Add reward to guild pool
                                    (map-set guilds guild-id {
                                      creator: (get creator guild),
                                      name: (get name guild),
                                      total-points: (+ (get total-points guild) reward),
                                      member-count: (get member-count guild),
                                    })
                                    ;; Update total guild YES stakes (subtract before clearing)
                                    (var-set total-guild-yes-stakes
                                      (- (var-get total-guild-yes-stakes) stake)
                                    )
                                    ;; Clear the stake
                                    (map-set guild-yes-stakes {
                                      guild-id: guild-id,
                                      event-id: event-id,
                                    }
                                      u0
                                    )
                                    ;; Update guild leaderboard stats (WIN)
                                    (match (map-get? guild-stats guild-id)
                                      stats (begin
                                        (let (
                                            (new-wins (+ (get wins stats) u1))
                                            (new-total-earned (+ (get total-points-earned stats)
                                              reward
                                            ))
                                            (new-win-rate (/ (* new-wins u10000)
                                              (+ new-wins (get losses stats))
                                            ))
                                          )
                                          (map-set guild-stats guild-id {
                                            total-predictions: (get total-predictions stats),
                                            wins: new-wins,
                                            losses: (get losses stats),
                                            total-points-earned: new-total-earned,
                                            win-rate: new-win-rate,
                                          })
                                        )
                                      )
                                      (map-set guild-stats guild-id {
                                        total-predictions: u1,
                                        wins: u1,
                                        losses: u0,
                                        total-points-earned: reward,
                                        win-rate: u10000,
                                      })
                                    )
                                    ;; Emit event
                                    (print {
                                      event: "guild-reward-claimed",
                                      guild-id: guild-id,
                                      event-id: event-id,
                                      reward: reward,
                                      total-points: (+ (get total-points guild) reward),
                                    })
                                    (ok reward)
                                  )
                                  (begin
                                    ;; Guild had YES stake but it's 0, check if guild had NO stake (they lost)
                                    (match (map-get? guild-no-stakes {
                                      guild-id: guild-id,
                                      event-id: event-id,
                                    })
                                      no-stake
                                      (begin
                                        (if (> no-stake u0)
                                          (begin
                                            ;; Guild had NO stake but YES won - clear stake and track loss
                                            ;; Update total guild NO stakes (subtract before clearing)
                                            (var-set total-guild-no-stakes
                                              (- (var-get total-guild-no-stakes)
                                                no-stake
                                              ))
                                            (map-set guild-no-stakes {
                                              guild-id: guild-id,
                                              event-id: event-id,
                                            }
                                              u0
                                            )
                                            ;; Update guild leaderboard stats (LOSS)
                                            (match (map-get? guild-stats guild-id)
                                              stats (begin
                                                (let (
                                                    (new-losses (+ (get losses stats) u1))
                                                    (total-games (+ (get wins stats)
                                                      new-losses
                                                    ))
                                                    (new-win-rate (if (is-eq total-games u0)
                                                      u0
                                                      (/
                                                        (* (get wins stats)
                                                          u10000
                                                        )
                                                        total-games
                                                      )
                                                    ))
                                                  )
                                                  (map-set guild-stats guild-id {
                                                    total-predictions: (get total-predictions stats),
                                                    wins: (get wins stats),
                                                    losses: new-losses,
                                                    total-points-earned: (get total-points-earned
                                                      stats
                                                    ),
                                                    win-rate: new-win-rate,
                                                  })
                                                )
                                              )
                                              (map-set guild-stats guild-id {
                                                total-predictions: u1,
                                                wins: u0,
                                                losses: u1,
                                                total-points-earned: u0,
                                                win-rate: u0,
                                              })
                                            )
                                            ;; Return success with 0 reward to indicate loss tracked (state changes persist)
                                            (ok u0)
                                          )
                                          ERR-NO-STAKE-FOUND ;; No stake found
                                        )
                                      )
                                      ERR-NO-STAKE-FOUND ;; No stake found
                                    )
                                  )
                                )
                              )
                              (begin
                                ;; No YES stake found, check if guild had NO stake (they lost)
                                (let ((no-stake-opt (map-get? guild-no-stakes {
                                    guild-id: guild-id,
                                    event-id: event-id,
                                  })))
                                  (if (is-some no-stake-opt)
                                    (let ((no-stake (unwrap! no-stake-opt ERR-NO-STAKE-FOUND)))
                                      (if (> no-stake u0)
                                        (begin
                                          ;; Guild had NO stake but YES won - clear stake and track loss
                                          ;; Update total guild NO stakes (subtract before clearing)
                                          (var-set total-guild-no-stakes
                                            (- (var-get total-guild-no-stakes)
                                              no-stake
                                            ))
                                          (map-set guild-no-stakes {
                                            guild-id: guild-id,
                                            event-id: event-id,
                                          }
                                            u0
                                          )
                                          ;; Update guild leaderboard stats (LOSS)
                                          (match (map-get? guild-stats guild-id)
                                            stats (begin
                                              (let (
                                                  (new-losses (+ (get losses stats) u1))
                                                  (total-games (+ (get wins stats) new-losses))
                                                  (new-win-rate (if (is-eq total-games u0)
                                                    u0
                                                    (/
                                                      (* (get wins stats) u10000)
                                                      total-games
                                                    )
                                                  ))
                                                )
                                                (map-set guild-stats guild-id {
                                                  total-predictions: (get total-predictions stats),
                                                  wins: (get wins stats),
                                                  losses: new-losses,
                                                  total-points-earned: (get total-points-earned stats),
                                                  win-rate: new-win-rate,
                                                })
                                              )
                                            )
                                            (map-set guild-stats guild-id {
                                              total-predictions: u1,
                                              wins: u0,
                                              losses: u1,
                                              total-points-earned: u0,
                                              win-rate: u0,
                                            })
                                          )
                                          ;; Return success with 0 reward to indicate loss tracked (state changes persist)
                                          (ok u0)
                                        )
                                        ERR-NO-STAKE-FOUND ;; No stake found
                                      )
                                    )
                                    ERR-NO-STAKE-FOUND ;; No stake found
                                  )
                                )
                              )
                            )
                            ;; Guild staked NO
                            (match (map-get? guild-no-stakes {
                              guild-id: guild-id,
                              event-id: event-id,
                            })
                              stake (begin
                                (if (> stake u0)
                                  (let ((reward (/ (* stake total-pool) winning-pool)))
                                    ;; Add reward to guild pool
                                    (map-set guilds guild-id {
                                      creator: (get creator guild),
                                      name: (get name guild),
                                      total-points: (+ (get total-points guild) reward),
                                      member-count: (get member-count guild),
                                    })
                                    ;; Update total guild NO stakes (subtract before clearing)
                                    (var-set total-guild-no-stakes
                                      (- (var-get total-guild-no-stakes) stake)
                                    )
                                    ;; Clear the stake
                                    (map-set guild-no-stakes {
                                      guild-id: guild-id,
                                      event-id: event-id,
                                    }
                                      u0
                                    )
                                    ;; Update guild leaderboard stats (WIN)
                                    (match (map-get? guild-stats guild-id)
                                      stats (begin
                                        (let (
                                            (new-wins (+ (get wins stats) u1))
                                            (new-total-earned (+ (get total-points-earned stats)
                                              reward
                                            ))
                                            (new-win-rate (/ (* new-wins u10000)
                                              (+ new-wins (get losses stats))
                                            ))
                                          )
                                          (map-set guild-stats guild-id {
                                            total-predictions: (get total-predictions stats),
                                            wins: new-wins,
                                            losses: (get losses stats),
                                            total-points-earned: new-total-earned,
                                            win-rate: new-win-rate,
                                          })
                                        )
                                      )
                                      (map-set guild-stats guild-id {
                                        total-predictions: u1,
                                        wins: u1,
                                        losses: u0,
                                        total-points-earned: reward,
                                        win-rate: u10000,
                                      })
                                    )
                                    ;; Emit event
                                    (print {
                                      event: "guild-reward-claimed",
                                      guild-id: guild-id,
                                      event-id: event-id,
                                      reward: reward,
                                      total-points: (+ (get total-points guild) reward),
                                    })
                                    (ok reward)
                                  )
                                  (begin
                                    ;; Guild had NO stake but it's 0, check if guild had YES stake (they lost)
                                    (match (map-get? guild-yes-stakes {
                                      guild-id: guild-id,
                                      event-id: event-id,
                                    })
                                      yes-stake
                                      (begin
                                        (if (> yes-stake u0)
                                          (begin
                                            ;; Guild had YES stake but NO won - clear stake and track loss
                                            ;; Update total guild YES stakes (subtract before clearing)
                                            (var-set total-guild-yes-stakes
                                              (- (var-get total-guild-yes-stakes)
                                                yes-stake
                                              ))
                                            (map-set guild-yes-stakes {
                                              guild-id: guild-id,
                                              event-id: event-id,
                                            }
                                              u0
                                            )
                                            ;; Update guild leaderboard stats (LOSS)
                                            (match (map-get? guild-stats guild-id)
                                              stats (begin
                                                (let (
                                                    (new-losses (+ (get losses stats) u1))
                                                    (total-games (+ (get wins stats)
                                                      new-losses
                                                    ))
                                                    (new-win-rate (if (is-eq total-games u0)
                                                      u0
                                                      (/
                                                        (* (get wins stats)
                                                          u10000
                                                        )
                                                        total-games
                                                      )
                                                    ))
                                                  )
                                                  (map-set guild-stats guild-id {
                                                    total-predictions: (get total-predictions stats),
                                                    wins: (get wins stats),
                                                    losses: new-losses,
                                                    total-points-earned: (get total-points-earned
                                                      stats
                                                    ),
                                                    win-rate: new-win-rate,
                                                  })
                                                )
                                              )
                                              (map-set guild-stats guild-id {
                                                total-predictions: u1,
                                                wins: u0,
                                                losses: u1,
                                                total-points-earned: u0,
                                                win-rate: u0,
                                              })
                                            )
                                            ;; Return success with 0 reward to indicate loss tracked (state changes persist)
                                            (ok u0)
                                          )
                                          ERR-NO-STAKE-FOUND ;; No stake found
                                        )
                                      )
                                      ERR-NO-STAKE-FOUND ;; No stake found
                                    )
                                  )
                                )
                              )
                              (begin
                                ;; No NO stake found, check if guild had YES stake (they lost)
                                (let ((yes-stake-opt (map-get? guild-yes-stakes {
                                    guild-id: guild-id,
                                    event-id: event-id,
                                  })))
                                  (if (is-some yes-stake-opt)
                                    (let ((yes-stake (unwrap! yes-stake-opt ERR-NO-STAKE-FOUND)))
                                      (if (> yes-stake u0)
                                        (begin
                                          ;; Guild had YES stake but NO won - clear stake and track loss
                                          ;; Update total guild YES stakes (subtract before clearing)
                                          (var-set total-guild-yes-stakes
                                            (- (var-get total-guild-yes-stakes)
                                              yes-stake
                                            ))
                                          (map-set guild-yes-stakes {
                                            guild-id: guild-id,
                                            event-id: event-id,
                                          }
                                            u0
                                          )
                                          ;; Update guild leaderboard stats (LOSS)
                                          (match (map-get? guild-stats guild-id)
                                            stats (begin
                                              (let (
                                                  (new-losses (+ (get losses stats) u1))
                                                  (total-games (+ (get wins stats) new-losses))
                                                  (new-win-rate (if (is-eq total-games u0)
                                                    u0
                                                    (/
                                                      (* (get wins stats) u10000)
                                                      total-games
                                                    )
                                                  ))
                                                )
                                                (map-set guild-stats guild-id {
                                                  total-predictions: (get total-predictions stats),
                                                  wins: (get wins stats),
                                                  losses: new-losses,
                                                  total-points-earned: (get total-points-earned stats),
                                                  win-rate: new-win-rate,
                                                })
                                              )
                                            )
                                            (map-set guild-stats guild-id {
                                              total-predictions: u1,
                                              wins: u0,
                                              losses: u1,
                                              total-points-earned: u0,
                                              win-rate: u0,
                                            })
                                          )
                                          ;; Return success with 0 reward to indicate loss tracked (state changes persist)
                                          (ok u0)
                                        )
                                        ERR-NO-STAKE-FOUND ;; No stake found
                                      )
                                    )
                                    ERR-NO-STAKE-FOUND ;; No stake found
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                  ERR-WINNER-NOT-SET ;; Winner not set
                )
              )
              ERR-EVENT-NOT-FOUND ;; Event not found
            )
          )
          ERR-NOT-A-MEMBER ;; Not a member
        )
      )
      ERR-GUILD-NOT-FOUND ;; Guild not found
    )
  )
)

;; read only functions

;; ============================================================================
;; 10. get-user-points (user)
;; ============================================================================
;; Purpose: Get a user's total point balance.
;;
;; Returns: (ok (some points)) or (ok none) if not registered.
;;
;; Parameters:
;;   - user: principal - The user's principal address
;;
;; Returns:
;;   - (ok (some points)) if user is registered
;;   - (ok none) if user is not registered
;; ============================================================================
(define-read-only (get-user-points (user principal))
  (match (map-get? user-points user)
    points-opt (ok (some points-opt))
    (ok none)
  )
)

;; ============================================================================
;; 11. get-earned-points (user)
;; ============================================================================
;; Purpose: Get a user's earned points (from winning predictions).
;;
;; Returns: (ok (some earned)) or (ok none) if not registered.
;;
;; Parameters:
;;   - user: principal - The user's principal address
;;
;; Returns:
;;   - (ok (some earned)) if user is registered
;;   - (ok none) if user is not registered
;;
;; Note: Earned points count toward the 10,000 threshold needed to sell points.
;; ============================================================================
(define-read-only (get-earned-points (user principal))
  (match (map-get? earned-points user)
    earned-opt (ok (some earned-opt))
    (ok none)
  )
)

;; ============================================================================
;; 12. get-username (user)
;; ============================================================================
;; Purpose: Get a user's registered username.
;;
;; Returns: (some username) or none if not registered.
;;
;; Parameters:
;;   - user: principal - The user's principal address
;;
;; Returns:
;;   - (some username) if user is registered
;;   - none if user is not registered
;; ============================================================================
(define-read-only (get-username (user principal))
  (map-get? user-names user)
)

;; ============================================================================
;; 13. can-sell (user)
;; ============================================================================
;; Purpose: Check if a user can sell points (earned >= 10,000).
;;
;; Returns: (ok true) if eligible, (ok false) otherwise.
;;
;; Parameters:
;;   - user: principal - The user's principal address
;;
;; Returns:
;;   - (ok true) if user has earned >= 10,000 points
;;   - (ok false) if user has not earned enough points or is not registered
;; ============================================================================
(define-read-only (can-sell (user principal))
  (match (map-get? earned-points user)
    earned (ok (>= earned MIN_EARNED_FOR_SELL))
    (ok false)
  )
)

;; ============================================================================
;; 14. get-event (event-id)
;; ============================================================================
;; Purpose: Get full event details.
;;
;; Returns: Event tuple with yes-pool, no-pool, status, winner, creator, metadata,
;;          or none if not found.
;;
;; Parameters:
;;   - event-id: uint - The event ID to query
;;
;; Returns:
;;   - (some event-tuple) containing:
;;     * yes-pool: uint - Total points staked on YES
;;     * no-pool: uint - Total points staked on NO
;;     * status: (string-ascii 20) - "open", "closed", or "resolved"
;;     * winner: (optional bool) - true if YES won, false if NO won, none if not resolved
;;     * creator: principal - Admin who created the event
;;     * metadata: (string-ascii 200) - Event description
;;   - none if event not found
;; ============================================================================
(define-read-only (get-event (event-id uint))
  (map-get? events event-id)
)

;; ============================================================================
;; 15. get-yes-stake (event-id, user)
;; ============================================================================
;; Purpose: Get a user's YES stake for a specific event.
;;
;; Returns: (some stake-amount) or none if no stake.
;;
;; Parameters:
;;   - event-id: uint - The event ID
;;   - user: principal - The user's principal address
;;
;; Returns:
;;   - (some stake-amount) if user has staked on YES
;;   - none if user has no YES stake
;; ============================================================================
(define-read-only (get-yes-stake
    (event-id uint)
    (user principal)
  )
  (map-get? yes-stakes {
    event-id: event-id,
    user: user,
  })
)

;; ============================================================================
;; 16. get-no-stake (event-id, user)
;; ============================================================================
;; Purpose: Get a user's NO stake for a specific event.
;;
;; Returns: (some stake-amount) or none if no stake.
;;
;; Parameters:
;;   - event-id: uint - The event ID
;;   - user: principal - The user's principal address
;;
;; Returns:
;;   - (some stake-amount) if user has staked on NO
;;   - none if user has no NO stake
;; ============================================================================
(define-read-only (get-no-stake
    (event-id uint)
    (user principal)
  )
  (map-get? no-stakes {
    event-id: event-id,
    user: user,
  })
)

;; ============================================================================
;; 16.5. get-total-yes-stakes
;; ============================================================================
;; Purpose: Get the total number of YES stakes across all events.
;;
;; Returns: uint - Total YES stakes across all events
;; ============================================================================
(define-read-only (get-total-yes-stakes)
  (var-get total-yes-stakes)
)

;; ============================================================================
;; 16.6. get-total-no-stakes
;; ============================================================================
;; Purpose: Get the total number of NO stakes across all events.
;;
;; Returns: uint - Total NO stakes across all events
;; ============================================================================
(define-read-only (get-total-no-stakes)
  (var-get total-no-stakes)
)

;; ============================================================================
;; 17. get-listing (listing-id)
;; ============================================================================
;; Purpose: Get listing details.
;;
;; Returns: Listing tuple with seller, points, price-stx, active, or none if not found.
;;
;; Parameters:
;;   - listing-id: uint - The listing ID to query
;;
;; Returns:
;;   - (some listing-tuple) containing:
;;     * seller: principal - The seller's principal address
;;     * points: uint - Number of points for sale
;;     * price-stx: uint - Price in micro-STX
;;     * active: bool - Whether the listing is active
;;   - none if listing not found
;; ============================================================================
(define-read-only (get-listing (listing-id uint))
  (map-get? listings listing-id)
)

;; ============================================================================
;; 18. get-protocol-treasury
;; ============================================================================
;; Purpose: Get the protocol treasury balance (accumulated from 2% marketplace fees).
;;
;; Returns: (ok treasury-balance) in micro-STX.
;;
;; Returns:
;;   - (ok treasury-balance) - Treasury balance in micro-STX
;;
;; Note: Treasury accumulates 2% fees from each marketplace point sale.
;; ============================================================================
(define-read-only (get-protocol-treasury)
  (ok (var-get protocol-treasury))
)

;; ============================================================================
;; 18b. get-total-admin-minted-points
;; ============================================================================
;; Purpose: Get the total points minted by admin.
;;
;; Returns: (ok total-minted-points)
;; ============================================================================
(define-read-only (get-total-admin-minted-points)
  (ok (var-get total-admin-minted-points))
)

;; ============================================================================
;; 19. get-admin
;; ============================================================================
;; Purpose: Get the admin principal address.
;;
;; Returns: (ok admin-principal).
;;
;; Returns:
;;   - (ok admin-principal) - The admin's principal address
;;
;; Note: Admin can create events and resolve them.
;; ============================================================================
(define-read-only (get-admin)
  (ok (var-get admin))
)

;; ============================================================================
;; 21. get-guild (guild-id)
;; ============================================================================
;; Purpose: Get guild details.
;;
;; Returns: Guild tuple or none if not found.
;;
;; Parameters:
;;   - guild-id: uint - The guild ID to query
;;
;; Returns:
;;   - (some guild-tuple) containing:
;;     * creator: principal - Guild creator
;;     * name: (string-ascii 50) - Guild name
;;     * total-points: uint - Total points in guild pool
;;     * member-count: uint - Number of members
;;   - none if guild not found
;; ============================================================================
(define-read-only (get-guild (guild-id uint))
  (map-get? guilds guild-id)
)

;; ============================================================================
;; 22. is-guild-member (guild-id, user)
;; ============================================================================
;; Purpose: Check if a user is a member of a guild.
;;
;; Returns: (some true) if member, none if not.
;;
;; Parameters:
;;   - guild-id: uint - The guild ID
;;   - user: principal - The user's principal address
;;
;; Returns:
;;   - (some true) if user is a member
;;   - none if user is not a member
;; ============================================================================
(define-read-only (is-guild-member
    (guild-id uint)
    (user principal)
  )
  (map-get? guild-members {
    guild-id: guild-id,
    user: user,
  })
)

;; ============================================================================
;; 23. get-guild-deposit (guild-id, user)
;; ============================================================================
;; Purpose: Get a user's deposit amount in a guild.
;;
;; Returns: (some deposit-amount) or none if no deposit.
;;
;; Parameters:
;;   - guild-id: uint - The guild ID
;;   - user: principal - The user's principal address
;;
;; Returns:
;;   - (some deposit-amount) if user has deposits
;;   - none if user has no deposits
;; ============================================================================
(define-read-only (get-guild-deposit
    (guild-id uint)
    (user principal)
  )
  (map-get? guild-deposits {
    guild-id: guild-id,
    user: user,
  })
)

;; ============================================================================
;; 24. get-guild-yes-stake (guild-id, event-id)
;; ============================================================================
;; Purpose: Get a guild's YES stake for a specific event.
;;
;; Returns: (some stake-amount) or none if no stake.
;;
;; Parameters:
;;   - guild-id: uint - The guild ID
;;   - event-id: uint - The event ID
;;
;; Returns:
;;   - (some stake-amount) if guild has staked on YES
;;   - none if guild has no YES stake
;; ============================================================================
(define-read-only (get-guild-yes-stake
    (guild-id uint)
    (event-id uint)
  )
  (map-get? guild-yes-stakes {
    guild-id: guild-id,
    event-id: event-id,
  })
)

;; ============================================================================
;; 25. get-guild-no-stake (guild-id, event-id)
;; ============================================================================
;; Purpose: Get a guild's NO stake for a specific event.
;;
;; Returns: (some stake-amount) or none if no stake.
;;
;; Parameters:
;;   - guild-id: uint - The guild ID
;;   - event-id: uint - The event ID
;;
;; Returns:
;;   - (some stake-amount) if guild has staked on NO
;;   - none if guild has no NO stake
;; ============================================================================
(define-read-only (get-guild-no-stake
    (guild-id uint)
    (event-id uint)
  )
  (map-get? guild-no-stakes {
    guild-id: guild-id,
    event-id: event-id,
  })
)

;; ============================================================================
;; 26.5. get-total-guild-yes-stakes
;; ============================================================================
;; Purpose: Get the total number of guild YES stakes across all events.
;;
;; Returns: uint - Total guild YES stakes across all events
;; ============================================================================
(define-read-only (get-total-guild-yes-stakes)
  (var-get total-guild-yes-stakes)
)

;; ============================================================================
;; 26.6. get-total-guild-no-stakes
;; ============================================================================
;; Purpose: Get the total number of guild NO stakes across all events.
;;
;; Returns: uint - Total guild NO stakes across all events
;; ============================================================================
(define-read-only (get-total-guild-no-stakes)
  (var-get total-guild-no-stakes)
)

;; ============================================================================
;; 27. get-user-stats (user)
;; ============================================================================
;; Purpose: Get user leaderboard statistics.
;;
;; Returns: User stats tuple or none if not found.
;;
;; Parameters:
;;   - user: principal - The user's principal address
;;
;; Returns:
;;   - (some stats-tuple) containing:
;;     * total-predictions: uint - Total number of predictions made
;;     * wins: uint - Number of winning predictions
;;     * losses: uint - Number of losing predictions
;;     * total-points-earned: uint - Total points earned from predictions
;;     * win-rate: uint - Win rate as percentage (0-10000, where 10000 = 100%)
;;   - none if user has no stats
;;
;; Note: Use this to build user leaderboards showing prediction performance.
;; ============================================================================
(define-read-only (get-user-stats (user principal))
  (map-get? user-stats user)
)

;; ============================================================================
;; 28. get-guild-stats (guild-id)
;; ============================================================================
;; Purpose: Get guild leaderboard statistics.
;;
;; Returns: Guild stats tuple or none if not found.
;;
;; Parameters:
;;   - guild-id: uint - The guild ID to query
;;
;; Returns:
;;   - (some stats-tuple) containing:
;;     * total-predictions: uint - Total number of predictions made
;;     * wins: uint - Number of winning predictions
;;     * losses: uint - Number of losing predictions
;;     * total-points-earned: uint - Total points earned from predictions
;;     * win-rate: uint - Win rate as percentage (0-10000, where 10000 = 100%)
;;   - none if guild has no stats
;;
;; Note: Use this to build guild leaderboards showing collaborative prediction performance.
;; ============================================================================
(define-read-only (get-guild-stats (guild-id uint))
  (map-get? guild-stats guild-id)
)

;; ============================================================================
;; 29. get-transaction-log (log-id)
;; ============================================================================
;; Purpose: Get a transaction log entry (for event tracking).
;;
;; Returns: Transaction log tuple or none if not found.
;;
;; Parameters:
;;   - log-id: uint - The transaction log ID to query
;;
;; Returns:
;;   - (some log-tuple) containing:
;;     * action: (string-ascii 30) - Action type
;;     * user: principal - User who performed the action
;;     * event-id: (optional uint) - Event ID if applicable
;;     * listing-id: (optional uint) - Listing ID if applicable
;;     * amount: (optional uint) - Amount if applicable
;;     * metadata: (string-ascii 200) - Additional metadata
;;   - none if log not found
;;
;; Note: This is used for event tracking since Clarity doesn't have native events.
;;       Frontend applications can query this to track contract activity.
;; ============================================================================
(define-read-only (get-transaction-log (log-id uint))
  (map-get? transaction-logs log-id)
)

;; private functions

;; Helper function to check if user is guild member
(define-private (is-member?
    (guild-id uint)
    (user principal)
  )
  (match (map-get? guild-members {
    guild-id: guild-id,
    user: user,
  })
    member-status
    member-status
    false
  )
)

;; ============================================================================
;; 20. increase-points (user, amount)
;; ============================================================================
;; Purpose: Internal helper to increase a user's points.
;;
;; Details:
;;   - Adds amount to user's total points
;;   - Creates entry if user doesn't exist
;;   - Returns (ok true)
;;
;; Note: Currently defined but not used (rewards are handled directly in claim).
;;       Could be used for future features like bonuses or airdrops.
;;
;; Parameters:
;;   - user: principal - The user's principal address
;;   - amount: uint - Points to add
;;
;; Returns:
;;   - (ok true) on success
;; ============================================================================
(define-private (increase-points
    (user principal)
    (amount uint)
  )
  (match (map-get? user-points user)
    current-points (begin
      (map-set user-points user (+ current-points amount))
      (ok true)
    )
    (begin
      (map-set user-points user amount)
      (ok true)
    )
  )
)
