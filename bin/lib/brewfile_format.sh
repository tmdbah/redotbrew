#!/usr/bin/env bash
# re.Brew — Brewfile section-aware merge.
# Merges a machine-dumped Brewfile into the curated repo Brewfile,
# preserving section headers, sub-comments, and entry ordering.
# https://github.com/tmdbah/redotbrew
#
# Usage (sourced by sync.sh):
#   merge_brewfile <repo_brewfile> <dump_brewfile>
#   Writes merged result to stdout.

# ── Extract the entry key from a Brewfile line ───────────────────────────────
# Returns "type:name" or empty string if not an entry line.
_entry_key() {
  local line="$1"
  case "$line" in
    tap\ *)    echo "tap:$(echo "$line"    | sed -E 's/^tap "([^"]+)".*/\1/')" ;;
    brew\ *)   echo "brew:$(echo "$line"   | sed -E 's/^brew "([^"]+)".*/\1/')" ;;
    cask\ *)   echo "cask:$(echo "$line"   | sed -E 's/^cask "([^"]+)".*/\1/')" ;;
    mas\ *)    echo "mas:$(echo "$line"    | sed -E 's/.*id: ([0-9]+).*/\1/')" ;;
    vscode\ *) echo "vscode:$(echo "$line" | sed -E 's/^vscode "([^"]+)".*/\1/' | tr '[:upper:]' '[:lower:]')" ;;
    *)         echo "" ;;
  esac
}

# ── Check if a key exists in a key file (one key per line) ───────────────────
_has_key() {
  grep -qxF "$1" "$2" 2>/dev/null
}

# ── Main merge function ─────────────────────────────────────────────────────
# Args: $1 = repo Brewfile path, $2 = dump Brewfile path
# Stdout: merged Brewfile content
merge_brewfile() {
  local repo_file="$1"
  local dump_file="$2"
  local _outfile _dump_keys _repo_keys _new_file _new_dir _type_sec
  _outfile="$(mktemp /tmp/rebrew-merge.XXXXXX)"
  _dump_keys="$(mktemp /tmp/rebrew-dkeys.XXXXXX)"
  _repo_keys="$(mktemp /tmp/rebrew-rkeys.XXXXXX)"
  _new_file="$(mktemp /tmp/rebrew-new.XXXXXX)"
  _new_dir="$(mktemp -d /tmp/rebrew-newsec.XXXXXX)"
  _type_sec="$(mktemp /tmp/rebrew-tsec.XXXXXX)"

  local key line etype

  # --- Step 1: Build key files for dump and repo ----------------------------
  while IFS= read -r line || [[ -n "$line" ]]; do
    key="$(_entry_key "$line")"
    [[ -n "$key" ]] && echo "$key" >> "$_dump_keys"
  done < "$dump_file"

  while IFS= read -r line || [[ -n "$line" ]]; do
    key="$(_entry_key "$line")"
    [[ -n "$key" ]] && echo "$key" >> "$_repo_keys"
  done < "$repo_file"

  # --- Step 2: Collect new entries (in dump, not in repo) -------------------
  while IFS= read -r line || [[ -n "$line" ]]; do
    key="$(_entry_key "$line")"
    [[ -z "$key" ]] && continue
    if ! _has_key "$key" "$_repo_keys"; then
      printf '%s\t%s\n' "$key" "$line" >> "$_new_file"
    fi
  done < "$dump_file"

  # --- Step 3: Find first section index of each entry type ------------------
  # _type_sec file contains lines like "tap=1", "brew=2", etc.
  local section_idx=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "# =="* ]]; then
      section_idx=$(( section_idx + 1 ))
    fi
    etype=""
    case "$line" in
      tap\ *)    etype="tap" ;;
      brew\ *)   etype="brew" ;;
      cask\ *)   etype="cask" ;;
      mas\ *)    etype="mas" ;;
      vscode\ *) etype="vscode" ;;
    esac
    if [[ -n "$etype" ]] && ! grep -q "^${etype}=" "$_type_sec" 2>/dev/null; then
      echo "${etype}=${section_idx}" >> "$_type_sec"
    fi
  done < "$repo_file"

  # --- Step 4: Group new entries by target section --------------------------
  local _uncat_file="$_new_dir/uncategorized"
  local nkey nline target_sec
  while IFS=$'\t' read -r nkey nline; do
    [[ -z "$nkey" ]] && continue
    etype="${nkey%%:*}"
    target_sec="$(grep "^${etype}=" "$_type_sec" 2>/dev/null | cut -d= -f2)"
    if [[ -n "$target_sec" ]]; then
      echo "$nline" >> "$_new_dir/sec_${target_sec}"
    else
      echo "$nline" >> "$_uncat_file"
    fi
  done < "$_new_file"

  # Sort new entries within each group
  local f
  for f in "$_new_dir"/sec_*; do
    [[ -f "$f" ]] && sort -o "$f" "$f"
  done 2>/dev/null
  [[ -f "$_uncat_file" ]] && sort -o "$_uncat_file" "$_uncat_file"

  # --- Step 5: Walk repo Brewfile, emit merged output to _outfile -----------
  local current_sec=0
  local pending_subcomment=""
  local subcomment_has_entries="false"
  local in_header="false"

  while IFS= read -r line || [[ -n "$line" ]]; do

    # ── Section header separator (# ===...) ──
    if [[ "$line" == "# =="* ]]; then
      if [[ "$in_header" == "false" ]]; then
        # Opening separator — flush new entries for the section that just ended
        if [[ $current_sec -gt 0 && -f "$_new_dir/sec_$current_sec" ]]; then
          cat "$_new_dir/sec_$current_sec" >> "$_outfile"
          echo "" >> "$_outfile"
          rm "$_new_dir/sec_$current_sec"
        fi
        # Flush pending subcomment
        if [[ -n "$pending_subcomment" && "$subcomment_has_entries" == "true" ]]; then
          echo "$pending_subcomment" >> "$_outfile"
        fi
        pending_subcomment=""
        subcomment_has_entries="false"
        in_header="true"
      else
        # Closing separator
        in_header="false"
      fi

      current_sec=$(( current_sec + 1 ))
      echo "$line" >> "$_outfile"
      continue
    fi

    # ── Inside header block (title line between separators) ──
    if [[ "$in_header" == "true" ]]; then
      echo "$line" >> "$_outfile"
      continue
    fi

    key="$(_entry_key "$line")"

    # ── Entry line ──
    if [[ -n "$key" ]]; then
      if _has_key "$key" "$_dump_keys"; then
        # Kept — flush pending subcomment first
        if [[ -n "$pending_subcomment" ]]; then
          echo "$pending_subcomment" >> "$_outfile"
          pending_subcomment=""
        fi
        subcomment_has_entries="true"
        echo "$line" >> "$_outfile"
      fi
      # Removed entries: skip silently
      continue
    fi

    # ── Sub-comment (# ...) ──
    if [[ "$line" == "#"* ]]; then
      # Flush previous pending subcomment if it had entries
      if [[ -n "$pending_subcomment" && "$subcomment_has_entries" == "true" ]]; then
        echo "$pending_subcomment" >> "$_outfile"
      fi
      pending_subcomment="$line"
      subcomment_has_entries="false"
      continue
    fi

    # ── Blank or unknown line ──
    echo "$line" >> "$_outfile"
  done < "$repo_file"

  # Flush new entries for the last section
  if [[ $current_sec -gt 0 && -f "$_new_dir/sec_$current_sec" ]]; then
    cat "$_new_dir/sec_$current_sec" >> "$_outfile"
  fi

  # Flush final pending subcomment
  if [[ -n "$pending_subcomment" && "$subcomment_has_entries" == "true" ]]; then
    echo "$pending_subcomment" >> "$_outfile"
  fi

  # --- Step 6: Append uncategorized new entries -----------------------------
  if [[ -f "$_uncat_file" ]]; then
    {
      echo ""
      echo "# =========================================================="
      echo "# Uncategorized"
      echo "# =========================================================="
      echo ""
      cat "$_uncat_file"
    } >> "$_outfile"
  fi

  # --- Step 7: Clean up consecutive blank lines (3+ → 2), emit to stdout ---
  awk '
    /^[[:space:]]*$/ { blank++; next }
    { for (i=0; i < (blank > 2 ? 2 : blank); i++) print ""; blank=0; print }
    END { if (blank > 0) print "" }
  ' "$_outfile"

  rm -f "$_outfile" "$_dump_keys" "$_repo_keys" "$_new_file" "$_type_sec"
  rm -rf "$_new_dir"
}
