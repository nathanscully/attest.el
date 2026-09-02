import { describe, it, test } from "node:test";
import assert from "node:assert/strict";

describe("regexp metacharacters", () => {
  it("a (b) [c]? $1.0 * + | ^ \\ end", () => {
    assert.equal(1, 1);
  });
  it("dots.and.slashes/and:colons", () => {
    assert.equal(1, 1);
  });
  it("unicodé and spaces   inside", () => {
    assert.equal(1, 1);
  });
});

describe("duplicates", () => {
  it("same", () => {
    assert.equal(1, 1);
  });
  describe("inner", () => {
    it("same", () => {
      assert.equal(1, 1);
    });
  });
});

describe("other duplicates", () => {
  it("same", () => {
    assert.equal(2, 2);
  });
});

test("same", () => {
  assert.equal(3, 3);
});

describe("level one", () => {
  describe("level two", () => {
    describe("level three", () => {
      describe("level four", () => {
        it("deep passes", () => {
          assert.equal(4, 4);
        });
        it("deep fails", () => {
          assert.equal(4, 5);
        });
      });
    });
  });
});

describe(`template describe`, () => {
  it(`template test`, () => {
    assert.equal(1, 1);
  });
  it('single quoted', () => {
    assert.equal(1, 1);
  });
});

describe("modifiers", () => {
  it.skip("skipped test", () => {
    assert.fail("never runs");
  });
  it.todo("todo test");
  test("async passes", async () => {
    await new Promise((resolve) => setTimeout(resolve, 5));
    assert.equal(1, 1);
  });
  test("async fails", async () => {
    await new Promise((resolve) => setTimeout(resolve, 5));
    assert.equal(1, 2);
  });
});

describe.skip("skipped suite", () => {
  it("never runs", () => {
    assert.fail("skipped suite ran");
  });
});

describe("thrown values", () => {
  it("throws string", () => {
    throw "a plain string";
  });
  it("throws object", () => {
    throw { code: 42 };
  });
  it("throws error with long stack", () => {
    const deep = (n: number): void => {
      if (n === 0) throw new Error("bottom of a deep stack");
      deep(n - 1);
    };
    deep(40);
  });
});
