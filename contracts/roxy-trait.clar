;; title: roxy-trait
;; version: 1.0.0
;; summary: Trait definition for Roxy Gaming SDK integration.

(define-trait roxy-game-trait
  (
    ;; Get current score/points for a player in a specific campaign
    ;; Returns (ok uint) or (err uint)
    (get-player-score (uint principal) (response uint uint))
  )
)
