#!/bin/bash
# re.Brew — Scan installed macOS apps and CLI tools, classify install sources,
# and check Homebrew availability to support Brewfile migration.
# https://github.com/tmdbah/redotbrew

set -u
shopt -s nullglob

# --- Defaults ---
OUTPUT_DIR="$HOME/Downloads"
VERSION_TIMEOUT_SECONDS=1
PROGRESS_EVERY=25
EXTRA_CMD_DIRS=()
MAX_VERSION_JOBS=8

# --- Parse arguments ---
show_help() {
    cat <<EOF
re.Brew — Installed Apps Audit
Usage: $(basename "$0") [OPTIONS]

Scan installed macOS applications and CLI tools. Generates a CSV and an
interactive HTML dashboard showing install source, version, and Homebrew
availability for each item.

Options:
  --output-dir DIR       Output directory for reports (default: ~/Downloads)
  --version-timeout SECS Timeout for version detection per tool (default: 1)
  --extra-paths DIRS     Additional colon-separated directories to scan for CLI tools
                         (e.g. ~/.local/bin:/opt/local/bin)
  --help, -h             Show this help message

Outputs:
  <output-dir>/installed_apps_audit.csv
  <output-dir>/installed_apps_audit.html

Prerequisites:
  Homebrew    Required for availability checking (runs without it, but limited)
  mas         Optional; enables Mac App Store app detection
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            [[ -z "${2:-}" ]] && { echo "Error: --output-dir requires a value" >&2; exit 1; }
            OUTPUT_DIR="$2"; shift 2 ;;
        --version-timeout)
            [[ -z "${2:-}" ]] && { echo "Error: --version-timeout requires a value" >&2; exit 1; }
            VERSION_TIMEOUT_SECONDS="$2"; shift 2 ;;
        --extra-paths)
            [[ -z "${2:-}" ]] && { echo "Error: --extra-paths requires a value" >&2; exit 1; }
            IFS=: read -ra _extra <<< "$2"
            EXTRA_CMD_DIRS+=("${_extra[@]}")
            shift 2 ;;
        -h|--help) show_help ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Validate output directory ---
