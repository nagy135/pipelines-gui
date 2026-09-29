# Pipelines for macOS

A native SwiftUI viewer for GitLab CI pipelines and GitHub Actions, rebuilt from `glab-pipelines`.

## Use

Open `dist/Pipelines.app` after building. In **Pipelines → Settings…** (`⌘,`), choose the parent folder containing your projects. The app recursively discovers `.git` directories and worktree `.git` files, including nested repositories. Dependency and build caches are skipped, and symlinks are not followed.

Press **⌘F** anywhere in the app to fuzzy search projects. **⌘K** and clicking the repository name also open the project picker. Type a few letters from a relative folder name: fuzzy search matches subsequences and ranks adjacent letters and word boundaries. Use **↑/↓** and **Enter**, double-click a result, or select it and click **Open**. Projects without an `origin` remote appear in the list but cannot load hosted pipelines. Use **Rescan** after adding or moving projects. The parent folder and last selected repository persist across launches.

The sidebar offers status filters. Select a pipeline to see its branch, commit, source, author, start time, duration, and jobs grouped by stage. Select a job to inspect its logs or resolved code. The GUI preserves previous-run metadata, typical job durations, and the latest five log lines for running or failed jobs.

- **⌘R**: refresh.
- **?**: show all keyboard shortcuts (outside editable text fields). The toolbar’s **Keyboard Shortcuts** button opens the same popup; **Esc** closes it.
- **⌘F**: fuzzy search projects from any view, including logs, code, connection, and Settings.
- Use **Find in logs/code** to search job output. Enter or the arrow buttons move between matches.
- **View Options** in the toolbar: pipeline count, refresh interval, inline logs. The popup stays open while changing options; changes apply immediately. Click **Done**, press **Esc**, or click outside to close it.
- Drag the dividers to resize the sidebar and jobs/logs panels.
- **Wrap**, **Lines**, and **Follow** control the log viewer.
- **Open in Browser** opens a pipeline or job on its provider.

This app focuses on displaying information. It does not start, retry, or cancel pipelines. GitHub publishes downloadable job logs after completion; dynamically generated runs may not have a workflow YAML file. GitLab uses resolved job scripts from the pipeline commit. Errors appear in the relevant pane and can be retried.

## Authentication

Install and authenticate the CLI for each provider you use:

```sh
glab auth login                         # GitLab.com
glab auth login --hostname git.example.com  # Self-hosted GitLab
gh auth login                           # GitHub
```

The app uses the origin remote to select the provider and host. Existing CLI credentials are reused; no tokens are stored by the GUI. Homebrew and Nix CLI locations are included when launching through Finder.

The toolbar's **Repository** button also lets you enter a hosted repository directly. For an `owner/repo` path, select the provider; a full URL allows automatic detection.

## Build and develop

Requires macOS 14+, the Xcode command-line tools (Swift 6+), Go 1.22+, and the relevant provider CLI.

```sh
make test       # Provider/bridge tests and native model/discovery/search tests
make build      # Build an ad-hoc signed .app with the bundled Go helper
make run        # Build and open the app
make demo       # Open a clearly labeled sample-data preview
```

The resulting app can be moved to Applications. Go is required only to build; `gh`/`glab` are still required to fetch data. Distribution to other Macs requires an appropriate build architecture and Apple signing/notarization.

`CI_TUI_LIMIT`, `CI_TUI_REFRESH`, and `CI_TUI_LOG_REFRESH` (and legacy `GLAB_TUI_*` equivalents) supply first-launch defaults. Saved GUI preferences take precedence. Duration history uses the original `~/.local/share/glab-pipelines/job-durations` directory.

## Source layout

`Sources/Pipelines` contains the native app, repository discovery, fuzzy search, and process bridge. `backend` contains the adapted provider data layer, a JSON request interface, and regression tests. See `backend/UPSTREAM.md` for provenance. The original terminal app was left unchanged.
