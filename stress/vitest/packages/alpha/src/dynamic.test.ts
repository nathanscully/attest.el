import { describe, it, test, expect } from "vitest";

describe("generated names", () => {
  for (const n of [1, 2, 3]) {
    it(`case ${n}`, () => {
      expect(n).toBe(n);
    });
  }
  test.each([1, 2])("each %i", (n) => {
    expect(n).toBe(n);
  });
  const name = "from a variable";
  it(name, () => {
    expect(1).toBe(1);
  });
});

describe.each(["x", "y"])("group %s", (letter) => {
  it("inside each", () => {
    expect(letter.length).toBe(1);
  });
});
