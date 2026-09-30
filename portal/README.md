# VIGOR Coach Portal

Static, no-build web app for exploring a client's VIGOR export on a laptop.

Open `index.html` in a browser (or serve the folder), go to **Clients & import**, and drop the `.json`
exported from the app (Settings → Export data). Importing the same client name again merges the new
export into their existing history.

- Pages: Overview, Volume, Weightlifting, Cardio, Stress & recovery, Progress & PRs, Balance & intensity, Calendar, Bodyweight, Programs
- Uses the client's app colours (accent, background, light/dark), carried in the export
- Period filter (30d / 90d / 6m / 1y / all / custom), kg/lb toggle, Print / PDF
- All data stays in the browser (IndexedDB). Nothing is uploaded; Chart.js is bundled in `vendor/`.
