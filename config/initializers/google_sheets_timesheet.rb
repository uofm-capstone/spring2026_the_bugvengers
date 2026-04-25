# frozen_string_literal: true

# Google Sheets Timesheet integration configuration notes.
#
# Why this file exists:
# - Keeps all expected environment variable names in one documented location.
# - Makes setup expectations visible to future teams during app boot.
# - Avoids hardcoding secrets in source control.
#
# Required environment variables for service-account auth:
# - GOOGLE_SHEETS_SERVICE_ACCOUNT_JSON
#   Full JSON credential content as a single string.
#   Useful for cloud environments that inject secret values directly.
#
# OR
#
# - GOOGLE_SHEETS_SERVICE_ACCOUNT_JSON_PATH
#   Absolute path to a service-account JSON file on disk.
#   Useful for local development with a mounted credential file.
#
# Optional environment variables:
# - GOOGLE_SHEETS_TIMEOUT_SECONDS
#   Request timeout for Google API calls. Default is 15 seconds.
#
# - GOOGLE_SHEETS_DEFAULT_RANGE
#   A1 notation range used when callers do not pass a range.
#   Default is A:ZZ to cover wide timesheet exports.
GOOGLE_SHEETS_TIMESHEET_CONFIG = {
  timeout_seconds: ENV.fetch("GOOGLE_SHEETS_TIMEOUT_SECONDS", "15").to_i,
  default_range: ENV.fetch("GOOGLE_SHEETS_DEFAULT_RANGE", "A:ZZ")
}.freeze
