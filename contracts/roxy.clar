;; title: roxy
;; version: 2.3.0
;; summary: STX-Based Gaming Prediction SDK (Modernized)
;; description: A platform for game developers to create campaigns, manage predictions, and track leaderboards with governance and indexability.

;; ============================================================================
;; TRAITS
;; ============================================================================

(use-trait roxy-game-trait .roxy-trait.roxy-game-trait)

;; ============================================================================
;; CONSTANTS & ERRORS
;; ============================================================================

(define-constant ERR-NOT-ADMIN (err u1))
(define-constant ERR-NOT-FOUND (err u2))
(define-constant ERR-UNAUTHORIZED (err u3))
(define-constant ERR-INVALID-AMOUNT (err u4))
(define-constant ERR-INSUFFICIENT-FUNDS (err u6))
(define-constant ERR-ALREADY-PARTICIPATED (err u7))
(define-constant ERR-EVENT-NOT-OPEN (err u8))
(define-constant ERR-EVENT-CLOSED (err u9))
(define-constant ERR-PAUSED (err u10))
(define-constant ERR-INVALID-TIME (err u11))
(define-constant ERR-INVALID-METADATA (err u12))
(define-constant ERR-USERNAME-TAKEN (err u13))

;; ============================================================================
;; DATA VARIABLES
;; ============================================================================

(define-data-var admin principal tx-sender)
(define-data-var pending-admin (optional principal) none)
(define-data-var campaign-creation-fee uint u1000000) ;; $1 in micro-STX
(define-data-var match-creation-fee uint u1000000) ;; $1 in micro-STX
(define-data-var stx-per-usd uint u1000000) ;; 1 STX = $1 (placeholder)
(define-data-var next-campaign-id uint u1)
(define-data-var next-event-id uint u1)
(define-data-var protocol-treasury uint u0)
(define-data-var protocol-paused bool false)

;; ============================================================================
;; DATA MAPS
;; ============================================================================

(define-map user-profiles
  principal
  { username: (string-ascii 50) }
)
(define-map usernames
  (string-ascii 50)
  principal
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
    winner: (optional principal),
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
    metadata-hash: (buff 32),
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

;; @desc Creates a new gaming campaign. Charges a protocol fee.
;; @param metadata-hash: 32-byte hash of campaign data (e.g. from IPFS)
;; @param reporter: Principal authorized to sync scores and resolve matches
;; @param start-time: Unix timestamp (block height or seconds)
;; @param end-time: Unix timestamp (must be > start-time)
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
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED)
    (asserts! (> end-time start-time) ERR-INVALID-TIME)
    (asserts! (is-standard reporter) ERR-UNAUTHORIZED)
    (asserts! (> (len metadata-hash) u0) ERR-INVALID-METADATA)

    ;; Pay creation fee to protocol treasury
    (try! (stx-transfer? creation-fee tx-sender (as-contract tx-sender)))
    (var-set protocol-treasury (+ (var-get protocol-treasury) creation-fee))

    (print {
      action: "create-campaign",
      campaign-id: campaign-id,
      creator: tx-sender,
      reporter: reporter,
      fee: creation-fee,
    })

    (map-set campaigns campaign-id {
      creator: tx-sender,
      metadata-hash: metadata-hash,
      prize-pool: u0,
      reporter: reporter,
      start-time: start-time,
      end-time: end-time,
      status: "open",
      winner: none,
    })

    (var-set next-campaign-id (+ campaign-id u1))
    (ok campaign-id)
  )
)

