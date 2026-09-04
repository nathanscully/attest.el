import { describe, it } from "node:test";
import assert from "node:assert/strict";

describe("directory collected by name", () => {
  it("passes without a test suffix", () => {
    assert.equal(1, 1);
  });
  it("fails without a test suffix", () => {
    assert.equal(1, 2);
  });
});
