// The demo's agents: herdr-github's demo org (Halcyon) has its pull requests;
// these are the made-up agents on them, so the PR screen's agents can be
// shown and screenshotted without a real one.

export function demoAgents(key, now) {
  switch (key) {
    case "github.com/halcyon/notes-app#482":
      return [
        { name: "Offline sync conflicts", status: "idle", machine: "build-1", part: "opened it", since: now - 20 * 60000 },
        { name: "Review the three-way merge", status: "working", machine: null, part: "on its branch", since: now - 4 * 60000 },
      ];
    case "github.com/halcyon/notes-app#476":
      return [{ name: "CRDT spike", status: null, machine: "build-1", part: "opened it", resume: true, since: now - 70 * 3600000 }];
  }
  return [];
}

// The demo's own repo, as if the space it was opened from were a checkout.
export const DEMO_REPO = { host: "github.com", owner: "halcyon", name: "notes-app" };
