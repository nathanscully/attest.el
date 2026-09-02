import { describe, it, expect } from "vitest";

describe("beta", () => {
  it("same", () => {
    expect(1).toBe(1);
  });
  it("beta fails", () => {
    expect(1).toBe(2);
  });
});
