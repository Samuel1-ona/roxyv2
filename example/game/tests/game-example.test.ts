import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const wallet1 = accounts.get("wallet_1")!;

describe("Roxy Clicker & SDK Integration Tests", () => {
  it("should increment score on click", () => {
    const campaignId = 1;

    // Initial score should be (ok u0)
    const initialScore = simnet.callReadOnlyFn(
      "game-example",
      "get-player-score",
      [Cl.uint(campaignId), Cl.standardPrincipal(wallet1)],
      wallet1
    );
    expect(initialScore.result).toEqual(Cl.ok(Cl.uint(0)));

    // Click
    const clickResult = simnet.callPublicFn(
      "game-example",
      "click",
      [Cl.uint(campaignId)],
      wallet1
    );
    expect(clickResult.result).toEqual(Cl.ok(Cl.bool(true)));

    // New score should be (ok u1)
    const newScore = simnet.callReadOnlyFn(
      "game-example",
      "get-player-score",
      [Cl.uint(campaignId), Cl.standardPrincipal(wallet1)],
      wallet1
    );
    expect(newScore.result).toEqual(Cl.ok(Cl.uint(1)));
  });

  it("should have SDK wrappers available", () => {
    // This test ensures the contract exports the expected SDK interaction functions
    const campaignId = 1;

    const clickResult = simnet.callPublicFn(
      "game-example",
      "click",
      [Cl.uint(campaignId)],
      wallet1
    );
    expect(clickResult.result).toEqual(Cl.ok(Cl.bool(true)));
  });
});