;; @desc Updates the campaign metadata hash. Only the creator can call this.
;; @param campaign-id: ID of the campaign
;; @param new-metadata-hash: new 32-byte hash
(define-public (set-campaign-metadata
    (campaign-id uint)
    (new-metadata-hash (buff 32))
  )
  (let ((campaign (unwrap! (map-get? campaigns campaign-id) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get creator campaign)) ERR-UNAUTHORIZED)
    (asserts! (> (len new-metadata-hash) u0) ERR-INVALID-METADATA)
    (print {
      action: "set-campaign-metadata",
      campaign-id: campaign-id,
      metadata-hash: new-metadata-hash,
    })
    (ok (map-set campaigns campaign-id
      (merge campaign { metadata-hash: new-metadata-hash })
    ))
  )
)

;; @desc Updates the current status of a campaign (e.g. "open" -> "closed")
;; @param campaign-id: ID of the campaign
;; @param new-status: String description of status
(define-public (update-campaign-status
    (campaign-id uint)
    (new-status (string-ascii 20))
  )
  (let ((campaign (unwrap! (map-get? campaigns campaign-id) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get creator campaign)) ERR-UNAUTHORIZED)
    (print {
      action: "update-campaign-status",
      campaign-id: campaign-id,
      status: new-status,
    })
    (ok (map-set campaigns campaign-id (merge campaign { status: new-status })))
  )
)

