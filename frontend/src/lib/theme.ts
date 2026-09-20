import { useCallback, useState } from "react";

export type Theme = "light" | "dark";

const STORAGE_KEY = "alicerce-theme";

function readTheme(): Theme {
  return document.documentElement.dataset.theme === "dark" ? "dark" : "light";
}

function applyTheme(theme: Theme) {
  document.documentElement.dataset.theme = theme;
  try {
    localStorage.setItem(STORAGE_KEY, theme);
  } catch {
    // Private browsing or blocked storage: the choice just does not persist.
  }
}

/** Mirrors the choice public/theme-init.js already applied before paint. */
export function useTheme() {
  const [theme, setTheme] = useState<Theme>(readTheme);

  const toggle = useCallback(() => {
    setTheme((current) => {
      const next = current === "dark" ? "light" : "dark";
      applyTheme(next);
      return next;
    });
  }, []);

  return { theme, toggle };
}
