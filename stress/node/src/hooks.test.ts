import { describe, it, beforeEach, after } from "node:test";
import assert from "node:assert/strict";

describe("failing beforeEach", () => {
  beforeEach(() => {
    throw new Error("hook exploded");
  });
  it("first victim", () => {
    assert.equal(1, 1);
  });
  it("second victim", () => {
    assert.equal(1, 1);
  });
});

describe("failing after", () => {
  after(() => {
    throw new Error("after exploded");
  });
  it("passes before the hook fails", () => {
    assert.equal(1, 1);
  });
});

describe("healthy hooks", () => {
  let n = 0;
  beforeEach(() => {
    n += 1;
  });
  it("sees the hook", () => {
    assert.equal(n, 1);
  });
});