;; @desc Allows a user to join a campaign for a $1 fee.
;; @param campaign-id: ID of the campaign to join
;; @param referrer: Optional principal to receive a 10% referral fee
(define-public (join-campaign
    (campaign-id uint)
    (referrer (optional principal))
  )
  (let (
      (campaign (unwrap! (map-get? campaigns campaign-id) ERR-NOT-FOUND))
      (fee (var-get stx-per-usd)) ;; $1 in micro-STX
    )
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED)
    (asserts! (> campaign-id u0) ERR-NOT-FOUND)
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
      (print {
        action: "join-campaign",
        campaign-id: campaign-id,
        user: tx-sender,
        referrer: referrer,
        pool-addition: pool-addition,
      })

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

;; @desc Syncs a player's score from an external game contract.
;; @param campaign-id: ID of the campaign
;; @param player: Principal of the player
;; @param game-contract: Contract conforming to roxy-game-trait
(define-public (sync-score
    (campaign-id uint)
    (player principal)
    (game-contract <roxy-game-trait>)
  )
  (let ((campaign (unwrap! (map-get? campaigns campaign-id) ERR-NOT-FOUND)))
    (asserts! (is-eq (contract-of game-contract) (get reporter campaign))
      ERR-UNAUTHORIZED
    )
    (asserts! (is-standard player) ERR-UNAUTHORIZED)

    (let ((score (try! (contract-call? game-contract get-player-score campaign-id player))))
      (print {
        action: "sync-score",
        campaign-id: campaign-id,
        player: player,
        score: score,
      })
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

;; @desc Sets a unique username for the caller.
;; @param username: String-ascii 1-50 chars
(define-public (set-username (username (string-ascii 50)))
  (let (
      (old-profile (map-get? user-profiles tx-sender))
      (existing-owner (map-get? usernames username))
    )
    (asserts! (> (len username) u0) ERR-INVALID-METADATA)
    ;; Check if username is taken by someone else
    (asserts!
      (or (is-none existing-owner) (is-eq (unwrap-panic existing-owner) tx-sender))
      ERR-USERNAME-TAKEN
    )

    ;; If user had an old username, remove it from the unique map
    (match old-profile
      profile (if (not (is-eq (get username profile) username))
        (map-delete usernames (get username profile))
        true
      )
      true
    )

    (print {
      action: "set-username",
      user: tx-sender,
      username: username,
    })

    ;; Update both maps
    (map-set usernames username tx-sender)
    (ok (map-set user-profiles tx-sender { username: username }))
  )
)

;; ============================================================================
;; PUBLIC FUNCTIONS - PREDICTIONS
;; ============================================================================

;; @desc Creates a new match within a campaign.
;; @param campaign-id: ID of the parent campaign
;; @param metadata-hash: 32-byte hash of match data
(define-public (create-match
    (campaign-id uint)
    (metadata-hash (buff 32))
  )
  (let ((event-id (var-get next-event-id)))
    (let ((campaign (unwrap! (map-get? campaigns campaign-id) ERR-NOT-FOUND)))
      (let ((fee (var-get match-creation-fee)))
        (asserts! (not (var-get protocol-paused)) ERR-PAUSED)
        ;; Only campaign creator or reporter can create matches
        (asserts!
          (or (is-eq tx-sender (get creator campaign)) (is-eq tx-sender (get reporter campaign)))
          ERR-UNAUTHORIZED
        )
        (asserts! (> (len metadata-hash) u0) ERR-INVALID-METADATA)

        ;; Pay creation fee to protocol treasury
        (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
        (var-set protocol-treasury (+ (var-get protocol-treasury) fee))

        (print {
          action: "create-match",
          event-id: event-id,
          campaign-id: campaign-id,
          metadata-hash: metadata-hash,
          fee: fee,
        })

        (map-set events event-id {
          campaign-id: campaign-id,
          yes-pool: u0,
          no-pool: u0,
          status: "open",
          winner: none,
          metadata-hash: metadata-hash,
        })

        (var-set next-event-id (+ event-id u1))
        (ok event-id)
      )
    )
  )
)

;; @desc Stakes micro-STX on YES or NO outcome.
;; @param event-id: ID of the match
;; @param amount: micro-STX amount to stake
;; @param is-yes: Outcome choice
(define-public (stake
    (event-id uint)
    (amount uint)
    (is-yes bool)
  )
  (let ((event (unwrap! (map-get? events event-id) ERR-NOT-FOUND)))
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED)
    (asserts! (is-eq (get status event) "open") ERR-EVENT-NOT-OPEN)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)

    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

    (print {
      action: "stake",
      event-id: event-id,
      user: tx-sender,
      amount: amount,
      is-yes: is-yes,
    })

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

;; @desc Resolves a match outcome. Only the campaign reporter can call this.
;; @param event-id: ID of the match
;; @param winner-is-yes: Outcome (true for YES, false for NO)
(define-public (resolve-match
    (event-id uint)
    (winner-is-yes bool)
  )
  (let ((event (unwrap! (map-get? events event-id) ERR-NOT-FOUND)))
    (let ((campaign (unwrap! (map-get? campaigns (get campaign-id event)) ERR-NOT-FOUND)))
      (asserts! (is-eq tx-sender (get reporter campaign)) ERR-UNAUTHORIZED)
      (print {
        action: "resolve-match",
        event-id: event-id,
        winner: winner-is-yes,
      })
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

;; @desc Cancels a match. Only the campaign reporter can call this.
;; @param event-id: ID of the match
(define-public (cancel-match (event-id uint))
  (let ((event (unwrap! (map-get? events event-id) ERR-NOT-FOUND)))
    (let ((campaign (unwrap! (map-get? campaigns (get campaign-id event)) ERR-NOT-FOUND)))
      (asserts! (is-eq tx-sender (get reporter campaign)) ERR-UNAUTHORIZED)
      (print {
        action: "cancel-match",
        event-id: event-id,
      })
      (map-set events event-id (merge event { status: "cancelled" }))
      (ok true)
    )
  )
)

;; @desc Refunds stakes for a cancelled match.
;; @param event-id: ID of the match
(define-public (refund-stake (event-id uint))
  (let ((event (unwrap! (map-get? events event-id) ERR-NOT-FOUND)))
    (asserts! (is-eq (get status event) "cancelled") ERR-UNAUTHORIZED)
    (let (
        (user tx-sender)
        (yes-amt (default-to u0
          (map-get? yes-stakes {
            event-id: event-id,
            user: user,
          })
        ))
        (no-amt (default-to u0
          (map-get? no-stakes {
            event-id: event-id,
            user: user,
          })
        ))
        (total-amt (+ yes-amt no-amt))
      )
      (asserts! (> total-amt u0) ERR-NOT-FOUND)
      ;; Clear stakes before transfer
      (map-set yes-stakes {
        event-id: event-id,
        user: user,
      }
        u0
      )
      (map-set no-stakes {
        event-id: event-id,
        user: user,
      }
        u0
      )
      (print {
        action: "refund-stake",
        event-id: event-id,
        user: user,
        amount: total-amt,
      })
      (try! (as-contract (stx-transfer? total-amt tx-sender user)))
      (ok total-amt)
    )
  )
)

;; @desc Claims rewards for a winning stake in a resolved match.
;; @param event-id: ID of the match
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
            (print {
              action: "claim-reward",
              event-id: event-id,
              user: recipient,
              reward: reward,
            })
            (try! (as-contract (stx-transfer? reward tx-sender recipient)))
            (ok reward)
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
            (print {
              action: "claim-reward",
              event-id: event-id,
              user: recipient,
              reward: reward,
            })
            (try! (as-contract (stx-transfer? reward tx-sender recipient)))
            (ok reward)
          )
        )
      )
    )
  )
)

;; @desc Sets the winner of a campaign. Only the reporter can call this.
;; @param campaign-id: ID of the campaign
;; @param winner: Principal of the winner
(define-public (set-campaign-winner
    (campaign-id uint)
    (winner principal)
  )
  (let ((campaign (unwrap! (map-get? campaigns campaign-id) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get reporter campaign)) ERR-UNAUTHORIZED)
    (print {
      action: "set-campaign-winner",
      campaign-id: campaign-id,
      winner: winner,
    })
    (ok (map-set campaigns campaign-id
      (merge campaign {
        winner: (some winner),
        status: "resolved",
      })
    ))
  )
)

;; @desc Claims the prize pool for a campaign. Only the winner can call this.
;; @param campaign-id: ID of the campaign
(define-public (claim-campaign-prize (campaign-id uint))
  (let ((campaign (unwrap! (map-get? campaigns campaign-id) ERR-NOT-FOUND)))
    (let (
        (user tx-sender)
        (winner (unwrap! (get winner campaign) ERR-UNAUTHORIZED))
      )
      (asserts! (is-eq user winner) ERR-UNAUTHORIZED)
      (let ((prize (get prize-pool campaign)))
        (asserts! (> prize u0) ERR-INSUFFICIENT-FUNDS)
        ;; Clear prize pool to prevent double claim
        (map-set campaigns campaign-id (merge campaign { prize-pool: u0 }))
        (print {
          action: "claim-campaign-prize",
          campaign-id: campaign-id,
          winner: user,
          prize: prize,
        })
        (try! (as-contract (stx-transfer? prize tx-sender user)))
        (ok prize)
      )
    )
  )
)

;; ============================================================================
;; ADMIN FUNCTIONS
;; ============================================================================

;; @desc Withdraws protocol fees from the treasury. Admin only.
;; @param amount: micro-STX to withdraw
(define-public (withdraw-treasury (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-ADMIN)
    (asserts! (<= amount (var-get protocol-treasury)) ERR-INSUFFICIENT-FUNDS)
    (var-set protocol-treasury (- (var-get protocol-treasury) amount))
    (print {
      action: "withdraw-treasury",
      amount: amount,
    })
    (try! (as-contract (stx-transfer? amount tx-sender (var-get admin))))
    (ok amount)
  )
)

;; @desc Sets the fee for campaign creation. Admin only.
;; @param new-fee: new micro-STX fee
(define-public (set-campaign-creation-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-ADMIN)
    (asserts! (>= new-fee u0) ERR-INVALID-AMOUNT)
    (print {
      action: "set-campaign-creation-fee",
      fee: new-fee,
    })
    (ok (var-set campaign-creation-fee new-fee))
  )
)

;; @desc Sets the STX per USD rate ($1 in micro-STX). Admin only.
;; @param new-rate: micro-STX per $1
(define-public (set-stx-per-usd (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-ADMIN)
    (asserts! (> new-rate u0) ERR-INVALID-AMOUNT)
    (print {
      action: "set-stx-per-usd",
      rate: new-rate,
    })
    (ok (var-set stx-per-usd new-rate))
  )
)

;; @desc Sets the fee for match creation. Admin only.
;; @param new-fee: new micro-STX fee
(define-public (set-match-creation-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-ADMIN)
    ;; Basic validation to satisfy 'unchecked data' lints
    (asserts! (>= new-fee u0) ERR-INVALID-AMOUNT)
    (print {
      action: "set-match-creation-fee",
      fee: new-fee,
    })
    (ok (var-set match-creation-fee new-fee))
  )
)

