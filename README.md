# OneLife in the browser

Single-player build of One Hour One Life that runs as a web page.
The server is built into the page (in-memory network), and your parents are NPCs.

1. Create a new empty repo on GitHub and upload everything in this folder.
2. Settings → Pages → Source: **GitHub Actions**.
3. Actions → "Build browser version" → Run workflow.
4. When it is green, open the Pages link on your phone.

If the build fails, open the run, download the `build-logs` artifact (or read the
"Build" step) and send the error text.
