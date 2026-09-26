import { describe, expect, it } from "vitest";
import { formatQuantity, parseDecimalInput, toDecimalInput } from "./format";

describe("parseDecimalInput", () => {
  it.each([
    ["1", "1"],
    ["1000", "1000"],
    ["2,5", "2.5"],
    ["0,000001", "0.000001"],
    ["1.000", "1000"],
    ["1.234.567,89", "1234567.89"],
    ["2.5", "2.5"],
    ["1000.5", "1000.5"],
    ["  12  ", "12"],
    ["1.0000004", "1.0000004"],
  ])("reads %s as %s", (typed, expected) => {
    expect(parseDecimalInput(typed)).toBe(expected);
  });

  it.each(["", "abc", "1,2,3", "1..000", "-1", ",5", "1e3", "1.000,"])("rejects %j", (typed) => {
    expect(parseDecimalInput(typed)).toBeNull();
  });

  it("reads back what the list displays, so the two never disagree by a thousand", () => {
    for (const apiValue of ["1000.000000", "1.500000", "0.250000", "1234567.500000"]) {
      expect(parseDecimalInput(formatQuantity(apiValue))).toBe(
        toDecimalInput(apiValue).replace(",", "."),
      );
    }
  });
});

describe("toDecimalInput", () => {
  it.each([
    ["1000.000000", "1000"],
    ["0.500000", "0,5"],
    ["1.000001", "1,000001"],
    ["50.000000", "50"],
    ["7", "7"],
  ])("shows %s as %s", (apiValue, expected) => {
    expect(toDecimalInput(apiValue)).toBe(expected);
  });
});
