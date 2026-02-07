import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;
const deployer = accounts.get("deployer")!;

const contractName = `${simnet.deployer}.roxy`;

describe("Roxy SDK v2.1.0 Tests", () => {
  it("ensures the contract is deployed", () => {
    const contractSource = simnet.getContractSource("roxy");
    expect(contractSource).toBeDefined();
  });

  describe("User Profiles", () => {
    it("should set a unique username successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "set-username",
        [Cl.stringAscii("roxy_hero")],
        address1
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify via getter
      const { result: profile } = simnet.callReadOnlyFn(
        contractName,
        "get-user-profile",
        [Cl.principal(address1)],
        address1
      );
      expect(profile).toBeOk(Cl.some(Cl.tuple({ username: Cl.stringAscii("roxy_hero") })));
    });

    it("should fail if username is taken", () => {
      simnet.callPublicFn(contractName, "set-username", [Cl.stringAscii("taken")], address1);
      const { result } = simnet.callPublicFn(
        contractName,
        "set-username",
        [Cl.stringAscii("taken")],
        address2
      );
      expect(result).toBeErr(Cl.uint(13)); // ERR-USERNAME-TAKEN
    });

    it("should allow a user to update their own username and release the old one", () => {
      simnet.callPublicFn(contractName, "set-username", [Cl.stringAscii("old_name")], address1);
      simnet.callPublicFn(contractName, "set-username", [Cl.stringAscii("new_name")], address1);

      // Old name should now be available
      const { result } = simnet.callPublicFn(
        contractName,
        "set-username",
        [Cl.stringAscii("old_name")],
        address2
      );
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail if username is empty", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "set-username",
        [Cl.stringAscii("")],
        address1
      );
      expect(result).toBeErr(Cl.uint(12)); // ERR-INVALID-METADATA
    });
  });

  describe("Campaign Management", () => {
    const metadataHash = new Uint8Array(32).fill(1);
    const reporter = address2;
    const startTime = 1000;
    const endTime = 2000;

    it("should create a campaign successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "create-campaign",
        [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(startTime), Cl.uint(endTime)],
        address1
      );
      expect(result).toBeOk(Cl.uint(1)); // First campaign ID

      // Verify treasury increased by $1 fee
      const { result: treasury } = simnet.callReadOnlyFn(contractName, "get-protocol-treasury", [], deployer);
      expect(treasury).toBeOk(Cl.uint(1000000));
    });

    it("should fail if end-time is not after start-time", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "create-campaign",
        [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(2000), Cl.uint(1000)],
        address1
      );
      expect(result).toBeErr(Cl.uint(11)); // ERR-INVALID-TIME
    });

    it("should allow a user to join a campaign with a referrer", () => {
      simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(startTime), Cl.uint(endTime)], address1);

      const { result } = simnet.callPublicFn(
        contractName,
        "join-campaign",
        [Cl.uint(1), Cl.some(Cl.principal(address3))],
        address2
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify referral (10% of $1 fee = 100,000 micro-STX)
      // Note: Simnet doesn't track STX balances unless we explicitly check them, 
      // but we can check the prize pool increase ($1 - 10% = 900,000)
      const { result: campaign } = simnet.callReadOnlyFn(contractName, "get-campaign", [Cl.uint(1)], deployer);
      expect(campaign).toBeOk(Cl.some(Cl.tuple({
        creator: Cl.principal(address1),
        "metadata-hash": Cl.buffer(metadataHash),
        "prize-pool": Cl.uint(900000),
        reporter: Cl.principal(reporter),
        "start-time": Cl.uint(startTime),
        "end-time": Cl.uint(endTime),
        status: Cl.stringAscii("open")
      })));
    });

    it("should fail to join a campaign twice", () => {
      simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(startTime), Cl.uint(endTime)], address1);
      simnet.callPublicFn(contractName, "join-campaign", [Cl.uint(1), Cl.none()], address2);
      const { result } = simnet.callPublicFn(contractName, "join-campaign", [Cl.uint(1), Cl.none()], address2);
      expect(result).toBeErr(Cl.uint(7)); // ERR-ALREADY-PARTICIPATED
    });

    it("should fail to join a non-existent campaign", () => {
      const { result } = simnet.callPublicFn(contractName, "join-campaign", [Cl.uint(999), Cl.none()], address1);
      expect(result).toBeErr(Cl.uint(2)); // ERR-NOT-FOUND
    });

    it("should fail to update campaign status if not creator", () => {
      simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(startTime), Cl.uint(endTime)], address1);
      const { result } = simnet.callPublicFn(contractName, "update-campaign-status", [Cl.uint(1), Cl.stringAscii("closed")], address2);
      expect(result).toBeErr(Cl.uint(3)); // ERR-UNAUTHORIZED
    });
  });

  describe("Prediction Market (Matches)", () => {
    const campaignId = 1;
    const matchMetadata = "Will Roxy reach top 10?";

    beforeEach(() => {
      const metadataHash = new Uint8Array(32).fill(1);
      simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(address2), Cl.uint(1000), Cl.uint(2000)], address1);
    });

    it("should create a match and collect fees", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "create-match",
        [Cl.uint(campaignId), Cl.stringAscii(matchMetadata)],
        address1
      );
      expect(result).toBeOk(Cl.uint(1)); // First match ID

      // Treasury should have $1 (campaign) + $1 (match) = $2
      const { result: treasury } = simnet.callReadOnlyFn(contractName, "get-protocol-treasury", [], deployer);
      expect(treasury).toBeOk(Cl.uint(2000000));
    });

    it("should fail to create a match if not authorized", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "create-match",
        [Cl.uint(campaignId), Cl.stringAscii(matchMetadata)],
        address3 // Not creator (address1) and not reporter (address2)
      );
      expect(result).toBeErr(Cl.uint(3)); // ERR-UNAUTHORIZED
    });

    it("should allow users to stake on YES/NO", () => {
      simnet.callPublicFn(contractName, "create-match", [Cl.uint(campaignId), Cl.stringAscii(matchMetadata)], address1);

      const resYes = simnet.callPublicFn(contractName, "stake", [Cl.uint(1), Cl.uint(1000000), Cl.bool(true)], address2);
      const resNo = simnet.callPublicFn(contractName, "stake", [Cl.uint(1), Cl.uint(2000000), Cl.bool(false)], address3);

      expect(resYes.result).toBeOk(Cl.bool(true));
      expect(resNo.result).toBeOk(Cl.bool(true));

      // Verify pools
      const { result: matchData } = simnet.callReadOnlyFn(contractName, "get-event", [Cl.uint(1)], deployer);
      expect(matchData).toBeOk(Cl.some(Cl.tuple({
        "campaign-id": Cl.uint(1),
        "yes-pool": Cl.uint(1000000),
        "no-pool": Cl.uint(2000000),
        status: Cl.stringAscii("open"),
        winner: Cl.none(),
        metadata: Cl.stringAscii(matchMetadata)
      })));
    });

    it("should fail if stake amount is 0", () => {
      simnet.callPublicFn(contractName, "create-match", [Cl.uint(campaignId), Cl.stringAscii(matchMetadata)], address1);
      const { result } = simnet.callPublicFn(contractName, "stake", [Cl.uint(1), Cl.uint(0), Cl.bool(true)], address2);
      expect(result).toBeErr(Cl.uint(4)); // ERR-INVALID-AMOUNT
    });

    it("should fail to stake on a non-open match", () => {
      simnet.callPublicFn(contractName, "create-match", [Cl.uint(campaignId), Cl.stringAscii(matchMetadata)], address1);
      simnet.callPublicFn(contractName, "resolve-match", [Cl.uint(1), Cl.bool(true)], address2);
      const { result } = simnet.callPublicFn(contractName, "stake", [Cl.uint(1), Cl.uint(1000000), Cl.bool(true)], address3);
      expect(result).toBeErr(Cl.uint(8)); // ERR-EVENT-NOT-OPEN
    });

    it("should resolve a match and allow rewards claim (YES wins)", () => {
      simnet.callPublicFn(contractName, "create-match", [Cl.uint(campaignId), Cl.stringAscii(matchMetadata)], address1);
      simnet.callPublicFn(contractName, "stake", [Cl.uint(1), Cl.uint(1000000), Cl.bool(true)], address2);
      simnet.callPublicFn(contractName, "stake", [Cl.uint(1), Cl.uint(1000000), Cl.bool(false)], address3);

      // Only reporter (address2) can resolve
      const resolveRes = simnet.callPublicFn(contractName, "resolve-match", [Cl.uint(1), Cl.bool(true)], address2);
      expect(resolveRes.result).toBeOk(Cl.bool(true));

      // Address 2 claims reward (1m stake + 1m pool share = 2m total)
      const claimRes = simnet.callPublicFn(contractName, "claim-reward", [Cl.uint(1)], address2);
      expect(claimRes.result).toBeOk(Cl.uint(2000000));
    });

    it("should fail to resolve match if not reporter", () => {
      simnet.callPublicFn(contractName, "create-match", [Cl.uint(campaignId), Cl.stringAscii(matchMetadata)], address1);
      const { result } = simnet.callPublicFn(contractName, "resolve-match", [Cl.uint(1), Cl.bool(true)], address3);
      expect(result).toBeErr(Cl.uint(3)); // ERR-UNAUTHORIZED
    });

    it("should fail to claim reward if match not resolved", () => {
      simnet.callPublicFn(contractName, "create-match", [Cl.uint(campaignId), Cl.stringAscii(matchMetadata)], address1);
      simnet.callPublicFn(contractName, "stake", [Cl.uint(1), Cl.uint(1000000), Cl.bool(true)], address2);
      const { result } = simnet.callPublicFn(contractName, "claim-reward", [Cl.uint(1)], address2);
      expect(result).toBeErr(Cl.uint(9)); // ERR-EVENT-CLOSED
    });

    it("should fail to claim reward if no stake found", () => {
      simnet.callPublicFn(contractName, "create-match", [Cl.uint(campaignId), Cl.stringAscii(matchMetadata)], address1);
      simnet.callPublicFn(contractName, "resolve-match", [Cl.uint(1), Cl.bool(true)], address2);
      const { result } = simnet.callPublicFn(contractName, "claim-reward", [Cl.uint(1)], address3);
      expect(result).toBeErr(Cl.uint(2)); // ERR-NOT-FOUND
    });
  });

  describe("Admin & Treasury", () => {
    it("should allow admin to withdraw protocol fees", () => {
      // Setup treasury
      const metadataHash = new Uint8Array(32).fill(1);
      simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(address2), Cl.uint(1000), Cl.uint(2000)], address1);

      // Withdraw half ($0.5)
      const { result } = simnet.callPublicFn(
        contractName,
        "withdraw-treasury",
        [Cl.uint(500000)],
        deployer
      );
      expect(result).toBeOk(Cl.uint(500000));

      const { result: remaining } = simnet.callReadOnlyFn(contractName, "get-protocol-treasury", [], deployer);
      expect(remaining).toBeOk(Cl.uint(500000));
    });

    it("should fail to withdraw treasury if not admin", () => {
      const { result } = simnet.callPublicFn(contractName, "withdraw-treasury", [Cl.uint(100)], address1);
      expect(result).toBeErr(Cl.uint(1)); // ERR-NOT-ADMIN
    });

    it("should fail to withdraw more than treasury balance", () => {
      const { result } = simnet.callPublicFn(contractName, "withdraw-treasury", [Cl.uint(999999999)], deployer);
      expect(result).toBeErr(Cl.uint(6)); // ERR-INSUFFICIENT-FUNDS
    });

    it("should allow admin to change match creation fee", () => {
      const { result } = simnet.callPublicFn(contractName, "set-match-creation-fee", [Cl.uint(5000000)], deployer);
      expect(result).toBeOk(Cl.bool(true));

      const { result: newFee } = simnet.callReadOnlyFn(contractName, "get-match-creation-fee", [], deployer);
      expect(newFee).toBeOk(Cl.uint(5000000));
    });

    it("should fail to set match creation fee if not admin", () => {
      const { result } = simnet.callPublicFn(contractName, "set-match-creation-fee", [Cl.uint(0)], address2);
      expect(result).toBeErr(Cl.uint(1)); // ERR-NOT-ADMIN
    });
  });
});
