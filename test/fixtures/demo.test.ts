import { test, describe, it } from "node:test";
import { strictEqual } from "node:assert/strict";

describe("math", () => {
  it("adds", () => {
    strictEqual(1 + 1, 2);
  });
  it("fails on purpose", () => {
    const x: number = 2;
    strictEqual(x, 3);
  });
  describe("nested", () => {
    test("deep passes", () => {});
    test.skip("skipped one", () => {});
    test.todo("todo one");
  });
});

test("top level passes", () => {});
test("throws", () => {
  throw new Error("boom");
});
