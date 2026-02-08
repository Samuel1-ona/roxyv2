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
      const { result } = simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(1000), Cl.uint(2000)], address1);
      expect(result).toBeOk(Cl.uint(1));
    });

    it("should allow a user to join a campaign without a referrer", () => {
      expect(simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(1000), Cl.uint(2000)], address1).result).toBeOk(Cl.uint(1));
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
        winner: Cl.none()
      })));
    });

    it("should allow updating campaign metadata", () => {
      expect(simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(1000), Cl.uint(2000)], address1).result).toBeOk(Cl.uint(1));

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
        winner: Cl.none()
      })));
    });

    it("should handle campaign prize distribution", () => {
      // 1. Create and Join
      expect(simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(1000), Cl.uint(2000)], address1).result).toBeOk(Cl.uint(1));
      expect(simnet.callPublicFn(contractName, "join-campaign", [Cl.uint(1), Cl.none()], address2).result).toBeOk(Cl.bool(true));

      // 2. Set Winner (Reporter only)
      const { result: winRes } = simnet.callPublicFn(contractName, "set-campaign-winner", [Cl.uint(1), Cl.principal(address3)], address2);
      expect(winRes).toBeOk(Cl.bool(true));

      // 3. Claim Prize (Winner only)
      const { result: claimRes } = simnet.callPublicFn(contractName, "claim-campaign-prize", [Cl.uint(1)], address3);
      expect(claimRes).toBeOk(Cl.uint(1000000));
    });

    it("should fail prize claim if not winner", () => {
      expect(simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(reporter), Cl.uint(1000), Cl.uint(2000)], address1).result).toBeOk(Cl.uint(1));
      expect(simnet.callPublicFn(contractName, "set-campaign-winner", [Cl.uint(1), Cl.principal(address3)], address2).result).toBeOk(Cl.bool(true));
      const { result } = simnet.callPublicFn(contractName, "claim-campaign-prize", [Cl.uint(1)], address1);
      expect(result).toBeErr(Cl.uint(3)); // ERR-UNAUTHORIZED
    });
  });

  describe("Prediction Market & Refunds", () => {
    const campaignId = 1;

    beforeEach(() => {
      const metadataHash = new Uint8Array(32).fill(1);
      simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(address2), Cl.uint(1000), Cl.uint(2000)], address1);
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
        [Cl.buffer(new Uint8Array(32)), Cl.principal(address2), Cl.uint(100), Cl.uint(200)],
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
      simnet.callPublicFn(contractName, "create-campaign", [Cl.buffer(metadataHash), Cl.principal(address2), Cl.uint(1000), Cl.uint(2000)], address1);

      const { result } = simnet.callPublicFn(contractName, "withdraw-treasury", [Cl.uint(1000000)], deployer);
      expect(result).toBeOk(Cl.uint(1000000));
    });
  });
});
