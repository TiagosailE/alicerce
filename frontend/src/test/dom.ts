/** The nth element of what a query returned, failing the test when it is not
 * there instead of leaving the index unchecked. */
export function nth<T>(items: T[], index: number): T {
  const item = items[index];
  if (item === undefined) throw new Error(`nothing at position ${String(index)}`);
  return item;
}

/** A table cell's text with every kind of space folded to a plain one, so a
 * currency written with a non-breaking space compares to what a person reads. */
export function cellText(cells: HTMLElement[], index: number): string {
  return nth(cells, index).textContent.replace(/\s/g, " ");
}
