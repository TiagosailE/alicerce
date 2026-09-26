import { describe, expect, it } from "vitest";
import {
  formatMoneyCents,
  formatQuantity,
  formatSignedQuantity,
  formatUnitCost,
  parseDecimalInput,
  basisPointsToPercentInput,
  centsToReaisInput,
  formatBasisPoints,
  formatDate,
  dayInZone,
  isZeroDecimal,
  percentToBasisPoints,
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

describe("percentToBasisPoints", () => {
  it.each([
    ["2", "200"],
    ["2,5", "250"],
    ["0,25", "25"],
    ["0", "0"],
    ["100", "10000"],
    ["12,34 %", "1234"],
    ["2%", "200"],
    ["2,50", "250"],
  ])("moves %s percent to %s basis points in the text", (typed, basisPoints) => {
    expect(percentToBasisPoints(typed)).toBe(basisPoints);
  });

  it("rejects more than two places, and what is not a number", () => {
    expect(percentToBasisPoints("0,001")).toBeNull();
    expect(percentToBasisPoints("abc")).toBeNull();
    expect(percentToBasisPoints("")).toBeNull();
    expect(percentToBasisPoints("-2")).toBeNull();
  });
});

describe("formatBasisPoints", () => {
  it.each([
    [200, "2%"],
    [250, "2,5%"],
    [25, "0,25%"],
    [0, "0%"],
    [10000, "100%"],
  ])("shows %i basis points as %s", (basisPoints, shown) => {
    expect(formatBasisPoints(basisPoints).replace(/\s/g, "")).toBe(shown);
  });
});

describe("formatDate", () => {
  it("reads the day from its own parts, never through a time zone", () => {
    expect(formatDate("2026-09-26")).toBe("26/09/2026");
    expect(formatDate("2026-01-01")).toBe("01/01/2026");
  });
});

describe("what the price and discount fields show when an order is edited", () => {
  it.each([
    [3250, "32,50"],
    [5, "0,05"],
    [0, "0,00"],
    [84990, "849,90"],
    [123456789, "1234567,89"],
  ])("shows %i cents as %s reais and reads back the same", (cents, shown) => {
    expect(centsToReaisInput(cents)).toBe(shown);
    expect(reaisToCents(shown)).toBe(String(cents));
  });

  it.each([
    [200, "2"],
    [250, "2,5"],
    [25, "0,25"],
    [0, "0"],
    [10000, "100"],
    [5, "0,05"],
  ])("shows %i basis points as %s percent and reads back the same", (basisPoints, shown) => {
    expect(basisPointsToPercentInput(basisPoints)).toBe(shown);
    expect(percentToBasisPoints(shown)).toBe(String(basisPoints));
  });
});

describe("dayInZone", () => {
  it("reads the day an instant falls on in the zone asked for, not in the machine's", () => {
    // 01:30 UTC is still the evening of the 26th in Bahia (UTC-3).
    const instant = "2026-09-27T01:30:00Z";

    expect(dayInZone(instant, "UTC")).toBe("2026-09-27");
    expect(dayInZone(instant, "America/Bahia")).toBe("2026-09-26");
    expect(dayInZone(instant, "Asia/Tokyo")).toBe("2026-09-27");
  });

  it("accepts a Date and pads the month and the day", () => {
    expect(dayInZone(new Date("2026-01-05T12:00:00Z"), "UTC")).toBe("2026-01-05");
  });
});

describe("isZeroDecimal", () => {
  it.each(["0", "00", "0.0", "0.000"])("reads %s as zero", (value) => {
    expect(isZeroDecimal(value)).toBe(true);
  });

  it.each(["1", "0.001", "10", "0.5", "", "abc"])("does not read %s as zero", (value) => {
    expect(isZeroDecimal(value)).toBe(false);
  });
});
