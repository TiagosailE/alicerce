import "@testing-library/jest-dom/vitest";
import { cleanup, configure } from "@testing-library/react";
import { afterEach } from "vitest";

// A query that waits for a screen gives up after one second by default, which
// the first render of a heavy screen exceeds when the suite runs many workers
// at once. Waiting longer costs nothing when the element is already there; it
// stays well under the test timeout in vite.config.ts.
configure({ asyncUtilTimeout: 4000 });

afterEach(() => {
  cleanup();
});
