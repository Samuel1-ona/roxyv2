import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;
const deployer = accounts.get("deployer")!;

const contractName = `${simnet.deployer}.roxy`;

describe("Roxy SDK v2.2.0 Tests", () => {
  it("ensures the contract is deployed", () => {
    const contractSource = simnet.getContractSource("roxy");
    expect(contractSource).toBeDefined();
  });

  describe("User Profiles", () => {
    it("should set a unique username successfully", () => {
      const { result } = simnet.callPublicFn(contractName, "set-username", [Cl.stringAscii("roxy_hero")], address1);
      expect(result).toBeOk(Cl.bool(true));

      const { result: profile } = simnet.callReadOnlyFn(contractName, "get-user-profile", [Cl.principal(address1)], address1);
      expect(profile).toBeOk(Cl.some(Cl.tuple({ username: Cl.stringAscii("roxy_hero") })));
    });

    it("should fail if username is taken", () => {
      simnet.callPublicFn(contractName, "set-username", [Cl.stringAscii("taken")], address1);
      const { result } = simnet.callPublicFn(contractName, "set-username", [Cl.stringAscii("taken")], address2);
      expect(result).toBeErr(Cl.uint(13)); // ERR-USERNAME-TAKEN
    });
  });

  describe("Campaign Management", () => {
    const metadataHash = new Uint8Array(32).fill(1);
    const reporter = address2;

    it("should create a campaign successfully", () => {
      const { result } = simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(1000), Cl.uint(2000), Cl.uint(0)], address1);
      expect(result).toBeOk(Cl.uint(1));
    });

    it("should allow a user to join a campaign without a referrer", () => {
      expect(simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(1000), Cl.uint(2000), Cl.uint(0)], address1).result).toBeOk(Cl.uint(1));
      expect(simnet.callPublicFn(contractName, "join-campaign", [Cl.uint(1), Cl.none()], address2).result).toBeOk(Cl.bool(true));

      const { result: campaign } = simnet.callReadOnlyFn(contractName, "get-campaign", [Cl.uint(1)], deployer);
      expect(campaign).toBeOk(Cl.some(Cl.tuple({
        creator: Cl.principal(address1),
        "metadata-hash": Cl.buffer(metadataHash),
        "prize-pool": Cl.uint(1000000),
        reporter: Cl.principal(reporter),
        "start-time": Cl.uint(1000),
        "end-time": Cl.uint(2000),
        status: Cl.stringAscii("open"),
        winner: Cl.none(),
        "scoring-mode": Cl.uint(0)
      })));
    });

    it("should allow updating campaign metadata", () => {
      expect(simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(1000), Cl.uint(2000), Cl.uint(0)], address1).result).toBeOk(Cl.uint(1));

      const newHash = new Uint8Array(32).fill(2);
      const { result } = simnet.callPublicFn(contractName, "set-campaign-metadata", [Cl.uint(1), Cl.buffer(newHash)], address1);
      expect(result).toBeOk(Cl.bool(true));

      const { result: campaign } = simnet.callReadOnlyFn(contractName, "get-campaign", [Cl.uint(1)], deployer);
      expect(campaign).toBeOk(Cl.some(Cl.tuple({
        creator: Cl.principal(address1),
        "metadata-hash": Cl.buffer(newHash),
        "prize-pool": Cl.uint(0),
        reporter: Cl.principal(reporter),
        "start-time": Cl.uint(1000),
        "end-time": Cl.uint(2000),
        status: Cl.stringAscii("open"),
        winner: Cl.none(),
        "scoring-mode": Cl.uint(0)
      })));
    });

    it("should handle campaign prize distribution", () => {
      // 1. Create and Join
      expect(simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(1000), Cl.uint(2000), Cl.uint(0)], address1).result).toBeOk(Cl.uint(1));
      expect(simnet.callPublicFn(contractName, "join-campaign", [Cl.uint(1), Cl.none()], address2).result).toBeOk(Cl.bool(true));

      // 2. Set Winner (Reporter only)
      const { result: winRes } = simnet.callPublicFn(contractName, "set-campaign-winner", [Cl.uint(1), Cl.principal(address3)], address2);
      expect(winRes).toBeOk(Cl.bool(true));

      // 3. Claim Prize (Winner only)
      const { result: claimRes } = simnet.callPublicFn(contractName, "claim-campaign-prize", [Cl.uint(1)], address3);
      expect(claimRes).toBeOk(Cl.uint(1000000));
    });

    it("should fail prize claim if not winner", () => {
      expect(simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(1000), Cl.uint(2000), Cl.uint(0)], address1).result).toBeOk(Cl.uint(1));
      expect(simnet.callPublicFn(contractName, "set-campaign-winner", [Cl.uint(1), Cl.principal(address3)], address2).result).toBeOk(Cl.bool(true));
      const { result } = simnet.callPublicFn(contractName, "claim-campaign-prize", [Cl.uint(1)], address1);
      expect(result).toBeErr(Cl.uint(3)); // ERR-UNAUTHORIZED
    });
  });

  describe("Prediction Market & Refunds", () => {
    const campaignId = 1;

    beforeEach(() => {
      const metadataHash = new Uint8Array(32).fill(1);
      simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(address2), Cl.uint(1000), Cl.uint(2000), Cl.uint(0)], address1);
    });

    it("should handle match cancellation and refunds", () => {
      const matchHash = new Uint8Array(32).fill(3);
      expect(simnet.callPublicFn(contractName, "create-match", [Cl.uint(campaignId), Cl.buffer(matchHash)], address1).result).toBeOk(Cl.uint(1));
      expect(simnet.callPublicFn(contractName, "stake", [Cl.uint(1), Cl.uint(5000000), Cl.bool(true)], address3).result).toBeOk(Cl.bool(true));

      // 1. Cancel Match (Reporter only)
      const { result: cancelRes } = simnet.callPublicFn(contractName, "cancel-match", [Cl.uint(1)], address2);
      expect(cancelRes).toBeOk(Cl.bool(true));

      // 2. Refund Stake
      const { result: refundRes } = simnet.callPublicFn(contractName, "refund-stake", [Cl.uint(1)], address3);
      expect(refundRes).toBeOk(Cl.uint(5000000));
    });
  });

  describe("Safety & Governance", () => {
    it("should enforce emergency pause", () => {
      // 1. Pause
      simnet.callPublicFn(contractName, "set-paused", [Cl.bool(true)], deployer);

      // 2. Try to create campaign
      const { result } = simnet.callPublicFn(
        contractName,
        "create-campaign",
        [Cl.buffer(new Uint8Array(32)), Cl.principal(address2), Cl.uint(100), Cl.uint(200), Cl.uint(0)],
        address1
      );
      expect(result).toBeErr(Cl.uint(10)); // ERR-PAUSED
    });

    it("should handle 2-step admin handoff", () => {
      // 1. Propose
      const { result: propRes } = simnet.callPublicFn(contractName, "propose-admin", [Cl.principal(address1)], deployer);
      expect(propRes).toBeOk(Cl.bool(true));

      // 2. Try to claim from wrong address
      const { result: failRes } = simnet.callPublicFn(contractName, "claim-admin", [], address2);
      expect(failRes).toBeErr(Cl.uint(3)); // ERR-UNAUTHORIZED

      // 3. Claim correctly
      const { result: claimRes } = simnet.callPublicFn(contractName, "claim-admin", [], address1);
      expect(claimRes).toBeOk(Cl.bool(true));

      // 4. Verify new admin
      const { result: admin } = simnet.callReadOnlyFn(contractName, "get-admin", [], deployer);
      expect(admin).toBeOk(Cl.principal(address1));
    });
  });

  describe("Admin & Treasury", () => {
    it("should allow admin to withdraw protocol fees", () => {
      const metadataHash = new Uint8Array(32).fill(1);
      simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(address2), Cl.uint(1000), Cl.uint(2000), Cl.uint(0)], address1);

      const { result } = simnet.callPublicFn(contractName, "withdraw-treasury", [Cl.uint(1000000)], deployer);
      expect(result).toBeOk(Cl.uint(1000000));
    });
  });

  describe("Developer Sync Power-Up (v2.4.0)", () => {
    const reporter = address2; // Use a wallet as the reporter for this test suite
    const player1 = address3;
    const player2 = address1;

    beforeEach(() => {
      const metadataHash = new Uint8Array(32).fill(1);
      // Create campaign with High Score mode (1)
      simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(0), Cl.uint(1000), Cl.uint(1)], address1);
    });

    it("should handle High Score logic correctly", () => {
      // 1. Sync score 50
      const updates = [
        Cl.tuple({ "campaign-id": Cl.uint(1), player: Cl.principal(player1), score: Cl.uint(50) })
      ];
      simnet.callPublicFn(contractName, "sync-scores-batch", [Cl.list(updates), Cl.principal(contractName)], reporter);

      let { result: score } = simnet.callReadOnlyFn(contractName, "get-leaderboard-score", [Cl.uint(1), Cl.principal(player1)], deployer);
      expect(score).toBeOk(Cl.uint(50));

      // 2. Sync score 30 (should NOT update)
      simnet.callPublicFn(contractName, "sync-scores-batch", [Cl.list([Cl.tuple({ "campaign-id": Cl.uint(1), player: Cl.principal(player1), score: Cl.uint(30) })]), Cl.principal(contractName)], reporter);
      ({ result: score } = simnet.callReadOnlyFn(contractName, "get-leaderboard-score", [Cl.uint(1), Cl.principal(player1)], deployer));
      expect(score).toBeOk(Cl.uint(50));

      // 3. Sync score 70 (SHOULD update)
      simnet.callPublicFn(contractName, "sync-scores-batch", [Cl.list([Cl.tuple({ "campaign-id": Cl.uint(1), player: Cl.principal(player1), score: Cl.uint(70) })]), Cl.principal(contractName)], reporter);
      ({ result: score } = simnet.callReadOnlyFn(contractName, "get-leaderboard-score", [Cl.uint(1), Cl.principal(player1)], deployer));
      expect(score).toBeOk(Cl.uint(70));
    });

    it("should handle batch syncing for multiple players", () => {
      const updates = [
        Cl.tuple({ "campaign-id": Cl.uint(1), player: Cl.principal(player1), score: Cl.uint(100) }),
        Cl.tuple({ "campaign-id": Cl.uint(1), player: Cl.principal(player2), score: Cl.uint(200) })
      ];
      const { result } = simnet.callPublicFn(contractName, "sync-scores-batch", [Cl.list(updates), Cl.principal(contractName)], reporter);
      expect(result).toBeOk(Cl.list([Cl.uint(100), Cl.uint(200)]));

      const { result: s1 } = simnet.callReadOnlyFn(contractName, "get-leaderboard-score", [Cl.uint(1), Cl.principal(player1)], deployer);
      const { result: s2 } = simnet.callReadOnlyFn(contractName, "get-leaderboard-score", [Cl.uint(1), Cl.principal(player2)], deployer);
      expect(s1).toBeOk(Cl.uint(100));
      expect(s2).toBeOk(Cl.uint(200));
    });

    it("should store and retrieve player state hashes", () => {
      const stateHash = new Uint8Array(32).fill(7);
      const { result } = simnet.callPublicFn(contractName, "sync-player-state", [Cl.uint(1), Cl.principal(player1), Cl.buffer(stateHash), Cl.principal(contractName)], reporter);
      expect(result).toBeOk(Cl.bool(true));

      const { result: state } = simnet.callReadOnlyFn(contractName, "get-player-state", [Cl.uint(1), Cl.principal(player1)], deployer);
      expect(state).toBeOk(Cl.some(Cl.buffer(stateHash)));
    });
  });

  describe("Full Management (v2.4.0+)", () => {
    const reporter = address2;
    const player = address3;
    const metadataHash = new Uint8Array(32).fill(9);

    it("should allow developer to onboard a player and set their username", () => {
      // 1. Create Campaign
      const { result: createRes } = simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(0), Cl.uint(100), Cl.uint(0)], deployer);
      const campaignId = (createRes as any).value.value;

      // 2. Onboard
      const { result: onboardRes } = simnet.callPublicFn(contractName, "onboard-player", [Cl.uint(campaignId), Cl.principal(player), Cl.none()], reporter);
      expect(onboardRes).toBeOk(Cl.bool(true));

      // 3. Set username for player
      const { result: userRes } = simnet.callPublicFn(contractName, "set-player-username", [Cl.principal(player), Cl.stringAscii("managed_user"), Cl.uint(campaignId)], reporter);
      expect(userRes).toBeOk(Cl.bool(true));

      const { result: profile } = simnet.callReadOnlyFn(contractName, "get-user-profile", [Cl.principal(player)], deployer);
      expect(profile).toBeOk(Cl.some(Cl.tuple({ username: Cl.stringAscii("managed_user") })));
    });

    it("should allow developer to stake, resolve, and trigger rewards for a player", () => {
      // 1. Setup
      const { result: createRes } = simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(0), Cl.uint(100), Cl.uint(0)], deployer);
      const campaignId = (createRes as any).value.value;

      const { result: matchRes } = simnet.callPublicFn(contractName, "create-match", [Cl.uint(campaignId), Cl.buffer(metadataHash)], reporter);
      const eventId = (matchRes as any).value.value;

      // 2. Stake for player (1 STX on YES)
      const { result: stakeRes } = simnet.callPublicFn(contractName, "stake-for", [Cl.uint(eventId), Cl.uint(1000000), Cl.bool(true), Cl.principal(player)], reporter);
      expect(stakeRes).toBeOk(Cl.bool(true));

      // 3. Resolve Match (YES wins)
      simnet.callPublicFn(contractName, "resolve-match", [Cl.uint(eventId), Cl.bool(true)], reporter);

      // 4. Developer triggers reward for player
      const { result: payoutRes } = simnet.callPublicFn(contractName, "claim-reward-for", [Cl.uint(eventId), Cl.principal(player)], reporter);
      expect(payoutRes).toBeOk(Cl.uint(1000000));
    });

    it("should allow developer to finalize campaign and trigger prize for the winner", () => {
      // 1. Setup
      const { result: createRes } = simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(0), Cl.uint(100), Cl.uint(0)], deployer);
      const campaignId = (createRes as any).value.value;

      // 2. Join player and sync score
      simnet.callPublicFn(contractName, "onboard-player", [Cl.uint(campaignId), Cl.principal(player), Cl.none()], reporter);
      simnet.callPublicFn(contractName, "sync-scores-batch", [Cl.list([Cl.tuple({ "campaign-id": Cl.uint(campaignId), player: Cl.principal(player), score: Cl.uint(500) })]), Cl.principal(contractName)], reporter);

      // 3. Finalize winner
      simnet.callPublicFn(contractName, "set-campaign-winner", [Cl.uint(campaignId), Cl.principal(player)], reporter);

      // 4. Developer triggers prize claim
      simnet.mineEmptyBlocks(101);

      const { result: claimRes } = simnet.callPublicFn(contractName, "claim-campaign-prize-for", [Cl.uint(campaignId), Cl.principal(player)], reporter);
      expect(claimRes).toBeOk(Cl.uint(1000000));
    });
  });
});
