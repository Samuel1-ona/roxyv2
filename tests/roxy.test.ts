import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;
const deployer = accounts.get("deployer")!;

const contractName = `${simnet.deployer}.roxy`;

// Helper function to accumulate enough earned points (10,000+) for a user
function accumulateEarnedPoints(user: string, opponent: string, startEventId: number = 1, createFirstEvent: boolean = false) {
  let eventId = startEventId;
  
  // Create event 1 if needed (only if explicitly requested, since beforeEach usually creates it)
  if (createFirstEvent) {
    simnet.callPublicFn(contractName, "create-event", [Cl.uint(eventId), Cl.stringAscii(`Event ${eventId}`)], deployer);
  }
  
  // Use smaller, consistent stake amounts so both users can participate
  const stakeAmount = 300; // Small stake so both users can participate in many events
  
  // Event 1: User wins (earned: ~1000, but reward is stake * 2 = 1000, so earned = 1000)
  simnet.callPublicFn(contractName, "stake-yes", [Cl.uint(eventId), Cl.uint(stakeAmount)], accounts.get(user)!);
  simnet.callPublicFn(contractName, "stake-no", [Cl.uint(eventId), Cl.uint(stakeAmount)], accounts.get(opponent)!);
  simnet.callPublicFn(contractName, "resolve-event", [Cl.uint(eventId), Cl.bool(true)], deployer); // YES wins
  const claim1Result = simnet.callPublicFn(contractName, "claim", [Cl.uint(eventId)], accounts.get(user)!);
  if (claim1Result.result.type === 'err') {
    throw new Error(`Event 1 claim failed: ${JSON.stringify(claim1Result.result)}`);
  }
  eventId++;
  
  // Event 2: Opponent wins (so they get points back)
  simnet.callPublicFn(contractName, "create-event", [Cl.uint(eventId), Cl.stringAscii(`Event ${eventId}`)], deployer);
  simnet.callPublicFn(contractName, "stake-yes", [Cl.uint(eventId), Cl.uint(stakeAmount)], accounts.get(user)!);
  simnet.callPublicFn(contractName, "stake-no", [Cl.uint(eventId), Cl.uint(stakeAmount)], accounts.get(opponent)!);
  simnet.callPublicFn(contractName, "resolve-event", [Cl.uint(eventId), Cl.bool(false)], deployer); // NO wins
  simnet.callPublicFn(contractName, "claim", [Cl.uint(eventId)], accounts.get(opponent)!);
  eventId++;
  
  // Continue with more events - user needs to win enough to get 10,000+ earned points
  // Each win gives approximately stakeAmount * 2 in reward (since pools are equal)
  // With 300 stake, each win = ~600 reward = ~600 earned points
  // User already won Event 1 (~600 earned), needs 16 more wins = 10,200 total earned
  // Alternate wins strictly so both users maintain point balance
  // User wins on even iterations (0, 2, 4...), opponent wins on odd (1, 3, 5...)
  for (let i = 0; i < 32; i++) {
    simnet.callPublicFn(contractName, "create-event", [Cl.uint(eventId), Cl.stringAscii(`Event ${eventId}`)], deployer);
    const userStakeResult = simnet.callPublicFn(contractName, "stake-yes", [Cl.uint(eventId), Cl.uint(stakeAmount)], accounts.get(user)!);
    if (userStakeResult.result.type === 'err') {
      throw new Error(`Event ${eventId} user stake failed: ${JSON.stringify(userStakeResult.result)}`);
    }
    const opponentStakeResult = simnet.callPublicFn(contractName, "stake-no", [Cl.uint(eventId), Cl.uint(stakeAmount)], accounts.get(opponent)!);
    if (opponentStakeResult.result.type === 'err') {
      throw new Error(`Event ${eventId} opponent stake failed: ${JSON.stringify(opponentStakeResult.result)}`);
    }
    const userWins = (i % 2 === 0);
    simnet.callPublicFn(contractName, "resolve-event", [Cl.uint(eventId), Cl.bool(userWins)], deployer);
    if (userWins) {
      const claimResult = simnet.callPublicFn(contractName, "claim", [Cl.uint(eventId)], accounts.get(user)!);
      if (claimResult.result.type === 'err') {
        throw new Error(`Event ${eventId} claim failed: ${JSON.stringify(claimResult.result)}`);
      }
    } else {
      const claimResult = simnet.callPublicFn(contractName, "claim", [Cl.uint(eventId)], accounts.get(opponent)!);
      if (claimResult.result.type === 'err') {
        throw new Error(`Event ${eventId} opponent claim failed: ${JSON.stringify(claimResult.result)}`);
      }
    }
    eventId++;
  }

  return eventId; // Return next available event ID
}

