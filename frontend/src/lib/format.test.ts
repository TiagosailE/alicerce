import { describe, expect, it } from "vitest";
import {
  formatMoneyCents,
  formatQuantity,
  formatSignedQuantity,
  formatUnitCost,
  parseDecimalInput,
  reaisToCents,
  toDecimalInput,
} from "./format";

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
    ["0.500", "0.500"],
    ["0.001", "0.001"],
    ["10.500", "10500"],
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

describe("money and signed quantities", () => {
  it("formats integer cents as reais", () => {
    expect(formatMoneyCents(850).replace(/\s/g, " ")).toBe("R$ 8,50");
    expect(formatMoneyCents(1_019_880).replace(/\s/g, " ")).toBe("R$ 10.198,80");
    expect(formatMoneyCents(-255).replace(/\s/g, " ")).toBe("-R$ 2,55");
  });

  it("formats an amount past what a float divides exactly, and every place of a unit cost", () => {
    expect(formatMoneyCents(999_999_999_999_999).replace(/\s/g, " ")).toBe(
      "R$ 9.999.999.999.999,99",
    );
    expect(formatUnitCost("84.994567").replace(/\s/g, " ")).toBe("R$ 0,84994567");
  });

  it("formats a fractional-cent unit cost with the places it has", () => {
    expect(formatUnitCost("84.990000").replace(/\s/g, " ")).toBe("R$ 0,8499");
    expect(formatUnitCost("3250.000000").replace(/\s/g, " ")).toBe("R$ 32,50");
  });

  it("always shows the sign of a movement", () => {
    expect(formatSignedQuantity("5.000")).toBe("+5");
    expect(formatSignedQuantity("-3.500")).toBe("-3,5");
    expect(formatSignedQuantity("0.000")).toBe("0");
  });
});

describe("reaisToCents", () => {
  it.each([
    ["32,50", "3250"],
    ["32,5", "3250"],
    ["32", "3200"],
    ["0,8499", "84.99"],
    ["1.234,56", "123456"],
    ["0", "0"],
    ["0,001", "0.1"],
    ["0,05", "5"],
    ["R$ 32,50", "3250"],
    ["  r$0,8499", "84.99"],
  ])("moves %s reais to %s cents in the text", (typed, cents) => {
    expect(reaisToCents(typed)).toBe(cents);
  });

  it("rejects what is not a number", () => {
    expect(reaisToCents("abc")).toBeNull();
    expect(reaisToCents("")).toBeNull();
    expect(reaisToCents("-1")).toBeNull();
  });
});
