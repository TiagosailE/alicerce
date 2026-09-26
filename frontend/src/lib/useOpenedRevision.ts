import { useState } from "react";

/** The revision an edit form was opened at (ADR 0015). The form keeps the values
 * it opened with, so a save has to go against the revision those values were
 * read at. The query's latest can be newer, because someone else saved while the
 * form was open (a background refetch brings it in), and sending that one would
 * overwrite their edit with no stale answer.
 *
 * Give it the latest revision the query holds. Call `adopt` with the saved
 * record's revision after a successful save (the form now holds what is stored),
 * or with null after a reload, to read the query's again. */
export function useOpenedRevision(latest: number | undefined) {
  const [opened, setOpened] = useState<number | null>(null);
  if (opened === null && latest !== undefined) setOpened(latest);

  return {
    revision: opened ?? latest,
    adopt: (revision: number | null) => {
      setOpened(revision);
    },
  };
}
