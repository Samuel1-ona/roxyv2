;; title: game-example
;; summary: A simple clicker game integrating with Roxy SDK

(use-trait roxy-game-trait 'STVAH96MR73TP2FZG2W4X220MEB4NEMJHPMVYQNS.roxy-trait.roxy-game-trait)
(use-trait roxy-sdk-trait 'STVAH96MR73TP2FZG2W4X220MEB4NEMJHPMVYQNS.roxy-trait.roxy-sdk-trait)

;; constants
(define-constant ERR-NOT-AUTHORIZED (err u401))

;; data maps
(define-map scores
    {
        campaign-id: uint,
        player: principal,
    }
    uint
)

;; --- Game Logic ---

;; @desc Increments the player's score for a specific campaign
(define-public (click (campaign-id uint))
    (let ((current-score (default-to u0
            (map-get? scores {
                campaign-id: campaign-id,
                player: tx-sender,
            })
        )))
        (ok (map-set scores {
            campaign-id: campaign-id,
            player: tx-sender,
        }
            (+ current-score u1)
        ))
    )
)

;; --- Roxy Game Trait Implementation ---

(define-read-only (get-player-score
        (campaign-id uint)
        (player principal)
    )
    (ok (default-to u0
        (map-get? scores {
            campaign-id: campaign-id,
            player: player,
        })
    ))
)

;; --- Roxy SDK Wrappers ---

;; Wrapper for testing create-campaign
(define-public (sdk-create-campaign
        (sdk <roxy-sdk-trait>)
        (metadata-hash (buff 32))
        (reporter principal)
        (start-time uint)
        (end-time uint)
        (scoring-mode uint)
    )
    (contract-call? sdk create-campaign metadata-hash reporter start-time
        end-time scoring-mode
    )
)

;; Wrapper for testing join-campaign
(define-public (sdk-join-campaign
        (sdk <roxy-sdk-trait>)
        (campaign-id uint)
        (referrer (optional principal))
    )
    (contract-call? sdk join-campaign campaign-id referrer)
    
)

;; Wrapper for testing onboard-player
(define-public (sdk-onboard-player
        (sdk <roxy-sdk-trait>)
        (campaign-id uint)
        (player principal)
        (referrer (optional principal))
    )
    (contract-call? sdk onboard-player campaign-id player referrer)
)

;; Wrapper for testing sync-score
(define-public (sdk-sync-score
        (sdk <roxy-sdk-trait>)
        (campaign-id uint)
        (player principal)
        (game-contract <roxy-game-trait>)
    )
    (contract-call? sdk sync-score campaign-id player game-contract)
)

;; Wrapper for testing set-username
(define-public (sdk-set-username
        (sdk <roxy-sdk-trait>)
        (username (string-ascii 50))
    )
    (contract-call? sdk set-username username)
)

;; Wrapper for testing create-match
(define-public (sdk-create-match
        (sdk <roxy-sdk-trait>)
        (campaign-id uint)
        (metadata-hash (buff 32))
    )
    (contract-call? sdk create-match campaign-id metadata-hash)
)

;; Wrapper for testing stake
(define-public (sdk-stake
        (sdk <roxy-sdk-trait>)
        (event-id uint)
        (amount uint)
        (is-yes bool)
    )
    (contract-call? sdk stake event-id amount is-yes)
)

;; Wrapper for testing resolve-match
(define-public (sdk-resolve-match
        (sdk <roxy-sdk-trait>)
        (event-id uint)
        (winner bool)
    )
    (contract-call? sdk resolve-match event-id winner)
)
