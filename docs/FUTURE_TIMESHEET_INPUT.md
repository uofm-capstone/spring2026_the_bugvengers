# Future Timesheet Input Decision

## Summary
We decided not to continue with Google Sheets uploads for timesheet collection. The team and sponsor (professor) agreed that a native in-app timesheet entry flow would be better long term. This work is out of scope for the current semester and should be handled by future teams.

## Why We Stopped Sheets Uploads
- Uploading a timesheet introduces brittle dependencies (external API credentials, file access inside Docker, and network errors).
- The UI experience is disruptive; updates should be immediate and contained within the app.
- A native workflow keeps data consistent, reduces name-matching issues, and avoids external permissions/sharing steps.

## Recommended Direction for Future Teams
- Build a dedicated timesheet page or tab where students log hours directly in the app.
- Store entries per student and sprint with a simple schema (date, hours, activity).
- Use the same hours-only rule logic already implemented in TimesheetAnalysisService.
- Provide per-sprint progress bars on the status page based on stored entries (no external fetch).

## Out of Scope (Current Semester)
- New database tables, CRUD UI, or student-facing input forms.
- Migration from Google Sheets or automatic imports.

## Notes
This decision was made with the sponsor during Spring 2026 to keep scope focused and avoid fragile integrations. Future teams can revisit Google Sheets if required, but the preferred path is native entry within the application.
