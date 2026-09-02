import { describe, it } from "node:test";
import assert from "node:assert/strict";

describe("generated names", () => {
  for (const n of [1, 2, 3]) {
    it(`case ${n}`, () => {
      assert.equal(n, n);
    });
  }
  const name = "from a variable";
  it(name, () => {
    assert.equal(1, 1);
  });
  it("prefix " + "concatenated", () => {
    assert.equal(1, 1);
  });
});
