import { describe, it } from "node:test";
import assert from "node:assert/strict";

describe("nested under the test directory", () => {
  it("still collected", () => {
    assert.equal(1, 1);
  });
});