if [[ ! -d "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR" 2>/dev/null || { echo "Error: Cannot create output directory: $OUTPUT_DIR" >&2; exit 1; }
fi

OUTPUT_CSV="$OUTPUT_DIR/installed_apps_audit.csv"
OUTPUT_HTML="$OUTPUT_DIR/installed_apps_audit.html"
echo "App/Tool Name,Install Source,Path/Command,Version,Homebrew Availability,Confidence,Install Evidence" > "$OUTPUT_CSV"

rows_json=""

csv_escape() {
    local s="${1:-}"
    s=${s//\"/\"\"}
    printf '"%s"' "$s"
}

write_row() {
    printf '%s,%s,%s,%s,%s,%s,%s\n' \
        "$(csv_escape "$1")" \
        "$(csv_escape "$2")" \
        "$(csv_escape "$3")" \
        "$(csv_escape "$4")" \
        "$(csv_escape "$5")" \
        "$(csv_escape "$6")" \
        "$(csv_escape "$7")" >> "$OUTPUT_CSV"
}

json_escape() {
        local s="${1:-}"
        s=${s//\\/\\\\}
        s=${s//\"/\\\"}
        s=${s//$'\n'/\\n}
        s=${s//$'\r'/\\r}
        s=${s//$'\t'/\\t}
        printf '%s' "$s"
}

append_json_row() {
        local name="$1"
        local source="$2"
        local path_cmd="$3"
        local version="$4"
        local brew_avail="$5"
        local confidence="$6"
    local install_evidence="$7"
    local item_type="$8"
        local row

    row="{\"name\":\"$(json_escape "$name")\",\"source\":\"$(json_escape "$source")\",\"path\":\"$(json_escape "$path_cmd")\",\"version\":\"$(json_escape "$version")\",\"brewAvailability\":\"$(json_escape "$brew_avail")\",\"confidence\":\"$(json_escape "$confidence")\",\"installEvidence\":\"$(json_escape "$install_evidence")\",\"itemType\":\"$(json_escape "$item_type")\"}"

        if [[ -n "$rows_json" ]]; then
            rows_json+=",$row"
        else
                rows_json="$row"
        fi
}

    log_progress() {
        local stage="$1"
        local processed="$2"
        local total="$3"
        local start_ts="$4"
        local now_ts
        local elapsed
        local eta
        now_ts=$(date +%s)
        elapsed=$((now_ts - start_ts))
        if [[ "$processed" -gt 0 && "$total" -gt 0 && "$processed" -lt "$total" ]]; then
            eta=$((elapsed * (total - processed) / processed))
        else
            eta=0
        fi
        if [[ "$total" -gt 0 ]]; then
            printf '[%s] %s/%s processed | Elapsed: %ds | ETA: %ds\n' "$stage" "$processed" "$total" "$elapsed" "$eta"
        else
            printf '[%s] %s processed | Elapsed: %ds\n' "$stage" "$processed" "$elapsed"
        fi
    }

    run_cmd_first_line_with_timeout() {
        local timeout_secs="$1"
        shift
        local tmp
        local pid
        local elapsed=0
        local out=""

        tmp="$(mktemp)"
        ("$@" </dev/null >"$tmp" 2>/dev/null) &
        pid=$!

        while kill -0 "$pid" 2>/dev/null; do
            if (( elapsed >= timeout_secs * 10 )); then
                kill -TERM "$pid" 2>/dev/null || true
                sleep 0.1
                kill -KILL "$pid" 2>/dev/null || true
                wait "$pid" 2>/dev/null || true
                rm -f "$tmp"
                return 124
            fi
            sleep 0.1
            elapsed=$((elapsed + 1))
        done

        wait "$pid" 2>/dev/null || true
        out="$(LC_ALL=C head -n 1 "$tmp" | LC_ALL=C tr -cd '\11\12\15\40-\176' | LC_ALL=C tr -d '\r\n')"
        rm -f "$tmp"
        printf '%s' "$out"
    }

normalize_token() {
        LC_ALL=C printf '%s' "$1" \
            | LC_ALL=C tr '[:upper:]' '[:lower:]' \
            | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

write_html_dashboard() {
        {
                cat <<'HTML_HEAD'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>re.Brew Dashboard</title>
    <style>
        :root {
            color-scheme: light dark;
            --bg: #0b1020;
            --panel: #121a2d;
            --panel-2: #1a2540;
            --text: #e6edf7;
            --muted: #9fb0d0;
            --accent: #5aa8ff;
            --ok: #37b26c;
            --warn: #f0b429;
            --bad: #e45555;
            --border: #2a3658;
        }
        * { box-sizing: border-box; }
        body {
            margin: 0;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background: var(--bg);
            color: var(--text);
        }
        .wrap {
            max-width: 1200px;
            margin: 0 auto;
            padding: 24px;
        }
        h1 {
            margin: 0 0 6px;
            font-size: 28px;
        }
        .sub {
            color: var(--muted);
            margin-bottom: 20px;
        }
        .grid {
            display: grid;
            gap: 12px;
            grid-template-columns: repeat(4, minmax(180px, 1fr));
            margin-bottom: 20px;
        }
        .card {
            background: var(--panel);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 14px;
        }
        .metric-label {
            font-size: 12px;
            color: var(--muted);
            margin-bottom: 6px;
            text-transform: uppercase;
            letter-spacing: 0.04em;
        }
        .metric-value {
            font-size: 28px;
            font-weight: 700;
            line-height: 1.1;
        }
        .section-title {
            margin: 0 0 10px;
            font-size: 18px;
        }
        .charts {
            display: grid;
            gap: 12px;
            grid-template-columns: repeat(2, minmax(300px, 1fr));
            margin-bottom: 20px;
        }
        .bar-row {
            margin-bottom: 10px;
        }
        .bar-label {
            display: flex;
            justify-content: space-between;
            font-size: 13px;
            margin-bottom: 5px;
            color: var(--muted);
        }
        .bar-track {
            height: 12px;
            border-radius: 999px;
            background: var(--panel-2);
            overflow: hidden;
            border: 1px solid var(--border);
        }
        .bar-fill {
            height: 100%;
            background: linear-gradient(90deg, var(--accent), #9bd0ff);
        }
        .legend-list {
            margin: 0;
            padding-left: 18px;
            color: var(--muted);
            line-height: 1.5;
            font-size: 14px;
        }
        .filters {
            display: flex;
            gap: 10px;
            margin-bottom: 10px;
            flex-wrap: wrap;
        }
        input, select {
            background: var(--panel-2);
            color: var(--text);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 8px 10px;
            font-size: 14px;
        }
        input { min-width: 240px; }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
            overflow: hidden;
            border-radius: 10px;
            border: 1px solid var(--border);
        }
        th, td {
            border-bottom: 1px solid var(--border);
            padding: 8px 10px;
            text-align: left;
            vertical-align: top;
        }
        th {
            background: var(--panel-2);
            color: var(--muted);
            position: sticky;
            top: 0;
            z-index: 1;
        }
        tr:hover td {
            background: rgba(90, 168, 255, 0.08);
        }
        .badge {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 999px;
            font-size: 12px;
            border: 1px solid var(--border);
            background: var(--panel-2);
            color: var(--text);
        }
        .insights {
            display: grid;
            gap: 12px;
            grid-template-columns: repeat(3, minmax(220px, 1fr));
            margin-bottom: 20px;
        }
        .insight-title { font-size: 14px; color: var(--muted); margin-bottom: 4px; }
        .insight-value { font-size: 24px; font-weight: 700; margin-bottom: 4px; }
        .insight-desc { font-size: 13px; color: var(--muted); line-height: 1.4; }
        .row-count { margin-top: 8px; color: var(--muted); font-size: 13px; }

        @media (max-width: 900px) {
            .grid, .charts, .insights { grid-template-columns: 1fr; }
            input { min-width: 100%; }
        }
    </style>
</head>
<body>
    <div class="wrap">
        <h1>re.Brew Dashboard</h1>
        <div class="sub">Your dotfiles, re-brewed. Scan data includes source detection, Homebrew availability, confidence, and migration insights.</div>

        <div class="grid" id="kpis"></div>

        <div class="insights" id="insights"></div>

        <div class="charts">
            <div class="card">
                <h2 class="section-title">Install Source Distribution</h2>
                <div id="sourceChart"></div>
            </div>
            <div class="card">
                <h2 class="section-title">Confidence Distribution</h2>
                <div id="confidenceChart"></div>
            </div>
        </div>

        <div class="card" style="margin-bottom: 20px;">
            <h2 class="section-title">Key / Definitions</h2>
            <ul class="legend-list">
                <li><strong>Manual but Homebrew available</strong>: Item appears manually installed but can be managed by Homebrew.</li>
                <li><strong>Installed via Homebrew</strong>: Item directly matched as Homebrew Formula or Cask.</li>
                <li><strong>Manual and not available in Homebrew</strong>: Item appears manually installed and no Homebrew match was found.</li>
                <li><strong>Confidence</strong>: High = direct list match, Medium = inferred availability, Low = no direct mapping found.</li>
            </ul>
        </div>

        <div class="card">
            <h2 class="section-title">Detailed Inventory</h2>
            <div class="filters">
                <input id="search" type="search" placeholder="Search name, source, path, version..." />
                <select id="categoryFilter">
                    <option value="all">All insight categories</option>
                    <option value="manual_brew_available">Manual but Homebrew available</option>
                    <option value="installed_via_brew">Installed via Homebrew</option>
                    <option value="manual_not_brew_available">Manual and not available in Homebrew</option>
                    <option value="other">Other</option>
                </select>
            </div>
            <div style="overflow:auto; max-height: 460px;">
                <table>
                    <thead>
                        <tr>
                            <th>Name</th>
                            <th>Type</th>
                            <th>Install Source</th>
                            <th>Path / Command</th>
                            <th>Version</th>
                            <th>Homebrew Availability</th>
                            <th>Confidence</th>
                            <th>Install Evidence</th>
                            <th>Insight Category</th>
                        </tr>
                    </thead>
                    <tbody id="tableBody"></tbody>
                </table>
            </div>
            <div class="row-count" id="rowCount"></div>
        </div>
    </div>

    <script>
        const rows = [
HTML_HEAD
                printf '%s\n' "$rows_json"
                cat <<'HTML_TAIL'
        ];

        function classify(row) {
            const source = row.source || "";
            const brew = row.brewAvailability || "";
            if (source === "Homebrew Cask" || source === "Homebrew Formula") return "installed_via_brew";
            if (source === "Manual / Other" && /^Available as (Cask|Formula): /.test(brew)) return "manual_brew_available";
            if (source === "Manual / Other" && brew === "Not available in Homebrew") return "manual_not_brew_available";
            return "other";
        }

        function humanCategory(category) {
            if (category === "manual_brew_available") return "Manual but Homebrew available";
            if (category === "installed_via_brew") return "Installed via Homebrew";
            if (category === "manual_not_brew_available") return "Manual and not available in Homebrew";
            return "Other";
        }

        function countBy(items, keyFn) {
            const map = new Map();
            items.forEach(item => {
                const key = keyFn(item);
                map.set(key, (map.get(key) || 0) + 1);
            });
            return map;
        }

        function pct(value, total) {
            if (!total) return "0.0%";
            return ((value / total) * 100).toFixed(1) + "%";
        }

        function renderBarChart(containerId, map, total) {
            const container = document.getElementById(containerId);
            container.innerHTML = "";
            const entries = Array.from(map.entries()).sort((a, b) => b[1] - a[1]);
            entries.forEach(([label, value]) => {
                const row = document.createElement("div");
                row.className = "bar-row";
                row.innerHTML = `
                    <div class="bar-label"><span>${label}</span><span>${value} (${pct(value, total)})</span></div>
                    <div class="bar-track"><div class="bar-fill" style="width:${Math.max(3, (value / Math.max(1, total)) * 100)}%"></div></div>
                `;
                container.appendChild(row);
            });
        }

        function renderKPIs(allRows) {
            const total = allRows.length;
            const appCount = allRows.filter(r => r.itemType === "App").length;
            const cmdCount = allRows.filter(r => r.itemType === "Command").length;
            const manualBrewAvail = allRows.filter(r => classify(r) === "manual_brew_available").length;
            const viaBrew = allRows.filter(r => classify(r) === "installed_via_brew").length;

            const cards = [
                ["Total Items", total],
                ["Apps", appCount],
                ["Commands", cmdCount],
                ["Manual + Brew Available", manualBrewAvail],
                ["Installed via Homebrew", viaBrew]
            ];

            const kpis = document.getElementById("kpis");
            kpis.innerHTML = cards.map(([label, value]) => `
                <div class="card">
                    <div class="metric-label">${label}</div>
                    <div class="metric-value">${value}</div>
                </div>
            `).join("");
        }

        function renderInsights(allRows) {
            const total = allRows.length;
            const manualBrew = allRows.filter(r => classify(r) === "manual_brew_available").length;
            const viaBrew = allRows.filter(r => classify(r) === "installed_via_brew").length;
            const manualNotBrew = allRows.filter(r => classify(r) === "manual_not_brew_available").length;

            const insights = [
                {
                    title: "Manual but Homebrew available",
                    value: `${manualBrew} (${pct(manualBrew, total)})`,
                    desc: "These are strong candidates to migrate into Homebrew for easier upgrades and reproducible setup."
                },
                {
                    title: "Installed via Homebrew",
                    value: `${viaBrew} (${pct(viaBrew, total)})`,
                    desc: "Already centrally managed through Homebrew. These are typically easiest to keep updated."
                },
                {
                    title: "Manual and not available in Homebrew",
                    value: `${manualNotBrew} (${pct(manualNotBrew, total)})`,
                    desc: "Likely requires manual install/updates or an alternative package manager."
                }
            ];

            const container = document.getElementById("insights");
            container.innerHTML = insights.map(i => `
                <div class="card">
                    <div class="insight-title">${i.title}</div>
                    <div class="insight-value">${i.value}</div>
                    <div class="insight-desc">${i.desc}</div>
                </div>
            `).join("");
        }

        function renderTable(allRows) {
            const search = document.getElementById("search");
            const filter = document.getElementById("categoryFilter");
            const body = document.getElementById("tableBody");
            const rowCount = document.getElementById("rowCount");

            function draw() {
                const q = (search.value || "").toLowerCase().trim();
                const category = filter.value;

                const filtered = allRows.filter(r => {
                    const cat = classify(r);
                    const matchesCategory = category === "all" ? true : cat === category;
                    const haystack = [r.name, r.itemType, r.source, r.path, r.version, r.brewAvailability, r.confidence, r.installEvidence, humanCategory(cat)]
                        .join(" ")
                        .toLowerCase();
                    const matchesSearch = q ? haystack.includes(q) : true;
                    return matchesCategory && matchesSearch;
                });

                body.innerHTML = filtered.map(r => {
                    const cat = classify(r);
                    return `
                        <tr>
                            <td>${r.name || ""}</td>
                            <td><span class="badge">${r.itemType || ""}</span></td>
                            <td>${r.source || ""}</td>
                            <td>${r.path || ""}</td>
                            <td>${r.version || ""}</td>
                            <td>${r.brewAvailability || ""}</td>
                            <td>${r.confidence || ""}</td>
                            <td>${r.installEvidence || ""}</td>
                            <td>${humanCategory(cat)}</td>
                        </tr>
                    `;
                }).join("");

                rowCount.textContent = `${filtered.length} of ${allRows.length} rows shown`;
            }

            search.addEventListener("input", draw);
            filter.addEventListener("change", draw);
            draw();
        }

        function main() {
            const sourceCounts = countBy(rows, r => r.source || "Unknown");
            const confidenceCounts = countBy(rows, r => r.confidence || "Unknown");

            renderKPIs(rows);
            renderInsights(rows);
            renderBarChart("sourceChart", sourceCounts, rows.length);
            renderBarChart("confidenceChart", confidenceCounts, rows.length);
            renderTable(rows);
        }

        main();
    </script>
</body>
</html>
HTML_TAIL
        } > "$OUTPUT_HTML"
}

get_app_version() {
    local app="$1"
    local plist="$app/Contents/Info.plist"
    local v=""
    if [[ -f "$plist" ]]; then
        v=$(defaults read "$plist" CFBundleShortVersionString 2>/dev/null || true)
        [[ -z "$v" ]] && v=$(defaults read "$plist" CFBundleVersion 2>/dev/null || true)
    fi
    [[ -z "$v" ]] && v=$(mdls -raw -name kMDItemVersion "$app" 2>/dev/null || true)
    [[ "$v" == "(null)" ]] && v=""
    printf '%s' "$v"
}

get_cmd_version() {
    local cmd="$1"
    local v=""
    for flag in --version -V; do
        v="$(run_cmd_first_line_with_timeout "$VERSION_TIMEOUT_SECONDS" "$cmd" "$flag" || true)"
        [[ -n "$v" ]] && break
    done
    printf '%s' "$v"
}

get_brew_availability() {
    local token="$1"

    if [[ $has_brew -eq 0 ]]; then
        printf '%s' "Homebrew not installed"
        return
    fi

    if [[ $has_brew_catalog -eq 1 ]]; then
        if printf '%s\n' "$brew_all_casks" | grep -Fqx "$token"; then
            printf '%s' "Available as Cask: $token"
            return
        fi
        if printf '%s\n' "$brew_all_formulae" | grep -Fqx "$token"; then
            printf '%s' "Available as Formula: $token"
            return
        fi
        printf '%s' "Not available in Homebrew"
        return
    fi

    if brew info --cask "$token" >/dev/null 2>&1; then
        printf '%s' "Available as Cask: $token"
    elif brew info "$token" >/dev/null 2>&1; then
        printf '%s' "Available as Formula: $token"
    else
        printf '%s' "Not available in Homebrew"
    fi
}

is_installed_cask_alias_for_token() {
    local token="$1"
    [[ -n "$token" ]] || return 1
    [[ $has_brew -eq 1 ]] || return 1
    printf '%s\n' "$brew_casks" | LC_ALL=C grep -Eiq "^${token}(-|$)"
}

has_brew=0
has_brew_catalog=0
if command -v brew >/dev/null 2>&1; then
    has_brew=1
    brew_casks="$(brew list --cask 2>/dev/null || true)"
    brew_formulae="$(brew list --formula 2>/dev/null || true)"
    brew_all_casks="$(brew casks 2>/dev/null || true)"
    brew_all_formulae="$(brew formulae 2>/dev/null || true)"
    if [[ -n "$brew_all_casks" || -n "$brew_all_formulae" ]]; then
        has_brew_catalog=1
    fi
else
    brew_casks=""
    brew_formulae=""
    brew_all_casks=""
    brew_all_formulae=""
fi

if command -v mas >/dev/null 2>&1; then
    mas_apps="$(mas list 2>/dev/null | sed -E 's/^[0-9]+[[:space:]]+//; s/[[:space:]]+\([^)]*\)$//' || true)"
else
    mas_apps=""
fi

# --- Startup summary ---
echo "=== re.Brew — Installed Apps Audit ==="
echo "  Output dir:        $OUTPUT_DIR"
echo "  Version timeout:   ${VERSION_TIMEOUT_SECONDS}s"
printf '  Homebrew:          %s\n' "$(if [[ $has_brew -eq 1 ]]; then echo "found (catalog: $(if [[ $has_brew_catalog -eq 1 ]]; then echo "loaded"; else echo "unavailable"; fi))"; else echo "NOT FOUND — availability data will be limited"; fi)"
printf '  mas (App Store):   %s\n' "$(if [[ -n "$mas_apps" ]]; then echo "found"; elif command -v mas >/dev/null 2>&1; then echo "installed but no apps listed"; else echo "not installed (Mac App Store detection skipped)"; fi)"
cmd_scan_dirs=("/usr/local/bin" "/opt/homebrew/bin")
for _d in "${EXTRA_CMD_DIRS[@]}"; do
    [[ -d "$_d" ]] && cmd_scan_dirs+=("$_d")
done
printf '  Command scan dirs: %s\n' "${cmd_scan_dirs[*]}"
echo ""

app_dirs=(/Applications "$HOME/Applications")
app_total=0
app_processed=0
app_start_ts=$(date +%s)

for dir in "${app_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    for app in "$dir"/*.app; do
        [[ -e "$app" ]] || continue
        app_total=$((app_total + 1))
    done
done

echo "[Start] Scanning apps and commands"
log_progress "Apps" 0 "$app_total" "$app_start_ts"

for dir in "${app_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    for app in "$dir"/*.app; do
        app_name="$(basename "$app" .app)"
        app_token="$(normalize_token "$app_name")"
        version="$(get_app_version "$app")"
        source="Manual / Other"
        brew_avail=""
        confidence="Low"
        install_evidence="none"

        if [[ $has_brew -eq 1 ]] && printf '%s\n' "$brew_casks" | grep -Fqx "$app_token"; then
            source="Homebrew Cask"
            confidence="High"
            install_evidence="exact-cask-match"
        elif [[ $has_brew -eq 1 ]] && printf '%s\n' "$brew_formulae" | grep -Fqx "$app_token"; then
            source="Homebrew Formula"
            confidence="High"
            install_evidence="exact-formula-match"
        elif printf '%s\n' "$mas_apps" | grep -Fqx "$app_name"; then
            source="Mac App Store"
            confidence="High"
            install_evidence="mas-name-match"
        fi

        if [[ "$source" == "Manual / Other" ]]; then
            brew_avail="$(get_brew_availability "$app_token")"
            if [[ "$brew_avail" == Available\ as\ Cask:* || "$brew_avail" == Available\ as\ Formula:* ]]; then
                confidence="Medium"
                install_evidence="inferred-availability"
            else
                confidence="Low"
                if [[ "$brew_avail" == "Homebrew not installed" ]]; then
                    install_evidence="brew-missing"
                else
                    install_evidence="not-found"
                fi
            fi
        fi

        write_row "$app_name" "$source" "$app" "$version" "$brew_avail" "$confidence" "$install_evidence"
        append_json_row "$app_name" "$source" "$app" "$version" "$brew_avail" "$confidence" "$install_evidence" "App"

        app_processed=$((app_processed + 1))
        if (( app_processed % PROGRESS_EVERY == 0 || app_processed == app_total )); then
            log_progress "Apps" "$app_processed" "$app_total" "$app_start_ts"
        fi
    done
done

brew_bin_dirs=("${cmd_scan_dirs[@]}")
seen_cmds=""
cmd_total=0
cmd_processed=0
count_seen_cmds=""
cmd_start_ts=$(date +%s)

for bin_dir in "${brew_bin_dirs[@]}"; do
    [[ -d "$bin_dir" ]] || continue
    for cmd in "$bin_dir"/*; do
        [[ -x "$cmd" ]] || continue
        cmd_name="$(basename "$cmd")"
        cmd_token="$(normalize_token "$cmd_name")"
        if printf '%s\n' "$count_seen_cmds" | grep -Fqx "$cmd_name"; then
            continue
        fi
        count_seen_cmds="${count_seen_cmds}"$'\n'"$cmd_name"
        cmd_total=$((cmd_total + 1))
    done
done

# --- Pre-compute command versions in parallel ---
VERSION_CACHE_DIR="$(mktemp -d)"
trap 'rm -rf "$VERSION_CACHE_DIR"' EXIT

_precomp_seen=""
_batch=0
for bin_dir in "${brew_bin_dirs[@]}"; do
    [[ -d "$bin_dir" ]] || continue
    for cmd in "$bin_dir"/*; do
        [[ -x "$cmd" ]] || continue
        cmd_name="$(basename "$cmd")"
        if printf '%s\n' "$_precomp_seen" | grep -Fqx "$cmd_name"; then
            continue
        fi
        _precomp_seen="${_precomp_seen}"$'\n'"$cmd_name"
        (
            v=""
            for flag in --version -V; do
                v="$(run_cmd_first_line_with_timeout "$VERSION_TIMEOUT_SECONDS" "$cmd" "$flag" || true)"
                [[ -n "$v" ]] && break
            done
            printf '%s' "$v" > "$VERSION_CACHE_DIR/$cmd_name"
        ) &
        _batch=$((_batch + 1))
        if (( _batch >= MAX_VERSION_JOBS )); then
            wait
            _batch=0
        fi
    done
done
wait
echo "[Versions] Pre-computed $cmd_total command versions (parallel=$MAX_VERSION_JOBS)"

log_progress "Commands" 0 "$cmd_total" "$cmd_start_ts"

for bin_dir in "${brew_bin_dirs[@]}"; do
    [[ -d "$bin_dir" ]] || continue
    for cmd in "$bin_dir"/*; do
        [[ -x "$cmd" ]] || continue
        cmd_name="$(basename "$cmd")"
        cmd_token="$(normalize_token "$cmd_name")"

        if printf '%s\n' "$seen_cmds" | grep -Fqx "$cmd_name"; then
            continue
        fi
        seen_cmds="${seen_cmds}"$'\n'"$cmd_name"

        version=""
        [[ -f "$VERSION_CACHE_DIR/$cmd_name" ]] && version="$(cat "$VERSION_CACHE_DIR/$cmd_name")"
        source="Manual / Other"
        brew_avail=""
        confidence="Low"
        install_evidence="none"

        if [[ $has_brew -eq 1 ]] && { printf '%s\n' "$brew_formulae" | grep -Fqx "$cmd_name" || printf '%s\n' "$brew_formulae" | grep -Fqx "$cmd_token"; }; then
            source="Homebrew Formula"
            confidence="High"
            install_evidence="exact-formula-match"
        elif [[ $has_brew -eq 1 ]] && { printf '%s\n' "$brew_casks" | grep -Fqx "$cmd_name" || printf '%s\n' "$brew_casks" | grep -Fqx "$cmd_token"; }; then
            source="Homebrew Cask"
            confidence="High"
            install_evidence="exact-cask-match"
        elif is_installed_cask_alias_for_token "$cmd_token"; then
            source="Homebrew Cask"
            confidence="Medium"
            install_evidence="cask-alias-match"
        fi

        if [[ "$source" == "Manual / Other" ]]; then
            brew_avail="$(get_brew_availability "$cmd_name")"
            if [[ "$brew_avail" == Available\ as\ Cask:* || "$brew_avail" == Available\ as\ Formula:* ]]; then
                confidence="Medium"
                install_evidence="inferred-availability"
            else
                confidence="Low"
                if [[ "$brew_avail" == "Homebrew not installed" ]]; then
                    install_evidence="brew-missing"
                else
                    install_evidence="not-found"
                fi
            fi
        fi

        write_row "$cmd_name" "$source" "$cmd" "$version" "$brew_avail" "$confidence" "$install_evidence"
        append_json_row "$cmd_name" "$source" "$cmd" "$version" "$brew_avail" "$confidence" "$install_evidence" "Command"

        cmd_processed=$((cmd_processed + 1))
        if (( cmd_processed % PROGRESS_EVERY == 0 || cmd_processed == cmd_total )); then
            log_progress "Commands" "$cmd_processed" "$cmd_total" "$cmd_start_ts"
        fi
    done
done

    write_html_dashboard

    echo "✅ re.Brew scan complete!"
    echo "   CSV:  $OUTPUT_CSV"
    echo "   HTML: $OUTPUT_HTML"