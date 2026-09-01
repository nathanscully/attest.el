import { describe, it, test, expect } from "vitest";

describe("math", () => {
  it("adds", () => {
    expect(1 + 1).toBe(2);
  });
  it("fails on purpose", () => {
    const x: number = 2;
    expect(x).toBe(3);
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
