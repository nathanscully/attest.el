import { test, describe } from "node:test";

describe("alpha suite", () => {
  describe("alpha inner", () => {
    test("alpha deep", () => {});
  });
  test("alpha shallow", () => {});
});
