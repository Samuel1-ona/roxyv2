;; title: roxy-trait
;; version: 1.1.0
;; summary: Trait definition for Roxy Gaming SDK integration.

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
    
    ;; Score Syncing
    (sync-score (uint principal <roxy-game-trait>) (response uint uint))
    
    ;; Prediction Market
    (create-match (uint (string-ascii 200)) (response uint uint))
    (stake (uint uint bool) (response bool uint))
    (resolve-match (uint bool) (response bool uint))
    (claim-reward (uint) (response bool uint))
  )
)
