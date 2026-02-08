;; title: roxy-trait
;; version: 1.7.0
;; summary: Trait definition for Roxy Gaming SDK integration with match creation fee support.

(define-trait roxy-game-trait
  (
    ;; Get current score/points for a player in a specific campaign
    (get-player-score (uint principal) (response uint uint))
  )
)

(define-trait roxy-sdk-trait
  (
    ;; Campaign Management
    (create-campaign ((buff 32) principal uint uint uint) (response uint uint))
    (join-campaign (uint (optional principal)) (response bool uint))
    (onboard-player (uint principal (optional principal)) (response bool uint))
    (update-campaign-status (uint (string-ascii 20)) (response bool uint))
    (set-campaign-metadata (uint (buff 32)) (response bool uint))
    (set-campaign-winner (uint principal) (response bool uint))
    (claim-campaign-prize (uint) (response uint uint))
    (claim-campaign-prize-for (uint principal) (response uint uint))
    
    ;; Score Syncing
    (sync-score (uint principal <roxy-game-trait>) (response uint uint))
    (sync-scores-batch ((list 50 { campaign-id: uint, player: principal, score: uint }) <roxy-game-trait>) (response (list 50 uint) uint))
    (sync-player-state (uint principal (buff 32) <roxy-game-trait>) (response bool uint))
    
    ;; Prediction Market
    (create-match (uint (buff 32)) (response uint uint))
    (stake (uint uint bool) (response bool uint))
    (stake-for (uint uint bool principal) (response bool uint))
    (resolve-match (uint bool) (response bool uint))
    (cancel-match (uint) (response bool uint))
    (refund-stake (uint) (response uint uint))
    (refund-stake-for (uint principal) (response uint uint))
    (claim-reward (uint) (response bool uint))
    (claim-reward-for (uint principal) (response uint uint))

    ;; User Management
    (set-username ((string-ascii 50)) (response bool uint))
    (set-player-username (principal (string-ascii 50) uint) (response bool uint))

    ;; Admin/Governance
    (set-campaign-creation-fee (uint) (response bool uint))
    (set-match-creation-fee (uint) (response bool uint))
    (set-stx-per-usd (uint) (response bool uint))
    (set-paused (bool) (response bool uint))
    (propose-admin (principal) (response bool uint))
    (claim-admin () (response bool uint))

    ;; Getters
    (get-campaign (uint) (response (optional {
      creator: principal,
      metadata-hash: (buff 32),
      prize-pool: uint,
      reporter: principal,
      start-time: uint,
      end-time: uint,
      status: (string-ascii 20),
      winner: (optional principal),
      scoring-mode: uint
    }) uint))
    (get-event (uint) (response (optional {
      campaign-id: uint,
      yes-pool: uint,
      no-pool: uint,
      status: (string-ascii 20),
      winner: (optional bool),
      metadata-hash: (buff 32)
    }) uint))
    (get-leaderboard-score (uint principal) (response uint uint))
    (get-player-state (uint principal) (response (optional (buff 32)) uint))
    (get-participant-status (uint principal) (response bool uint))
    (get-yes-stake (uint principal) (response uint uint))
    (get-no-stake (uint principal) (response uint uint))
    (get-referral (uint principal) (response (optional principal) uint))
    (get-user-profile (principal) (response (optional { username: (string-ascii 50) }) uint))
    (get-user-by-username ((string-ascii 50)) (response (optional principal) uint))
    (get-admin () (response principal uint))
    (get-protocol-treasury () (response uint uint))
    (get-campaign-creation-fee () (response uint uint))
    (get-match-creation-fee () (response uint uint))
    (get-stx-per-usd () (response uint uint))
  )
)
