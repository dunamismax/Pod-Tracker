import { describe, expect, it } from "vitest";

import { formatInTimeZone } from "./timezone";

describe("formatInTimeZone", () => {
  it("renders an instant in the requested timezone", () => {
    const formatted = formatInTimeZone(
      "2026-07-11T02:00:00.000Z",
      "America/Phoenix",
    );

    expect(formatted).toContain("2026");
    expect(formatted).toMatch(/7:00/);
  });
});
