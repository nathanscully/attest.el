import { describe, it, beforeEach, afterAll, expect } from "vitest";

describe("failing beforeEach", () => {
  beforeEach(() => {
    throw new Error("hook exploded");
  });
  it("first victim", () => {
    expect(1).toBe(1);
  });
  it("second victim", () => {
    expect(1).toBe(1);
  });
});

describe("failing afterAll", () => {
  afterAll(() => {
    throw new Error("afterAll exploded");
  });
  it("passes before the hook fails", () => {
    expect(1).toBe(1);
  });
});