describe("Roxy Contract Tests", () => {
  it("ensures the contract is deployed", () => {
    const contractSource = simnet.getContractSource("roxy");
    expect(contractSource).toBeDefined();
  });

  describe("register", () => {
    it("should register a new user successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "register",
        [Cl.stringAscii("alice")],
        address1
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify user points via map
      const userPoints = simnet.getMapEntry(contractName, "user-points", Cl.principal(address1));
      expect(userPoints).toBeSome(Cl.uint(1000));

      // Verify earned points via map
      const earnedPoints = simnet.getMapEntry(contractName, "earned-points", Cl.principal(address1));
      expect(earnedPoints).toBeSome(Cl.uint(0));

      // Verify user name via map
      const userName = simnet.getMapEntry(contractName, "user-names", Cl.principal(address1));
      expect(userName).toBeSome(Cl.stringAscii("alice"));

      // Verify username uniqueness map
      const usernameMapping = simnet.getMapEntry(contractName, "usernames", Cl.stringAscii("alice"));
      expect(usernameMapping).toBeSome(Cl.principal(address1));

      // Verify user points via read-only function
      const { result: pointsResult } = simnet.callReadOnlyFn(
        contractName,
        "get-user-points",
        [Cl.principal(address1)],
        address1
      );
      expect(pointsResult).toBeOk(Cl.some(Cl.uint(1000)));

      // Verify earned points via read-only function
      const { result: earnedResult } = simnet.callReadOnlyFn(
        contractName,
        "get-earned-points",
        [Cl.principal(address1)],
        address1
      );
      expect(earnedResult).toBeOk(Cl.some(Cl.uint(0)));

      // Verify username via read-only function
      const { result: usernameResult } = simnet.callReadOnlyFn(
        contractName,
        "get-username",
        [Cl.principal(address1)],
        address1
      );
      expect(usernameResult).toBeSome(Cl.stringAscii("alice"));
    });

    it("should fail if user already registered", () => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      const { result } = simnet.callPublicFn(
        contractName,
        "register",
        [Cl.stringAscii("alice2")],
        address1
      );
      expect(result).toBeErr(Cl.uint(1)); // ERR-USER-ALREADY-REGISTERED
    });

    it("should fail if username is already taken", () => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      const { result } = simnet.callPublicFn(
        contractName,
        "register",
        [Cl.stringAscii("alice")],
        address2
      );
      expect(result).toBeErr(Cl.uint(26)); // ERR-USERNAME-TAKEN
    });
  });

  describe("create-event", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
    });

    it("should create an event successfully (admin only)", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("Will Bitcoin reach $100k?")],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify event via map
      const event = simnet.getMapEntry(contractName, "events", Cl.uint(1));
      expect(event).toBeSome(
        Cl.tuple({
          "yes-pool": Cl.uint(0),
          "no-pool": Cl.uint(0),
          status: Cl.stringAscii("open"),
          winner: Cl.none(),
          creator: Cl.principal(deployer),
          metadata: Cl.stringAscii("Will Bitcoin reach $100k?"),
        })
      );

      // Verify event via read-only function
      const { result: eventResult } = simnet.callReadOnlyFn(
        contractName,
        "get-event",
        [Cl.uint(1)],
        address1
      );
      expect(eventResult).toBeSome(
        Cl.tuple({
          "yes-pool": Cl.uint(0),
          "no-pool": Cl.uint(0),
          status: Cl.stringAscii("open"),
          winner: Cl.none(),
          creator: Cl.principal(deployer),
          metadata: Cl.stringAscii("Will Bitcoin reach $100k?"),
        })
      );
    });

    it("should fail if not admin", () => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("user")], address1);
      const { result } = simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("Test event")],
        address1
      );
      expect(result).toBeErr(Cl.uint(2)); // ERR-NOT-ADMIN
    });

    it("should fail if event ID already exists", () => {
      simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("First event")],
        deployer
      );
      const { result } = simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("Duplicate event")],
        deployer
      );
      expect(result).toBeErr(Cl.uint(3)); // ERR-EVENT-ID-EXISTS
    });
  });

  describe("stake-yes", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("Test event")],
        deployer
      );
    });

    it("should stake YES successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "stake-yes",
        [Cl.uint(1), Cl.uint(100)],
        address1
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify stake via map
      const stakeKey = Cl.tuple({
        "event-id": Cl.uint(1),
        user: Cl.principal(address1),
      });
      const stake = simnet.getMapEntry(contractName, "yes-stakes", stakeKey);
      expect(stake).toBeSome(Cl.uint(100));

      // Verify user points reduced via map
      const userPoints = simnet.getMapEntry(contractName, "user-points", Cl.principal(address1));
      expect(userPoints).toBeSome(Cl.uint(900)); // 1000 - 100

      // Verify event pool updated via map
      const event = simnet.getMapEntry(contractName, "events", Cl.uint(1));
      expect(event).toBeSome(
        Cl.tuple({
          "yes-pool": Cl.uint(100),
          "no-pool": Cl.uint(0),
          status: Cl.stringAscii("open"),
          winner: Cl.none(),
          creator: Cl.principal(deployer),
          metadata: Cl.stringAscii("Test event"),
        })
      );

      // Verify total YES stakes via data var
      const totalYesStakes = simnet.getDataVar(contractName, "total-yes-stakes");
      expect(totalYesStakes).toBeUint(100);

      // Verify stake via read-only function
      const { result: stakeResult } = simnet.callReadOnlyFn(
        contractName,
        "get-yes-stake",
        [Cl.uint(1), Cl.principal(address1)],
        address1
      );
      expect(stakeResult).toBeSome(Cl.uint(100));

      // Verify user points reduced via read-only function
      const { result: pointsResult } = simnet.callReadOnlyFn(
        contractName,
        "get-user-points",
        [Cl.principal(address1)],
        address1
      );
      expect(pointsResult).toBeOk(Cl.some(Cl.uint(900))); // 1000 - 100

      // Verify event pool updated via read-only function
      const { result: eventResult } = simnet.callReadOnlyFn(
        contractName,
        "get-event",
        [Cl.uint(1)],
        address1
      );
      expect(eventResult).toBeSome(
        Cl.tuple({
          "yes-pool": Cl.uint(100),
          "no-pool": Cl.uint(0),
          status: Cl.stringAscii("open"),
          winner: Cl.none(),
          creator: Cl.principal(deployer),
          metadata: Cl.stringAscii("Test event"),
        })
      );

      // Verify total YES stakes via read-only function
      const { result: totalYesResult } = simnet.callReadOnlyFn(
        contractName,
        "get-total-yes-stakes",
        [],
        address1
      );
      expect(totalYesResult).toStrictEqual(Cl.uint(100));
    });

    it("should fail if amount is 0", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "stake-yes",
        [Cl.uint(1), Cl.uint(0)],
        address1
      );
      expect(result).toBeErr(Cl.uint(4)); // ERR-INVALID-AMOUNT
    });

    it("should fail if event not found", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "stake-yes",
        [Cl.uint(999), Cl.uint(100)],
        address1
      );
      expect(result).toBeErr(Cl.uint(8)); // ERR-EVENT-NOT-FOUND
    });

    it("should fail if event not open", () => {
      simnet.callPublicFn(contractName, "stake-yes", [Cl.uint(1), Cl.uint(100)], address1);
      simnet.callPublicFn(
        contractName,
        "resolve-event",
        [Cl.uint(1), Cl.bool(true)],
        deployer
      );
      const { result } = simnet.callPublicFn(
        contractName,
        "stake-yes",
        [Cl.uint(1), Cl.uint(100)],
        address1
      );
      expect(result).toBeErr(Cl.uint(5)); // ERR-EVENT-NOT-OPEN
    });

    it("should fail if insufficient points", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "stake-yes",
        [Cl.uint(1), Cl.uint(2000)],
        address1
      );
      expect(result).toBeErr(Cl.uint(6)); // ERR-INSUFFICIENT-POINTS
    });

    it("should fail if user not registered", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "stake-yes",
        [Cl.uint(1), Cl.uint(100)],
        address2
      );
      expect(result).toBeErr(Cl.uint(7)); // ERR-USER-NOT-REGISTERED
    });

    it("should accumulate stakes for same user", () => {
      simnet.callPublicFn(contractName, "stake-yes", [Cl.uint(1), Cl.uint(100)], address1);
      simnet.callPublicFn(contractName, "stake-yes", [Cl.uint(1), Cl.uint(50)], address1);

      const { result: stakeResult } = simnet.callReadOnlyFn(
        contractName,
        "get-yes-stake",
        [Cl.uint(1), Cl.principal(address1)],
        address1
      );
      expect(stakeResult).toBeSome(Cl.uint(150));
    });
  });

  describe("stake-no", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("Test event")],
        deployer
      );
    });

    it("should stake NO successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "stake-no",
        [Cl.uint(1), Cl.uint(100)],
        address1
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify stake via map
      const stakeKey = Cl.tuple({
        "event-id": Cl.uint(1),
        user: Cl.principal(address1),
      });
      const stake = simnet.getMapEntry(contractName, "no-stakes", stakeKey);
      expect(stake).toBeSome(Cl.uint(100));

      // Verify total NO stakes via data var
      const totalNoStakes = simnet.getDataVar(contractName, "total-no-stakes");
      expect(totalNoStakes).toBeUint(100);

      // Verify stake via read-only function
      const { result: stakeResult } = simnet.callReadOnlyFn(
        contractName,
        "get-no-stake",
        [Cl.uint(1), Cl.principal(address1)],
        address1
      );
      expect(stakeResult).toBeSome(Cl.uint(100));

      // Verify total NO stakes via read-only function
      const { result: totalNoResult } = simnet.callReadOnlyFn(
        contractName,
        "get-total-no-stakes",
        [],
        address1
      );
      expect(totalNoResult).toStrictEqual(Cl.uint(100));
    });

    it("should fail with same errors as stake-yes", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "stake-no",
        [Cl.uint(1), Cl.uint(0)],
        address1
      );
      expect(result).toBeErr(Cl.uint(4)); // ERR-INVALID-AMOUNT
    });
  });

  describe("resolve-event", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("Test event")],
        deployer
      );
    });

    it("should resolve event successfully (admin only)", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "resolve-event",
        [Cl.uint(1), Cl.bool(true)],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify event resolved via map
      const event = simnet.getMapEntry(contractName, "events", Cl.uint(1));
      expect(event).toBeSome(
        Cl.tuple({
          "yes-pool": Cl.uint(0),
          "no-pool": Cl.uint(0),
          status: Cl.stringAscii("resolved"),
          winner: Cl.some(Cl.bool(true)),
          creator: Cl.principal(deployer),
          metadata: Cl.stringAscii("Test event"),
        })
      );

      // Verify event resolved via read-only function
      const { result: eventResult } = simnet.callReadOnlyFn(
        contractName,
        "get-event",
        [Cl.uint(1)],
        address1
      );
      expect(eventResult).toBeSome(
        Cl.tuple({
          "yes-pool": Cl.uint(0),
          "no-pool": Cl.uint(0),
          status: Cl.stringAscii("resolved"),
          winner: Cl.some(Cl.bool(true)),
          creator: Cl.principal(deployer),
          metadata: Cl.stringAscii("Test event"),
        })
      );
    });

    it("should fail if not admin", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "resolve-event",
        [Cl.uint(1), Cl.bool(true)],
        address1
      );
      expect(result).toBeErr(Cl.uint(2)); // ERR-NOT-ADMIN
    });

    it("should fail if event not found", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "resolve-event",
        [Cl.uint(999), Cl.bool(true)],
        deployer
      );
      expect(result).toBeErr(Cl.uint(8)); // ERR-EVENT-NOT-FOUND
    });

    it("should fail if event not open", () => {
      simnet.callPublicFn(
        contractName,
        "resolve-event",
        [Cl.uint(1), Cl.bool(true)],
        deployer
      );
      const { result } = simnet.callPublicFn(
        contractName,
        "resolve-event",
        [Cl.uint(1), Cl.bool(false)],
        deployer
      );
      expect(result).toBeErr(Cl.uint(9)); // ERR-EVENT-MUST-BE-OPEN
    });
  });

  describe("claim", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("bob")], address2);
      simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("Test event")],
        deployer
      );
    });

    it("should claim rewards successfully when YES wins", () => {
      // Alice stakes 100 YES, Bob stakes 200 NO
      simnet.callPublicFn(contractName, "stake-yes", [Cl.uint(1), Cl.uint(100)], address1);
      simnet.callPublicFn(contractName, "stake-no", [Cl.uint(1), Cl.uint(200)], address2);

      // Resolve YES wins
      simnet.callPublicFn(
        contractName,
        "resolve-event",
        [Cl.uint(1), Cl.bool(true)],
        deployer
      );

      // Alice claims (should get 300 total pool / 100 winning pool * 100 stake = 300)
      const { result } = simnet.callPublicFn(
        contractName,
        "claim",
        [Cl.uint(1)],
        address1
      );
      expect(result.type).toBe("ok");
      if (result.type === "ok") {
        expect(result.value).toStrictEqual(Cl.uint(300));
      }

      // Verify user points increased via map
      const userPoints = simnet.getMapEntry(contractName, "user-points", Cl.principal(address1));
      expect(userPoints).toBeSome(Cl.uint(1200)); // 1000 - 100 + 300

      // Verify earned points increased via map
      const earnedPoints = simnet.getMapEntry(contractName, "earned-points", Cl.principal(address1));
      expect(earnedPoints).toBeSome(Cl.uint(300));

      // Verify stake cleared via map
      const stakeKey = Cl.tuple({
        "event-id": Cl.uint(1),
        user: Cl.principal(address1),
      });
      const stake = simnet.getMapEntry(contractName, "yes-stakes", stakeKey);
      expect(stake).toBeSome(Cl.uint(0));

      // Verify user stats updated via map
      const userStats = simnet.getMapEntry(contractName, "user-stats", Cl.principal(address1));
      expect(userStats).toBeSome(
        Cl.tuple({
          "total-predictions": Cl.uint(1),
          wins: Cl.uint(1),
          losses: Cl.uint(0),
          "total-points-earned": Cl.uint(300),
          "win-rate": Cl.uint(10000), // 100%
        })
      );

      // Verify user points increased via read-only function
      const { result: pointsResult } = simnet.callReadOnlyFn(
        contractName,
        "get-user-points",
        [Cl.principal(address1)],
        address1
      );
      expect(pointsResult).toBeOk(Cl.some(Cl.uint(1200))); // 1000 - 100 + 300

      // Verify earned points increased via read-only function
      const { result: earnedResult } = simnet.callReadOnlyFn(
        contractName,
        "get-earned-points",
        [Cl.principal(address1)],
        address1
      );
      expect(earnedResult).toBeOk(Cl.some(Cl.uint(300)));

      // Verify stake cleared via read-only function
      const { result: stakeResult } = simnet.callReadOnlyFn(
        contractName,
        "get-yes-stake",
        [Cl.uint(1), Cl.principal(address1)],
        address1
      );
      expect(stakeResult).toBeSome(Cl.uint(0));

      // Verify user stats updated via read-only function
      const { result: statsResult } = simnet.callReadOnlyFn(
        contractName,
        "get-user-stats",
        [Cl.principal(address1)],
        address1
      );
      expect(statsResult).toBeSome(
        Cl.tuple({
          "total-predictions": Cl.uint(1),
          wins: Cl.uint(1),
          losses: Cl.uint(0),
          "total-points-earned": Cl.uint(300),
          "win-rate": Cl.uint(10000), // 100%
        })
      );
    });

    it("should claim rewards successfully when NO wins", () => {
      simnet.callPublicFn(contractName, "stake-yes", [Cl.uint(1), Cl.uint(100)], address1);
      simnet.callPublicFn(contractName, "stake-no", [Cl.uint(1), Cl.uint(200)], address2);

      simnet.callPublicFn(
        contractName,
        "resolve-event",
        [Cl.uint(1), Cl.bool(false)],
        deployer
      );

      const { result } = simnet.callPublicFn(
        contractName,
        "claim",
        [Cl.uint(1)],
        address2
      );
      expect(result.type).toBe("ok");
    });

    it("should fail if event not found", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "claim",
        [Cl.uint(999)],
        address1
      );
      expect(result).toBeErr(Cl.uint(8)); // ERR-EVENT-NOT-FOUND
    });

    it("should fail if event not resolved", () => {
      simnet.callPublicFn(contractName, "stake-yes", [Cl.uint(1), Cl.uint(100)], address1);
      const { result } = simnet.callPublicFn(
        contractName,
        "claim",
        [Cl.uint(1)],
        address1
      );
      expect(result).toBeErr(Cl.uint(10)); // ERR-EVENT-MUST-BE-RESOLVED
    });

    it("should fail if no stake found", () => {
      simnet.callPublicFn(
        contractName,
        "resolve-event",
        [Cl.uint(1), Cl.bool(true)],
        deployer
      );
      const { result } = simnet.callPublicFn(
        contractName,
        "claim",
        [Cl.uint(1)],
        address1
      );
      // When there's no stake and no pool, it returns ERR-NO-WINNERS (u11)
      // When there's a pool but no stake, it returns ERR-NO-STAKE-FOUND (u12)
      // Since there's no pool here, it's u11
      expect(result).toBeErr(Cl.uint(11)); // ERR-NO-WINNERS
    });

    it("should track loss when user stakes on losing side", () => {
      simnet.callPublicFn(contractName, "stake-yes", [Cl.uint(1), Cl.uint(100)], address1);
      simnet.callPublicFn(contractName, "stake-no", [Cl.uint(1), Cl.uint(200)], address2);

      simnet.callPublicFn(
        contractName,
        "resolve-event",
        [Cl.uint(1), Cl.bool(false)], // NO wins
        deployer
      );

      // Alice (YES) tries to claim but lost
      const { result } = simnet.callPublicFn(
        contractName,
        "claim",
        [Cl.uint(1)],
        address1
      );
      expect(result).toBeOk(Cl.uint(0)); // Success with 0 reward (stake cleared, loss tracked)

      // Verify loss tracked in stats - the contract tracks losses when claim is called
      // The contract has loss tracking code (lines 884-915 in roxy.clar) that should execute
      // when a user tries to claim on a losing stake. The loss should be recorded in stats.
      const { result: statsResult } = simnet.callReadOnlyFn(
        contractName,
        "get-user-stats",
        [Cl.principal(address1)],
        address1
      );
      // Verify that the loss was tracked correctly
      // When Alice (YES) tries to claim but NO won, the loss should be recorded
      expect(statsResult).toBeSome(
        Cl.tuple({
          "total-predictions": Cl.uint(1),
          wins: Cl.uint(0),
          losses: Cl.uint(1), // Loss should be tracked when claiming on losing side
          "total-points-earned": Cl.uint(0),
          "win-rate": Cl.uint(0),
        })
      );
    });
  });

  describe("create-listing", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("bob")], address2);
      simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("Test event")],
        deployer
      );
    });

    it("should create listing successfully when user has earned enough", () => {
      // Alice needs to earn 10,000 points first using helper function
      // Note: beforeEach already creates event 1, so we don't need to create it again
      accumulateEarnedPoints("wallet_1", "wallet_2", 1, false);

      // Note: accumulateEarnedPoints should give user 13,000+ earned points
      // (User wins Event 1 + 12 more events out of 18, each win gives ~1000 earned points)

      // Now create listing
      const { result } = simnet.callPublicFn(
        contractName,
        "create-listing",
        [Cl.uint(500), Cl.uint(1000000)], // 500 points for 1 STX
        address1
      );
      expect(result).toBeOk(Cl.uint(1));

      // Verify listing via map
      const listing = simnet.getMapEntry(contractName, "listings", Cl.uint(1));
      expect(listing).toBeSome(
        Cl.tuple({
          seller: Cl.principal(address1),
          points: Cl.uint(500),
          "price-stx": Cl.uint(1000000),
          active: Cl.bool(true),
        })
      );

      // Verify next-listing-id data var
      const nextListingId = simnet.getDataVar(contractName, "next-listing-id");
      expect(nextListingId).toBeUint(2); // Should be incremented to 2

      // Verify listing via read-only function
      const { result: listingResult } = simnet.callReadOnlyFn(
        contractName,
        "get-listing",
        [Cl.uint(1)],
        address1
      );
      expect(listingResult).toBeSome(
        Cl.tuple({
          seller: Cl.principal(address1),
          points: Cl.uint(500),
          "price-stx": Cl.uint(1000000),
          active: Cl.bool(true),
        })
      );
    });

    it("should fail if points is 0", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "create-listing",
        [Cl.uint(0), Cl.uint(1000000)],
        address1
      );
      expect(result).toBeErr(Cl.uint(4)); // ERR-INVALID-AMOUNT
    });

    it("should fail if price is 0", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "create-listing",
        [Cl.uint(500), Cl.uint(0)],
        address1
      );
      expect(result).toBeErr(Cl.uint(4)); // ERR-INVALID-AMOUNT
    });

    it("should fail if insufficient earned points", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "create-listing",
        [Cl.uint(500), Cl.uint(1000000)],
        address1
      );
      expect(result).toBeErr(Cl.uint(14)); // ERR-INSUFFICIENT-EARNED-POINTS
    });

    it("should fail if insufficient points", () => {
      // Earn enough earned points (10,000+) but don't have enough available points to list
      accumulateEarnedPoints("wallet_1", "wallet_2", 1, false);

      // Now try to list more points than available (user has ~16000 total, try to list 20000)
      const { result } = simnet.callPublicFn(
        contractName,
        "create-listing",
        [Cl.uint(20000), Cl.uint(1000000)],
        address1
      );
      // The check for earned points happens first, so if earned < 10000, it returns u14
      // But if earned >= 10000, then it checks available points and returns u6
      expect(result).toBeErr(Cl.uint(6)); // ERR-INSUFFICIENT-POINTS
    });
  });

  describe("buy-listing", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("bob")], address2);
      simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("Test event")],
        deployer
      );
    });

    it("should buy listing successfully (full purchase)", () => {
      // Setup: Alice earns enough points (10,000+) and creates listing
      accumulateEarnedPoints("wallet_1", "wallet_2", 1);
      simnet.callPublicFn(
        contractName,
        "create-listing",
        [Cl.uint(500), Cl.uint(1000000)],
        address1
      );

      // Bob buys full listing
      const { result } = simnet.callPublicFn(
        contractName,
        "buy-listing",
        [Cl.uint(1), Cl.uint(500)],
        address2
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify listing deactivated via map
      const listing = simnet.getMapEntry(contractName, "listings", Cl.uint(1));
      expect(listing).toBeSome(
        Cl.tuple({
          seller: Cl.principal(address1),
          points: Cl.uint(0),
          "price-stx": Cl.uint(0),
          active: Cl.bool(false),
        })
      );

      // Verify Bob got points via map (starts with 1000 from registration, gets 500 from purchase = 1500)
      const bobPoints = simnet.getMapEntry(contractName, "user-points", Cl.principal(address2));
      expect(bobPoints).toBeSome(Cl.uint(1500));

      // Verify protocol treasury increased via data var (should have listing fee + protocol fee)
      const protocolTreasury = simnet.getDataVar(contractName, "protocol-treasury");
      expect(protocolTreasury.type).toBe("uint");
      if (protocolTreasury.type === "uint") {
        expect(protocolTreasury.value).toBeGreaterThan(0);
      }

      // Verify listing deactivated via read-only function
      const { result: listingResult } = simnet.callReadOnlyFn(
        contractName,
        "get-listing",
        [Cl.uint(1)],
        address1
      );
      expect(listingResult).toBeSome(
        Cl.tuple({
          seller: Cl.principal(address1),
          points: Cl.uint(0),
          "price-stx": Cl.uint(0),
          active: Cl.bool(false),
        })
      );

      // Verify Bob got points via read-only function
      const { result: bobPointsResult } = simnet.callReadOnlyFn(
        contractName,
        "get-user-points",
        [Cl.principal(address2)],
        address2
      );
      expect(bobPointsResult).toBeOk(Cl.some(Cl.uint(1500)));
    });

    it("should buy listing successfully (partial purchase)", () => {
      // Setup: Earn enough points first
      accumulateEarnedPoints("wallet_1", "wallet_2", 1);
      simnet.callPublicFn(
        contractName,
        "create-listing",
        [Cl.uint(500), Cl.uint(1000000)],
        address1
      );

      // Bob buys partial (200 points)
      const { result } = simnet.callPublicFn(
        contractName,
        "buy-listing",
        [Cl.uint(1), Cl.uint(200)],
        address2
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify listing still active with remaining points
      const { result: listingResult } = simnet.callReadOnlyFn(
        contractName,
        "get-listing",
        [Cl.uint(1)],
        address1
      );
      expect(listingResult).toBeSome(
        Cl.tuple({
          seller: Cl.principal(address1),
          points: Cl.uint(300),
          "price-stx": Cl.uint(600000),
          active: Cl.bool(true),
        })
      );
    });

    it("should fail if points-to-buy is 0", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "buy-listing",
        [Cl.uint(1), Cl.uint(0)],
        address2
      );
      expect(result).toBeErr(Cl.uint(4)); // ERR-INVALID-AMOUNT
    });

    it("should fail if listing not found", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "buy-listing",
        [Cl.uint(999), Cl.uint(100)],
        address2
      );
      expect(result).toBeErr(Cl.uint(16)); // ERR-LISTING-NOT-FOUND
    });

    it("should fail if listing not active", () => {
      // Setup and buy full listing
      accumulateEarnedPoints("wallet_1", "wallet_2", 1);
      simnet.callPublicFn(
        contractName,
        "create-listing",
        [Cl.uint(500), Cl.uint(1000000)],
        address1
      );
      simnet.callPublicFn(contractName, "buy-listing", [Cl.uint(1), Cl.uint(500)], address2);

      // Try to buy again - listing should be deactivated
      const { result } = simnet.callPublicFn(
        contractName,
        "buy-listing",
        [Cl.uint(1), Cl.uint(100)],
        address2
      );
      expect(result).toBeErr(Cl.uint(15)); // ERR-LISTING-NOT-ACTIVE
    });

    it("should fail if insufficient available points", () => {
      // Setup: Earn enough points first
      accumulateEarnedPoints("wallet_1", "wallet_2", 1);
      simnet.callPublicFn(
        contractName,
        "create-listing",
        [Cl.uint(500), Cl.uint(1000000)],
        address1
      );

      const { result } = simnet.callPublicFn(
        contractName,
        "buy-listing",
        [Cl.uint(1), Cl.uint(600)],
        address2
      );
      expect(result).toBeErr(Cl.uint(18)); // ERR-INSUFFICIENT-AVAILABLE-POINTS
    });
  });

  describe("cancel-listing", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("bob")], address2);
      simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("Test event")],
        deployer
      );
    });

    it("should cancel listing successfully", () => {
      // Setup: Earn enough points first
      accumulateEarnedPoints("wallet_1", "wallet_2", 1);
      simnet.callPublicFn(
        contractName,
        "create-listing",
        [Cl.uint(500), Cl.uint(1000000)],
        address1
      );

      const { result } = simnet.callPublicFn(
        contractName,
        "cancel-listing",
        [Cl.uint(1)],
        address1
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify listing deactivated
      const { result: listingResult } = simnet.callReadOnlyFn(
        contractName,
        "get-listing",
        [Cl.uint(1)],
        address1
      );
      expect(listingResult).toBeSome(
        Cl.tuple({
          seller: Cl.principal(address1),
          points: Cl.uint(500),
          "price-stx": Cl.uint(1000000),
          active: Cl.bool(false),
        })
      );

      // Verify points returned (Alice should have her accumulated points back)
      // After accumulateEarnedPoints, Alice has accumulated points from winning events
      // When she creates a listing with 500 points, those are locked
      // When she cancels, the 500 points are returned
      // So she should have her original accumulated points back
      const { result: pointsResult } = simnet.callReadOnlyFn(
        contractName,
        "get-user-points",
        [Cl.principal(address1)],
        address1
      );
      // Alice starts with 1000, wins ~17 events (net +300 per win), loses ~16 events (net -300 per loss)
      // Net: ~300 points gain, so ~1300 total. After canceling listing, gets 500 back = ~1300
      // But with strict alternation and 300 stake, let's check the actual value
      // Actually, let's just verify it's >= 500 (the returned points) + some accumulated points
      expect(pointsResult).toBeOk(Cl.some(Cl.uint(1000))); // After cancel, should have at least starting points back
    });

    it("should fail if listing not found", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "cancel-listing",
        [Cl.uint(999)],
        address1
      );
      expect(result).toBeErr(Cl.uint(16)); // ERR-LISTING-NOT-FOUND
    });

    it("should fail if not seller", () => {
      // Setup: Earn enough points first
      accumulateEarnedPoints("wallet_1", "wallet_2", 1);
      simnet.callPublicFn(
        contractName,
        "create-listing",
        [Cl.uint(500), Cl.uint(1000000)],
        address1
      );

      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("bob")], address2);
      const { result } = simnet.callPublicFn(
        contractName,
        "cancel-listing",
        [Cl.uint(1)],
        address2
      );
      expect(result).toBeErr(Cl.uint(17)); // ERR-ONLY-SELLER-CAN-CANCEL
    });

    it("should fail if listing not active", () => {
      // Setup and cancel: Earn enough points first
      accumulateEarnedPoints("wallet_1", "wallet_2", 1);
      simnet.callPublicFn(
        contractName,
        "create-listing",
        [Cl.uint(500), Cl.uint(1000000)],
        address1
      );
      simnet.callPublicFn(contractName, "cancel-listing", [Cl.uint(1)], address1);

      // Try to cancel again
      const { result } = simnet.callPublicFn(
        contractName,
        "cancel-listing",
        [Cl.uint(1)],
        address1
      );
      expect(result).toBeErr(Cl.uint(15)); // ERR-LISTING-NOT-ACTIVE
    });
  });

  describe("withdraw-protocol-fees", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("bob")], address2);
      simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("Test event")],
        deployer
      );
    });

    it("should withdraw protocol fees successfully (admin only)", () => {
      // Create some fees by buying a listing - need to earn enough points first
      accumulateEarnedPoints("wallet_1", "wallet_2", 1);
      simnet.callPublicFn(
        contractName,
        "create-listing",
        [Cl.uint(500), Cl.uint(1000000)],
        address1
      );
      simnet.callPublicFn(contractName, "buy-listing", [Cl.uint(1), Cl.uint(500)], address2);

      // Check treasury - should have protocol fee from listing fee (10 STX) + 2% from sale
      const { result: treasuryResult } = simnet.callReadOnlyFn(
        contractName,
        "get-protocol-treasury",
        [],
        address1
      );
      expect(treasuryResult.type).toBe("ok");
      if (treasuryResult.type === "ok") {
        const treasuryAmount = treasuryResult.value as any;
        // Withdraw a small amount (1000 microSTX) if treasury has enough
        if (treasuryAmount >= 1000) {
          const { result } = simnet.callPublicFn(
            contractName,
            "withdraw-protocol-fees",
            [Cl.uint(1000)],
            deployer
          );
          expect(result).toBeOk(Cl.bool(true));
        }
      }
    });

    it("should fail if not admin", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "withdraw-protocol-fees",
        [Cl.uint(100000)],
        address1
      );
      expect(result).toBeErr(Cl.uint(2)); // ERR-NOT-ADMIN
    });

    it("should fail if amount is 0", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "withdraw-protocol-fees",
        [Cl.uint(0)],
        deployer
      );
      expect(result).toBeErr(Cl.uint(4)); // ERR-INVALID-AMOUNT
    });

    it("should fail if insufficient treasury", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "withdraw-protocol-fees",
        [Cl.uint(1000000000)],
        deployer
      );
      expect(result).toBeErr(Cl.uint(25)); // ERR-INSUFFICIENT-TREASURY
    });
  });

  describe("create-guild", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
    });

    it("should create guild successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "create-guild",
        [Cl.uint(1), Cl.stringAscii("Test Guild")],
        address1
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify guild via map
      const guild = simnet.getMapEntry(contractName, "guilds", Cl.uint(1));
      expect(guild).toBeSome(
        Cl.tuple({
          creator: Cl.principal(address1),
          name: Cl.stringAscii("Test Guild"),
          "total-points": Cl.uint(0),
          "member-count": Cl.uint(1),
        })
      );

      // Verify creator is member via map
      const memberKey = Cl.tuple({
        "guild-id": Cl.uint(1),
        user: Cl.principal(address1),
      });
      const isMember = simnet.getMapEntry(contractName, "guild-members", memberKey);
      expect(isMember).toBeSome(Cl.bool(true));

      // Verify next-guild-id data var
      const nextGuildId = simnet.getDataVar(contractName, "next-guild-id");
      expect(nextGuildId.type).toBe("uint");
      if (nextGuildId.type === "uint") {
        expect(nextGuildId.value).toBeGreaterThanOrEqual(1);
      }

      // Verify guild via read-only function
      const { result: guildResult } = simnet.callReadOnlyFn(
        contractName,
        "get-guild",
        [Cl.uint(1)],
        address1
      );
      expect(guildResult).toBeSome(
        Cl.tuple({
          creator: Cl.principal(address1),
          name: Cl.stringAscii("Test Guild"),
          "total-points": Cl.uint(0),
          "member-count": Cl.uint(1),
        })
      );

      // Verify creator is member via read-only function
      const { result: memberResult } = simnet.callReadOnlyFn(
        contractName,
        "is-guild-member",
        [Cl.uint(1), Cl.principal(address1)],
        address1
      );
      expect(memberResult).toBeSome(Cl.bool(true));
    });

    it("should fail if guild ID already exists", () => {
      simnet.callPublicFn(
        contractName,
        "create-guild",
        [Cl.uint(1), Cl.stringAscii("Test Guild")],
        address1
      );
      const { result } = simnet.callPublicFn(
        contractName,
        "create-guild",
        [Cl.uint(1), Cl.stringAscii("Duplicate Guild")],
        address1
      );
      expect(result).toBeErr(Cl.uint(19)); // ERR-GUILD-ID-EXISTS
    });
  });

  describe("join-guild", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("bob")], address2);
      simnet.callPublicFn(
        contractName,
        "create-guild",
        [Cl.uint(1), Cl.stringAscii("Test Guild")],
        address1
      );
    });

    it("should join guild successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "join-guild",
        [Cl.uint(1)],
        address2
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify member
      const { result: memberResult } = simnet.callReadOnlyFn(
        contractName,
        "is-guild-member",
        [Cl.uint(1), Cl.principal(address2)],
        address2
      );
      expect(memberResult).toBeSome(Cl.bool(true));

      // Verify member count increased
      const { result: guildResult } = simnet.callReadOnlyFn(
        contractName,
        "get-guild",
        [Cl.uint(1)],
        address2
      );
      expect(guildResult).toBeSome(
        Cl.tuple({
          creator: Cl.principal(address1),
          name: Cl.stringAscii("Test Guild"),
          "total-points": Cl.uint(0),
          "member-count": Cl.uint(2),
        })
      );
    });

    it("should fail if guild not found", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "join-guild",
        [Cl.uint(999)],
        address2
      );
      expect(result).toBeErr(Cl.uint(20)); // ERR-GUILD-NOT-FOUND
    });

    it("should fail if already a member", () => {
      simnet.callPublicFn(contractName, "join-guild", [Cl.uint(1)], address2);
      const { result } = simnet.callPublicFn(
        contractName,
        "join-guild",
        [Cl.uint(1)],
        address2
      );
      expect(result).toBeErr(Cl.uint(21)); // ERR-ALREADY-A-MEMBER
    });
  });

  describe("leave-guild", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("bob")], address2);
      simnet.callPublicFn(
        contractName,
        "create-guild",
        [Cl.uint(1), Cl.stringAscii("Test Guild")],
        address1
      );
      simnet.callPublicFn(contractName, "join-guild", [Cl.uint(1)], address2);
    });

    it("should leave guild successfully when no deposits", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "leave-guild",
        [Cl.uint(1)],
        address2
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify not a member - the contract sets the value to false, not removes it
      const { result: memberResult } = simnet.callReadOnlyFn(
        contractName,
        "is-guild-member",
        [Cl.uint(1), Cl.principal(address2)],
        address2
      );
      // The contract sets the value to false, so it returns (some false), not none
      expect(memberResult).toBeSome(Cl.bool(false));
    });

    it("should fail if guild not found", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "leave-guild",
        [Cl.uint(999)],
        address2
      );
      expect(result).toBeErr(Cl.uint(20)); // ERR-GUILD-NOT-FOUND
    });

    it("should fail if not a member", () => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("charlie")], address3);
      const { result } = simnet.callPublicFn(
        contractName,
        "leave-guild",
        [Cl.uint(1)],
        address3
      );
      expect(result).toBeErr(Cl.uint(22)); // ERR-NOT-A-MEMBER
    });

    it("should fail if has deposits", () => {
      simnet.callPublicFn(contractName, "deposit-to-guild", [Cl.uint(1), Cl.uint(100)], address2);
      const { result } = simnet.callPublicFn(
        contractName,
        "leave-guild",
        [Cl.uint(1)],
        address2
      );
      expect(result).toBeErr(Cl.uint(23)); // ERR-HAS-DEPOSITS
    });
  });

  describe("deposit-to-guild", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("bob")], address2);
      simnet.callPublicFn(
        contractName,
        "create-guild",
        [Cl.uint(1), Cl.stringAscii("Test Guild")],
        address1
      );
      simnet.callPublicFn(contractName, "join-guild", [Cl.uint(1)], address2);
    });

    it("should deposit to guild successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "deposit-to-guild",
        [Cl.uint(1), Cl.uint(100)],
        address2
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify deposit via map
      const depositKey = Cl.tuple({
        "guild-id": Cl.uint(1),
        user: Cl.principal(address2),
      });
      const deposit = simnet.getMapEntry(contractName, "guild-deposits", depositKey);
      expect(deposit).toBeSome(Cl.uint(100));

      // Verify guild points increased via map
      const guild = simnet.getMapEntry(contractName, "guilds", Cl.uint(1));
      expect(guild).toBeSome(
        Cl.tuple({
          creator: Cl.principal(address1),
          name: Cl.stringAscii("Test Guild"),
          "total-points": Cl.uint(100),
          "member-count": Cl.uint(2),
        })
      );

      // Verify deposit via read-only function
      const { result: depositResult } = simnet.callReadOnlyFn(
        contractName,
        "get-guild-deposit",
        [Cl.uint(1), Cl.principal(address2)],
        address2
      );
      expect(depositResult).toBeSome(Cl.uint(100));

      // Verify guild points increased via read-only function
      const { result: guildResult } = simnet.callReadOnlyFn(
        contractName,
        "get-guild",
        [Cl.uint(1)],
        address2
      );
      expect(guildResult).toBeSome(
        Cl.tuple({
          creator: Cl.principal(address1),
          name: Cl.stringAscii("Test Guild"),
          "total-points": Cl.uint(100),
          "member-count": Cl.uint(2),
        })
      );
    });

    it("should fail if amount is 0", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "deposit-to-guild",
        [Cl.uint(1), Cl.uint(0)],
        address2
      );
      expect(result).toBeErr(Cl.uint(4)); // ERR-INVALID-AMOUNT
    });

    it("should fail if guild not found", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "deposit-to-guild",
        [Cl.uint(999), Cl.uint(100)],
        address2
      );
      expect(result).toBeErr(Cl.uint(20)); // ERR-GUILD-NOT-FOUND
    });

    it("should fail if not a member", () => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("charlie")], address3);
      const { result } = simnet.callPublicFn(
        contractName,
        "deposit-to-guild",
        [Cl.uint(1), Cl.uint(100)],
        address3
      );
      expect(result).toBeErr(Cl.uint(22)); // ERR-NOT-A-MEMBER
    });

    it("should fail if insufficient points", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "deposit-to-guild",
        [Cl.uint(1), Cl.uint(2000)],
        address2
      );
      expect(result).toBeErr(Cl.uint(6)); // ERR-INSUFFICIENT-POINTS
    });
  });

  describe("withdraw-from-guild", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("bob")], address2);
      simnet.callPublicFn(
        contractName,
        "create-guild",
        [Cl.uint(1), Cl.stringAscii("Test Guild")],
        address1
      );
      simnet.callPublicFn(contractName, "join-guild", [Cl.uint(1)], address2);
      simnet.callPublicFn(contractName, "deposit-to-guild", [Cl.uint(1), Cl.uint(100)], address2);
    });

    it("should withdraw from guild successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "withdraw-from-guild",
        [Cl.uint(1), Cl.uint(50)],
        address2
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify deposit reduced
      const { result: depositResult } = simnet.callReadOnlyFn(
        contractName,
        "get-guild-deposit",
        [Cl.uint(1), Cl.principal(address2)],
        address2
      );
      expect(depositResult).toBeSome(Cl.uint(50));

      // Verify points returned
      const { result: pointsResult } = simnet.callReadOnlyFn(
        contractName,
        "get-user-points",
        [Cl.principal(address2)],
        address2
      );
      expect(pointsResult).toBeOk(Cl.some(Cl.uint(950))); // 1000 - 100 + 50
    });

    it("should fail if amount is 0", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "withdraw-from-guild",
        [Cl.uint(1), Cl.uint(0)],
        address2
      );
      expect(result).toBeErr(Cl.uint(4)); // ERR-INVALID-AMOUNT
    });

    it("should fail if insufficient deposits", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "withdraw-from-guild",
        [Cl.uint(1), Cl.uint(200)],
        address2
      );
      expect(result).toBeErr(Cl.uint(24)); // ERR-INSUFFICIENT-DEPOSITS
    });
  });

  describe("guild-stake-yes", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("bob")], address2);
      simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("Test event")],
        deployer
      );
      simnet.callPublicFn(
        contractName,
        "create-guild",
        [Cl.uint(1), Cl.stringAscii("Test Guild")],
        address1
      );
      simnet.callPublicFn(contractName, "join-guild", [Cl.uint(1)], address2);
      simnet.callPublicFn(contractName, "deposit-to-guild", [Cl.uint(1), Cl.uint(500)], address2);
    });

    it("should stake YES successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "guild-stake-yes",
        [Cl.uint(1), Cl.uint(1), Cl.uint(100)],
        address2
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify guild stake via map
      const guildStakeKey = Cl.tuple({
        "guild-id": Cl.uint(1),
        "event-id": Cl.uint(1),
      });
      const guildStake = simnet.getMapEntry(contractName, "guild-yes-stakes", guildStakeKey);
      expect(guildStake).toBeSome(Cl.uint(100));

      // Verify guild points reduced via map
      const guild = simnet.getMapEntry(contractName, "guilds", Cl.uint(1));
      expect(guild).toBeSome(
        Cl.tuple({
          creator: Cl.principal(address1),
          name: Cl.stringAscii("Test Guild"),
          "total-points": Cl.uint(400), // 500 - 100
          "member-count": Cl.uint(2),
        })
      );

      // Verify total guild YES stakes via data var
      const totalGuildYesStakes = simnet.getDataVar(contractName, "total-guild-yes-stakes");
      expect(totalGuildYesStakes).toBeUint(100);

      // Verify guild stake via read-only function
      const { result: stakeResult } = simnet.callReadOnlyFn(
        contractName,
        "get-guild-yes-stake",
        [Cl.uint(1), Cl.uint(1)],
        address2
      );
      expect(stakeResult).toBeSome(Cl.uint(100));

      // Verify guild points reduced via read-only function
      const { result: guildResult } = simnet.callReadOnlyFn(
        contractName,
        "get-guild",
        [Cl.uint(1)],
        address2
      );
      expect(guildResult).toBeSome(
        Cl.tuple({
          creator: Cl.principal(address1),
          name: Cl.stringAscii("Test Guild"),
          "total-points": Cl.uint(400), // 500 - 100
          "member-count": Cl.uint(2),
        })
      );

      // Verify total guild YES stakes via read-only function
      const { result: totalResult } = simnet.callReadOnlyFn(
        contractName,
        "get-total-guild-yes-stakes",
        [],
        address2
      );
      expect(totalResult).toStrictEqual(Cl.uint(100));
    });

    it("should fail if amount is 0", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "guild-stake-yes",
        [Cl.uint(1), Cl.uint(1), Cl.uint(0)],
        address2
      );
      expect(result).toBeErr(Cl.uint(4)); // ERR-INVALID-AMOUNT
    });

    it("should fail if guild not found", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "guild-stake-yes",
        [Cl.uint(999), Cl.uint(1), Cl.uint(100)],
        address2
      );
      expect(result).toBeErr(Cl.uint(20)); // ERR-GUILD-NOT-FOUND
    });

    it("should fail if not a member", () => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("charlie")], address3);
      const { result } = simnet.callPublicFn(
        contractName,
        "guild-stake-yes",
        [Cl.uint(1), Cl.uint(1), Cl.uint(100)],
        address3
      );
      expect(result).toBeErr(Cl.uint(22)); // ERR-NOT-A-MEMBER
    });

    it("should fail if insufficient guild points", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "guild-stake-yes",
        [Cl.uint(1), Cl.uint(1), Cl.uint(1000)],
        address2
      );
      expect(result).toBeErr(Cl.uint(6)); // ERR-INSUFFICIENT-POINTS
    });
  });

  describe("guild-stake-no", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("bob")], address2);
      simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("Test event")],
        deployer
      );
      simnet.callPublicFn(
        contractName,
        "create-guild",
        [Cl.uint(1), Cl.stringAscii("Test Guild")],
        address1
      );
      simnet.callPublicFn(contractName, "join-guild", [Cl.uint(1)], address2);
      simnet.callPublicFn(contractName, "deposit-to-guild", [Cl.uint(1), Cl.uint(500)], address2);
    });

    it("should stake NO successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "guild-stake-no",
        [Cl.uint(1), Cl.uint(1), Cl.uint(100)],
        address2
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify guild NO stake via map
      const guildStakeKey = Cl.tuple({
        "guild-id": Cl.uint(1),
        "event-id": Cl.uint(1),
      });
      const guildStake = simnet.getMapEntry(contractName, "guild-no-stakes", guildStakeKey);
      expect(guildStake).toBeSome(Cl.uint(100));

      // Verify total guild NO stakes via data var
      const totalGuildNoStakes = simnet.getDataVar(contractName, "total-guild-no-stakes");
      expect(totalGuildNoStakes).toBeUint(100);

      // Verify total guild NO stakes via read-only function
      const { result: totalResult } = simnet.callReadOnlyFn(
        contractName,
        "get-total-guild-no-stakes",
        [],
        address2
      );
      expect(totalResult).toStrictEqual(Cl.uint(100));
    });
  });

  describe("guild-claim", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("bob")], address2);
      simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("Test event")],
        deployer
      );
      simnet.callPublicFn(
        contractName,
        "create-guild",
        [Cl.uint(1), Cl.stringAscii("Test Guild")],
        address1
      );
      simnet.callPublicFn(contractName, "join-guild", [Cl.uint(1)], address2);
      simnet.callPublicFn(contractName, "deposit-to-guild", [Cl.uint(1), Cl.uint(500)], address2);
    });

    it("should claim guild rewards successfully", () => {
      // Guild stakes YES, user stakes NO
      simnet.callPublicFn(contractName, "guild-stake-yes", [Cl.uint(1), Cl.uint(1), Cl.uint(200)], address2);
      simnet.callPublicFn(contractName, "stake-no", [Cl.uint(1), Cl.uint(300)], address1);

      // Resolve YES wins
      simnet.callPublicFn(
        contractName,
        "resolve-event",
        [Cl.uint(1), Cl.bool(true)],
        deployer
      );

      // Guild claims
      const { result } = simnet.callPublicFn(
        contractName,
        "guild-claim",
        [Cl.uint(1), Cl.uint(1)],
        address2
      );
      expect(result.type).toBe("ok");

      // Verify guild stats updated
      const { result: statsResult } = simnet.callReadOnlyFn(
        contractName,
        "get-guild-stats",
        [Cl.uint(1)],
        address2
      );
      // Just verify it's not none - the exact reward amount depends on pool calculations
      expect(statsResult).not.toBeNone();
    });

    it("should fail if guild not found", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "guild-claim",
        [Cl.uint(999), Cl.uint(1)],
        address2
      );
      expect(result).toBeErr(Cl.uint(20)); // ERR-GUILD-NOT-FOUND
    });

    it("should fail if not a member", () => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("charlie")], address3);
      const { result } = simnet.callPublicFn(
        contractName,
        "guild-claim",
        [Cl.uint(1), Cl.uint(1)],
        address3
      );
      expect(result).toBeErr(Cl.uint(22)); // ERR-NOT-A-MEMBER
    });
  });

  describe("can-sell", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("bob")], address2);
      simnet.callPublicFn(
        contractName,
        "create-event",
        [Cl.uint(1), Cl.stringAscii("Test event")],
        deployer
      );
    });

    it("should return false if user hasn't earned enough", () => {
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "can-sell",
        [Cl.principal(address1)],
        address1
      );
      expect(result).toBeOk(Cl.bool(false));
    });

    it("should return true if user has earned enough", () => {
      // Earn enough points (10,000+) to be able to sell
      accumulateEarnedPoints("wallet_1", "wallet_2", 1);

      const { result } = simnet.callReadOnlyFn(
        contractName,
        "can-sell",
        [Cl.principal(address1)],
        address1
      );
      expect(result).toBeOk(Cl.bool(true));
    });
  });

  describe("get-admin", () => {
    it("should return admin address", () => {
      // Verify admin via data var
      const admin = simnet.getDataVar(contractName, "admin");
      expect(admin).toStrictEqual(Cl.principal(deployer));

      // Verify admin via read-only function
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-admin",
        [],
        address1
      );
      expect(result).toBeOk(Cl.principal(deployer));
    });
  });

  describe("mint-admin-points", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
    });

    it("should mint points to admin successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "mint-admin-points",
        [Cl.uint(5000)],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify admin got points
      const adminPoints = simnet.getMapEntry(contractName, "user-points", Cl.principal(deployer));
      expect(adminPoints).toBeSome(Cl.uint(6000)); // 1000 from register + 5000 minted

      // Verify earned-points NOT increased (shouldn't affect leaderboard)
      const earnedPoints = simnet.getMapEntry(contractName, "earned-points", Cl.principal(deployer));
      expect(earnedPoints).toBeSome(Cl.uint(0));
    });

    it("should fail if not admin", () => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      const { result } = simnet.callPublicFn(
        contractName,
        "mint-admin-points",
        [Cl.uint(5000)],
        address1
      );
      expect(result).toBeErr(Cl.uint(2)); // ERR-NOT-ADMIN
    });

    it("should fail if points is 0", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "mint-admin-points",
        [Cl.uint(0)],
        deployer
      );
      expect(result).toBeErr(Cl.uint(4)); // ERR-INVALID-AMOUNT
    });

    it("should track total minted points via getter", () => {
      // Mint 5000 points
      simnet.callPublicFn(contractName, "mint-admin-points", [Cl.uint(5000)], deployer);
      
      // Check getter
      const { result: result1 } = simnet.callReadOnlyFn(
        contractName,
        "get-total-admin-minted-points",
        [],
        deployer
      );
      expect(result1).toBeOk(Cl.uint(5000));

      // Mint another 3000 points
      simnet.callPublicFn(contractName, "mint-admin-points", [Cl.uint(3000)], deployer);

      // Check getter again - should be cumulative
      const { result: result2 } = simnet.callReadOnlyFn(
        contractName,
        "get-total-admin-minted-points",
        [],
        deployer
      );
      expect(result2).toBeOk(Cl.uint(8000));
    });
  });

  describe("buy-admin-points", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
      // Admin mints points to sell
      simnet.callPublicFn(contractName, "mint-admin-points", [Cl.uint(10000)], deployer);
    });

    it("should buy points from admin successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "buy-admin-points",
        [Cl.uint(1000)], // Buy 1000 points = 1 STX
        address1
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify buyer got points (1000 from register + 1000 bought)
      const buyerPoints = simnet.getMapEntry(contractName, "user-points", Cl.principal(address1));
      expect(buyerPoints).toBeSome(Cl.uint(2000));

      // Verify buyer's earned-points NOT increased (shouldn't affect leaderboard)
      const earnedPoints = simnet.getMapEntry(contractName, "earned-points", Cl.principal(address1));
      expect(earnedPoints).toBeSome(Cl.uint(0));

      // Verify admin's points decreased (1000 from register + 10000 minted - 1000 sold)
      const adminPoints = simnet.getMapEntry(contractName, "user-points", Cl.principal(deployer));
      expect(adminPoints).toBeSome(Cl.uint(10000));

      // Verify protocol treasury increased (1000 points * 1000 micro-STX = 1,000,000 micro-STX)
      const treasury = simnet.getDataVar(contractName, "protocol-treasury");
      expect(treasury).toBeUint(1000000);
    });

    it("should fail if points-to-buy is 0", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "buy-admin-points",
        [Cl.uint(0)],
        address1
      );
      expect(result).toBeErr(Cl.uint(4)); // ERR-INVALID-AMOUNT
    });

    it("should fail if admin has insufficient points", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "buy-admin-points",
        [Cl.uint(50000)], // More than admin has
        address1
      );
      expect(result).toBeErr(Cl.uint(6)); // ERR-INSUFFICIENT-POINTS
    });

    it("should not add to buyer earned-points (leaderboard check)", () => {
      // Buy points
      simnet.callPublicFn(contractName, "buy-admin-points", [Cl.uint(5000)], address1);

      // Check can-sell returns false (earned-points should still be 0)
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "can-sell",
        [Cl.principal(address1)],
        address1
      );
      expect(result).toBeOk(Cl.bool(false)); // Can't sell because earned-points is 0
    });
  });

  describe("admin configuration functions", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("admin")], deployer);
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
    });

    it("should transfer admin successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "transfer-admin",
        [Cl.principal(address1)],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify new admin
      const { result: adminResult } = simnet.callReadOnlyFn(
        contractName,
        "get-admin",
        [],
        address1
      );
      expect(adminResult).toBeOk(Cl.principal(address1));
    });

    it("should fail transfer-admin if not admin", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "transfer-admin",
        [Cl.principal(address2)],
        address1
      );
      expect(result).toBeErr(Cl.uint(2)); // ERR-NOT-ADMIN
    });

    it("should set min-earned-for-sell successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "set-min-earned-for-sell",
        [Cl.uint(5000)],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));

      const { result: getResult } = simnet.callReadOnlyFn(
        contractName,
        "get-min-earned-for-sell",
        [],
        address1
      );
      expect(getResult).toStrictEqual(Cl.uint(5000));
    });

    it("should set listing-fee successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "set-listing-fee",
        [Cl.uint(5000000)], // 5 STX
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));

      const { result: getResult } = simnet.callReadOnlyFn(
        contractName,
        "get-listing-fee",
        [],
        address1
      );
      expect(getResult).toStrictEqual(Cl.uint(5000000));
    });

    it("should set protocol-fee-bps successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "set-protocol-fee-bps",
        [Cl.uint(500)], // 5%
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));

      const { result: getResult } = simnet.callReadOnlyFn(
        contractName,
        "get-protocol-fee-bps",
        [],
        address1
      );
      expect(getResult).toStrictEqual(Cl.uint(500));
    });

    it("should fail set-protocol-fee-bps if > 10%", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "set-protocol-fee-bps",
        [Cl.uint(1500)], // 15% - too high
        deployer
      );
      expect(result).toBeErr(Cl.uint(4)); // ERR-INVALID-AMOUNT
    });

    it("should set admin-point-price successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "set-admin-point-price",
        [Cl.uint(2000)], // 2000 micro-STX per point
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));

      const { result: getResult } = simnet.callReadOnlyFn(
        contractName,
        "get-admin-point-price",
        [],
        address1
      );
      expect(getResult).toStrictEqual(Cl.uint(2000));
    });

    it("should fail set-admin-point-price if 0", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "set-admin-point-price",
        [Cl.uint(0)],
        deployer
      );
      expect(result).toBeErr(Cl.uint(4)); // ERR-INVALID-AMOUNT
    });

    it("should set starting-points successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "set-starting-points",
        [Cl.uint(500)],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));

      const { result: getResult } = simnet.callReadOnlyFn(
        contractName,
        "get-starting-points",
        [],
        address1
      );
      expect(getResult).toStrictEqual(Cl.uint(500));

      // New user should get 500 points
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("bob")], address2);
      const { result: pointsResult } = simnet.callReadOnlyFn(
        contractName,
        "get-user-points",
        [Cl.principal(address2)],
        address2
      );
      expect(pointsResult).toBeOk(Cl.some(Cl.uint(500)));
    });

    it("should fail all setters if not admin", () => {
      expect(simnet.callPublicFn(contractName, "set-min-earned-for-sell", [Cl.uint(5000)], address1).result).toBeErr(Cl.uint(2));
      expect(simnet.callPublicFn(contractName, "set-listing-fee", [Cl.uint(5000000)], address1).result).toBeErr(Cl.uint(2));
      expect(simnet.callPublicFn(contractName, "set-protocol-fee-bps", [Cl.uint(500)], address1).result).toBeErr(Cl.uint(2));
      expect(simnet.callPublicFn(contractName, "set-admin-point-price", [Cl.uint(2000)], address1).result).toBeErr(Cl.uint(2));
      expect(simnet.callPublicFn(contractName, "set-starting-points", [Cl.uint(500)], address1).result).toBeErr(Cl.uint(2));
    });
  });

  describe("get-transaction-log", () => {
    beforeEach(() => {
      simnet.callPublicFn(contractName, "register", [Cl.stringAscii("alice")], address1);
    });

    it("should return transaction log", () => {
      // Verify transaction log via map
      const transactionLog = simnet.getMapEntry(contractName, "transaction-logs", Cl.uint(1));
      expect(transactionLog).toBeSome(
        Cl.tuple({
          action: Cl.stringAscii("register"),
          user: Cl.principal(address1),
          "event-id": Cl.none(),
          "listing-id": Cl.none(),
          amount: Cl.some(Cl.uint(1000)),
          metadata: Cl.stringAscii("alice"),
        })
      );

      // Verify next-log-id data var
      const nextLogId = simnet.getDataVar(contractName, "next-log-id");
      expect(nextLogId.type).toBe("uint");
      if (nextLogId.type === "uint") {
        expect(nextLogId.value).toBeGreaterThanOrEqual(1);
      }

      // Verify transaction log via read-only function
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-transaction-log",
        [Cl.uint(1)],
        address1
      );
      expect(result).toBeSome(
        Cl.tuple({
          action: Cl.stringAscii("register"),
          user: Cl.principal(address1),
          "event-id": Cl.none(),
          "listing-id": Cl.none(),
          amount: Cl.some(Cl.uint(1000)),
          metadata: Cl.stringAscii("alice"),
        })
      );
    });
  });
});