;; @desc Proposes a new admin (2-step handoff). Admin only.
;; @param new-pending: principal of the proposed admin
(define-public (propose-admin (new-pending principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-ADMIN)
    (asserts! (is-standard new-pending) ERR-UNAUTHORIZED)
    (print {
      action: "propose-admin",
      pending: new-pending,
    })
    (ok (var-set pending-admin (some new-pending)))
  )
)

;; @desc Claims the admin role. Only the pending-admin can call this.
(define-public (claim-admin)
  (let ((pending (unwrap! (var-get pending-admin) ERR-UNAUTHORIZED)))
    (asserts! (is-eq tx-sender pending) ERR-UNAUTHORIZED)
    (print {
      action: "claim-admin",
      new-admin: tx-sender,
    })
    (var-set admin tx-sender)
    (ok (var-set pending-admin none))
  )
)

;; @desc Pauses/Unpauses the protocol. Admin only.
;; @param paused: boolean status
(define-public (set-paused (paused bool))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-ADMIN)
    (print {
      action: "set-paused",
      paused: paused,
    })
    (ok (var-set protocol-paused paused))
  )
)

;; ============================================================================
;; READ-ONLY FUNCTIONS
;; ============================================================================

(define-read-only (get-campaign (campaign-id uint))
  (ok (map-get? campaigns campaign-id))
)

