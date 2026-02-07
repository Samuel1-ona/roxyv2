;; title: roxy-trait
;; version: 1.6.0
;; summary: Trait definition for Roxy Gaming SDK integration with a complete set of response-based getters.

(define-trait roxy-game-trait
  (
    ;; Get current score/points for a player in a specific campaign
    (get-player-score (uint principal) (response uint uint))
  )
)

(define-trait roxy-sdk-trait
  (
    ;; Campaign Management
    (create-campaign ((buff 32) principal uint uint) (response uint uint))
    (join-campaign (uint (optional principal)) (response bool uint))
    (update-campaign-status (uint (string-ascii 20)) (response bool uint))
    
    ;; Score Syncing
    (sync-score (uint principal <roxy-game-trait>) (response uint uint))
    
    ;; Prediction Market
    (create-match (uint (string-ascii 200)) (response uint uint))
    (stake (uint uint bool) (response bool uint))
    (resolve-match (uint bool) (response bool uint))
    (claim-reward (uint) (response bool uint))

    ;; User Management
    (set-username ((string-ascii 50)) (response bool uint))

    ;; Getters
    (get-campaign (uint) (response (optional {
      creator: principal,
      metadata-hash: (buff 32),
      prize-pool: uint,
      reporter: principal,
      start-time: uint,
      end-time: uint,
      status: (string-ascii 20)
    }) uint))
    (get-event (uint) (response (optional {
      campaign-id: uint,
      yes-pool: uint,
      no-pool: uint,
      status: (string-ascii 20),
      winner: (optional bool),
      metadata: (string-ascii 200)
    }) uint))
    (get-leaderboard-score (uint principal) (response uint uint))
    (get-participant-status (uint principal) (response bool uint))
    (get-yes-stake (uint principal) (response uint uint))
    (get-no-stake (uint principal) (response uint uint))
    (get-referral (uint principal) (response (optional principal) uint))
    (get-user-profile (principal) (response (optional { username: (string-ascii 50) }) uint))
    (get-user-by-username ((string-ascii 50)) (response (optional principal) uint))
    (get-admin () (response principal uint))
    (get-protocol-treasury () (response uint uint))
    (get-campaign-creation-fee () (response uint uint))
    (get-stx-per-usd () (response uint uint))
  )
)
