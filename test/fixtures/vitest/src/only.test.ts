import { describe, it, test, expect } from "vitest";

describe("only", () => {
  it.only("the only one", () => {
    expect(1 + 1).toBe(2);
  });
  it("excluded by only", () => {
    expect(1).toBe(1);
  });
  test.skip("written as skip", () => {});
});
