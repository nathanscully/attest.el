import { describe, it, test, expect } from "vitest";

describe("regexp metacharacters", () => {
  it("a (b) [c]? $1.0 * + | ^ \\ end", () => {
    expect(1).toBe(1);
  });
  it("dots.and.slashes/and:colons", () => {
    expect(1).toBe(1);
  });
  it("unicodé and spaces   inside", () => {
    expect(1).toBe(1);
  });
});

describe("duplicates", () => {
  it("same", () => {
    expect(1).toBe(1);
  });
  describe("inner", () => {
    it("same", () => {
      expect(1).toBe(1);
    });
  });
});

describe("other duplicates", () => {
  it("same", () => {
    expect(2).toBe(2);
  });
});

test("same", () => {
  expect(3).toBe(3);
});

describe("level one", () => {
  describe("level two", () => {
    describe("level three", () => {
      describe("level four", () => {
        it("deep passes", () => {
          expect(4).toBe(4);
        });
        it("deep fails", () => {
          expect(4).toBe(5);
        });
      });
    });
  });
});

describe(`template describe`, () => {
  it(`template test`, () => {
    expect(1).toBe(1);
  });
  it('single quoted', () => {
    expect(1).toBe(1);
  });
});

describe("modifiers", () => {
  it.skip("skipped test", () => {
    expect.fail("never runs");
  });
  it.todo("todo test");
  test("async passes", async () => {
    await new Promise((resolve) => setTimeout(resolve, 5));
    expect(1).toBe(1);
  });
  test("async fails", async () => {
    await new Promise((resolve) => setTimeout(resolve, 5));
    expect(1).toBe(2);
  });
});

describe.skip("skipped suite", () => {
  it("never runs", () => {
    expect.fail("skipped suite ran");
  });
});

describe("thrown values", () => {
  it("throws string", () => {
    throw "a plain string";
  });
  it("throws error with long stack", () => {
    const deep = (n: number): void => {
      if (n === 0) throw new Error("bottom of a deep stack");
      deep(n - 1);
    };
    deep(40);
  });
});
