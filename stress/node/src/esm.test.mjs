import { describe, it } from "node:test";
import assert from "node:assert/strict";

describe("plain esm", () => {
  it("passes", () => {
    assert.equal(1, 1);
  });
  it("fails", () => {
    assert.equal(1, 2);
  });
});
