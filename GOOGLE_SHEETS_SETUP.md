# Google Sheets Timesheet API Setup

This guide covers configuration for the Google Sheets fetch layer used by TAG to ingest timesheet worksheet data. The scope of this integration is authentication and data fetching/parsing preparation only. Grading and rule-based analysis logic are intentionally out of scope.

## Required Environment Variables

Set the credential input:

- `GOOGLE_SHEETS_SERVICE_ACCOUNT_JSON`
  - Full service-account credential JSON as a single string.

## Optional Environment Variables

- `GOOGLE_SHEETS_TIMEOUT_SECONDS` (default: `15`)
  - Timeout used by Google Sheets API requests.

- `GOOGLE_SHEETS_DEFAULT_RANGE` (default: `A:ZZ`)
  - Default A1 range fetched from each selected worksheet tab.

## Service Account Checklist

1. Create a Google Cloud service account with read access to Google Sheets API.
2. Enable Google Sheets API in the same GCP project.
3. Share each target spreadsheet with the service-account email.
4. Provide credentials using one of the required environment variable options.

## Rails Configuration Reference

The initializer [config/initializers/google_sheets_timesheet.rb](config/initializers/google_sheets_timesheet.rb) documents expected Google Sheets environment variables and defaults used by the fetch layer.

## Fetch Service Object

- Service class: `GoogleSheetsTimesheetFetcherService`
- File: `app/services/google_sheets_timesheet_fetcher_service.rb`
- Responsibility: authenticate and fetch spreadsheet tab values only
- Output contract: structured Hash with `ok`, `spreadsheet_id`, `tabs`, `warnings`, and `errors`

This output is intentionally designed for a separate parser service so future teams edit that service file if timesheet structures change.
