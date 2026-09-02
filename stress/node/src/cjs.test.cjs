const { describe, it } = require("node:test");
const assert = require("node:assert/strict");

describe("commonjs", () => {
  it("passes", () => {
    assert.equal(1, 1);
  });
});
