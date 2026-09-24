# Security and source-media policy

Video to Live Turbo is designed around a strict non-destructive media workflow.

- Source footage is read-only.
- The app does not delete source footage.
- The app does not move source footage.
- The app does not overwrite source footage.
- Generated Live Photo files are written to the configured output directory.
- Temporary AirDrop .pvt bundles are written only to the app cache and may be cleaned after 24 hours.

If you find behavior that violates these guarantees, please report it as a bug.
