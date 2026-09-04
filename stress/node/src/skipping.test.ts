import { describe, it, test } from "node:test";
import assert from "node:assert/strict";

describe.skip("outer skipped suite", () => {
  it("direct child never runs", () => {
    assert.fail("skipped suite ran");
  });
  describe("nested under a skipped suite", () => {
    it("grandchild never runs", () => {
      assert.fail("skipped suite ran");
    });
  });
});

describe("suite around a skipped suite", () => {
  it("sibling still runs", () => {
    assert.equal(1, 1);
  });
  describe.skip("inner skipped suite", () => {
    it("inner child never runs", () => {
      assert.fail("skipped suite ran");
    });
  });
});

describe("per-test modifiers", () => {
  it.skip("skipped by modifier", () => {
    assert.fail("never runs");
  });
  it.todo("todo by modifier");
  test("runs beside them", () => {
    assert.equal(1, 1);
  });
});