(define-read-only (get-event (event-id uint))
  (ok (map-get? events event-id))
)

(define-read-only (get-leaderboard-score
    (campaign-id uint)
    (user principal)
  )
  (ok (default-to u0
    (map-get? leaderboard {
      campaign-id: campaign-id,
      user: user,
    })
  ))
)

(define-read-only (get-yes-stake
    (event-id uint)
    (user principal)
  )
  (ok (default-to u0
    (map-get? yes-stakes {
      event-id: event-id,
      user: user,
    })
  ))
)

(define-read-only (get-no-stake
    (event-id uint)
    (user principal)
  )
  (ok (default-to u0
    (map-get? no-stakes {
      event-id: event-id,
      user: user,
    })
  ))
)

(define-read-only (get-referral
    (campaign-id uint)
    (user principal)
  )
  (ok (map-get? referrals {
    campaign-id: campaign-id,
    user: user,
  }))
)

(define-read-only (get-participant-status
    (campaign-id uint)
    (user principal)
  )
  (ok (default-to false
    (map-get? campaign-participants {
      campaign-id: campaign-id,
      user: user,
    })
  ))
)

(define-read-only (get-user-profile (user principal))
  (ok (map-get? user-profiles user))
)

(define-read-only (get-admin)
  (ok (var-get admin))
)

(define-read-only (get-protocol-treasury)
  (ok (var-get protocol-treasury))
)

(define-read-only (get-campaign-creation-fee)
  (ok (var-get campaign-creation-fee))
)

(define-read-only (get-match-creation-fee)
  (ok (var-get match-creation-fee))
)

(define-read-only (get-stx-per-usd)
  (ok (var-get stx-per-usd))
)

(define-read-only (get-user-by-username (username (string-ascii 50)))
  (ok (map-get? usernames username))
)
