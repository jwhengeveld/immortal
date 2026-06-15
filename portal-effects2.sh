#!/usr/bin/env bash
#
# portal-effects.sh
# -----------------
# Aangepast voor gebruik ZONDER root via portal-toolkit (tchebb)
# https://codeberg.org/tchebb/portal-toolkit
#
#  extract  -> trekt effecten/stories + catalogus-metadata uit een Portal
#              zonder root, gebruikmakend van de portal-toolkit.
#  analyze  -> pakt zo'n dump uit en lijst de gevonden stories/effecten op
#              (met ID's en of de assets compleet lijken)
#  all      -> extract gevolgd door analyze
#
# Vereist op de pc: adb, tar, git, python3. Optioneel: sqlite3 (rijkere analyse).

set -euo pipefail

# ----------------------------------------------------------------------------
# Toolkit Instellingen
# ----------------------------------------------------------------------------
TOOLKIT_URL="enable-internal-settings.sh"
TOOLKIT_DIR="/"

# ----------------------------------------------------------------------------
# Apps waarvan we de effect-/story-cache willen redden.
# ----------------------------------------------------------------------------
PACKAGES=(
  "com.facebook.aloha.app.storytime"     # StoryTime (verhalen + AR)
  "com.facebook.aloha.app.photobooth"    # Photo Booth (AR-effecten)
  "com.facebook.alohaapps.superframe"    # Photos (AR / frames)
)

# Submappen binnen /data/data/<pkg> die we proberen mee te nemen.
SUBDIRS=( "cache" "files" "shared_prefs" "databases" "app_ardelivery" )

# Patronen om effect-/story-mappen te herkennen (gebruikt bij analyse).
FIND_NAMES=( "*effect_asset_disk_cache*" "*ardelivery*" "*msqrd*" "*spark*" \
             "*stor*" "*creative_formats*" "*thumbnail_assets*" )

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
portal-effects.sh — Portal AR-effecten redden (zonder root via portal-toolkit)

  ./portal-effects.sh extract [uitvoermap]   van de Portal halen via toolkit
  ./portal-effects.sh analyze <dumpmap>      een dump uitpakken + oplijsten
  ./portal-effects.sh all     [uitvoermap]   extract, daarna analyze

Standaard uitvoermap: ./portal-effects-dump-<datum>
EOF
}

# ============================================================================
#  EXTRACT (Zonder Root)
# ============================================================================
do_extract() {
  local OUTDIR="$1"
  command -v adb >/dev/null 2>&1 || die "adb niet gevonden in PATH."
  command -v git >/dev/null 2>&1 || die "git niet gevonden in PATH."

  local DEV_COUNT; DEV_COUNT="$(adb devices | grep -cw device || true)"
  [ "$DEV_COUNT" -ge 1 ] || die "Geen ADB-apparaat verbonden (zie 'adb devices')."
  [ "$DEV_COUNT" -eq 1 ] || warn "Meerdere apparaten verbonden; zet eventueel ANDROID_SERIAL."

  # Zorg dat de toolkit aanwezig is
  if [ ! -d "$TOOLKIT_DIR" ]; then
    log "portal-toolkit niet lokaal gevonden. Downloaden van Codeberg..."
    git clone "$TOOLKIT_URL" "$TOOLKIT_DIR" || die "Kon toolkit niet clonen."
  fi
  ok "Portal-toolkit is aanwezig."

  mkdir -p "$OUTDIR"
  local MANIFEST="$OUTDIR/MANIFEST.txt"
  : > "$MANIFEST"
  {
    echo "Portal effecten/stories dump (Unrooted / Toolkit method)"
    echo "Datum   : $(date -Iseconds)"
    echo "Toestel : $(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r') / $(adb shell getprop ro.build.display.id 2>/dev/null | tr -d '\r')"
    echo "============================================================"
  } >> "$MANIFEST"

  local TOTAL_PULLED=0
  local PKG SUB

  # We maken een tijdelijke map lokaal aan om de bestanden in te trekken voordat we ze inpakken
  local LOCAL_TMP_DIR="$OUTDIR/.tmp_pull"
  mkdir -p "$LOCAL_TMP_DIR"

  for PKG in "${PACKAGES[@]}"; do
    echo; log "=== $PKG ==="
    echo "" >> "$MANIFEST"; echo "[$PKG]" >> "$MANIFEST"

    local PKG_TMP_BASE="$LOCAL_TMP_DIR/$PKG"
    mkdir -p "$PKG_TMP_BASE"

    for SUB in "${SUBDIRS[@]}"; do
      local SRC="/data/data/$PKG/$SUB"
      local DST="$OUTDIR/${PKG}__${SUB}.tar.gz"

      log "Via portal-toolkit ophalen: $SRC"
      
      # ----------------------------------------------------------------------
      # AANPASSING: Configureer hier de exacte executie van portal-toolkit. 
      # Ga ervan uit dat de tool een manier heeft om een path te pullen.
      # Bijv: python3 "$TOOLKIT_DIR/main.py" pull <device_path> <local_path>
      # ----------------------------------------------------------------------
      if ! python3 "$TOOLKIT_DIR/main.py" pull "$SRC" "$PKG_TMP_BASE/" 2>/dev/null; then
        warn "Toolkit kon $SRC niet ophalen (misschien bestaat de map niet of is de syntax anders)."
        continue
      fi

      # Als de map succesvol is overgehaald naar onze lokale temp folder, pakken we hem in
      if [ -d "$PKG_TMP_BASE/$SUB" ] && [ -n "$(ls -A "$PKG_TMP_BASE/$SUB" 2>/dev/null)" ]; then
        log "Lokaal inpakken van $SUB..."
        if tar -czf "$DST" -C "$PKG_TMP_BASE" "$SUB" 2>/dev/null; then
          local BYTES HSZ
          BYTES="$(stat -c%s "$DST" 2>/dev/null || stat -f%z "$DST" 2>/dev/null || echo 0)"
          HSZ="$(du -h "$DST" 2>/dev/null | awk '{print $1}')"
          ok "Opgehaald: $(basename "$DST")  (${HSZ})"
          echo "  pulled ${HSZ:-?}  ${PKG}__${SUB}.tar.gz" >> "$MANIFEST"
          TOTAL_PULLED=$((TOTAL_PULLED + BYTES))
        else
          warn "Lokale tar mislukte voor $DST"
        fi
      else
         warn "Map $SUB lijkt leeg of niet opgehaald."
      fi
    done
  done

  # Ruim de onverpakte tijdelijke bestanden op
  rm -rf "$LOCAL_TMP_DIR"

  echo
  ok "Extract klaar. Totaal: $(awk "BEGIN{printf \"%.1f\", $TOTAL_PULLED/1048576}") MiB -> $OUTDIR/"
  log "Manifest: $MANIFEST"
}

# ============================================================================
#  ANALYZE
# ============================================================================
do_analyze() {
  local DUMP="$1"
  [ -d "$DUMP" ] || die "Dumpmap niet gevonden: $DUMP"
  command -v tar >/dev/null 2>&1 || die "tar niet gevonden."

  local UNP="$DUMP/_unpacked"
  local REPORT="$DUMP/ANALYSIS.txt"
  mkdir -p "$UNP"
  : > "$REPORT"

  local HAVE_SQLITE=0
  command -v sqlite3 >/dev/null 2>&1 && HAVE_SQLITE=1

  {
    echo "Portal effecten/stories — ANALYSE"
    echo "Datum : $(date -Iseconds)"
    echo "Dump  : $DUMP"
    echo "sqlite3: $([ $HAVE_SQLITE -eq 1 ] && echo aanwezig || echo afwezig)"
    echo "============================================================"
  } >> "$REPORT"

  # 1) Alle tarballs uitpakken.
  local found_tar=0 t
  for t in "$DUMP"/*.tar.gz; do
    [ -e "$t" ] || continue
    found_tar=1
    local base; base="$(basename "$t" .tar.gz)"   # pkg__sub
    local dest="$UNP/$base"
    mkdir -p "$dest"
    log "Uitpakken: $(basename "$t")"
    tar -xzf "$t" -C "$dest" 2>/dev/null || warn "kon $t niet volledig uitpakken"
  done
  [ "$found_tar" -eq 1 ] || die "Geen *.tar.gz in $DUMP — eerst 'extract' draaien?"

  # 2) Effect-/story-bundels lokaliseren.
  echo >> "$REPORT"; echo "## Effect-/story-bundels (asset-bestanden)" >> "$REPORT"
  log "Effect-/story-assets zoeken..."
  local bundles
  bundles="$(find "$UNP" -type f \( -iname '*.arproj' -o -iname '*.zip' -o -iname '*manifest*' \
              -o -iname '*.arbundle' -o -iname 'effect*' \) 2>/dev/null | sort || true)"
  if [ -n "$bundles" ]; then
    local cnt; cnt="$(printf '%s\n' "$bundles" | grep -c . || true)"
    ok "$cnt mogelijke bundel-/manifestbestanden gevonden."
    echo "$bundles" | while read -r f; do
      [ -n "$f" ] || continue
      printf '  %8s  %s\n' "$(du -h "$f" 2>/dev/null | awk '{print $1}')" "${f#$UNP/}" >> "$REPORT"
    done
  else
    warn "Geen losse bundels gevonden."
    echo "  (geen losse bundels herkend — zie cache-mappen hieronder)" >> "$REPORT"
  fi

  # 3) effect_asset_disk_cache-mappen + groottes (de eigenlijke gecachete assets).
  echo >> "$REPORT"; echo "## Effect-asset-disk-caches (ruwe gecachete assets)" >> "$REPORT"
  local cdir
  while read -r cdir; do
    [ -n "$cdir" ] || continue
    local files sz
    files="$(find "$cdir" -type f 2>/dev/null | wc -l | tr -d ' ')"
    sz="$(du -sh "$cdir" 2>/dev/null | awk '{print $1}')"
    printf '  %8s  %5s bestanden  %s\n' "${sz:-?}" "$files" "${cdir#$UNP/}" >> "$REPORT"
  done < <(find "$UNP" -type d \( -iname '*effect_asset_disk_cache*' -o -iname '*ardelivery*' \
            -o -iname '*msqrd*' -o -iname '*spark*' \) 2>/dev/null | sort)

  # 4) Story-/effect-ID's en namen uit shared_prefs (XML).
  echo >> "$REPORT"; echo "## Story-/effect-ID's en namen (uit shared_prefs)" >> "$REPORT"
  log "shared_prefs doorzoeken op story-/effect-ID's..."
  local xml
  while read -r xml; do
    [ -n "$xml" ] || continue
    local hits
    hits="$(grep -oiE 'effect[_-]?id[^<>"]{0,40}|story[_-]?id[^<>"]{0,40}|"[0-9]{8,}"|name="[^"]*"' "$xml" 2>/dev/null \
            | sort -u | head -40 || true)"
    if [ -n "$hits" ]; then
      echo "  -- ${xml#$UNP/} --" >> "$REPORT"
      printf '%s\n' "$hits" | sed 's/^/     /' >> "$REPORT"
    fi
  done < <(find "$UNP" -type f -name '*.xml' 2>/dev/null | grep -iE 'stor|effect|spark|ardeliver' | sort)

  # 5) Databases: tabellen + rijen die naar stories/effecten verwijzen.
  echo >> "$REPORT"; echo "## Databases (tabellen met story/effect-data)" >> "$REPORT"
  if [ $HAVE_SQLITE -eq 1 ]; then
    log "SQLite-databases inspecteren..."
    local db
    while read -r db; do
      [ -n "$db" ] || continue
      echo "  -- ${db#$UNP/} --" >> "$REPORT"
      local tables
      tables="$(sqlite3 "$db" ".tables" 2>/dev/null || true)"
      [ -n "$tables" ] && printf '     tabellen: %s\n' "$tables" >> "$REPORT"
      local tb
      for tb in $(echo "$tables" | tr ' ' '\n' | grep -iE 'stor|effect|asset|spark|ardeliver' || true); do
        local rc; rc="$(sqlite3 "$db" "SELECT COUNT(*) FROM \"$tb\";" 2>/dev/null || echo '?')"
        printf '     %s: %s rijen\n' "$tb" "$rc" >> "$REPORT"
        sqlite3 -header "$db" "SELECT * FROM \"$tb\" LIMIT 5;" 2>/dev/null | sed 's/^/        /' >> "$REPORT" || true
      done
    done < <(find "$UNP" -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) 2>/dev/null | sort)
  else
    warn "sqlite3 ontbreekt — databases niet uitgelezen. Installeer sqlite3 voor rijkere analyse."
    find "$UNP" -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) 2>/dev/null \
      | sed "s#$UNP/#  (db) #" >> "$REPORT" || true
  fi

  # 6) Samenvatting / oordeel.
  echo >> "$REPORT"; echo "## Samenvatting" >> "$REPORT"
  local asset_bytes asset_files
  asset_files="$(find "$UNP" -type d \( -iname '*effect_asset_disk_cache*' -o -iname '*ardelivery*' \) -exec find {} -type f \; 2>/dev/null | wc -l | tr -d ' ')"
  asset_bytes="$(find "$UNP" -type d \( -iname '*effect_asset_disk_cache*' -o -iname '*ardelivery*' \) -exec du -sb {} + 2>/dev/null | awk '{s+=$1} END{printf "%.1f", s/1048576}')"
  {
    echo "  Gecachete asset-bestanden in caches: ${asset_files:-0}"
    echo "  Totale omvang van die caches: ${asset_bytes:-0} MiB"
    if [ "${asset_files:-0}" -gt 0 ]; then
      echo "  -> Er staat lokaal gecachete effect-/story-content."
    else
      echo "  -> GEEN gecachete effect-/story-assets gevonden."
    fi
  } >> "$REPORT"

  echo
  ok "Analyse klaar -> $REPORT"
  log "Uitgepakt in: $UNP/"
  echo "------------------------------------------------------------"
  cat "$REPORT"
}

# ============================================================================
#  Dispatcher
# ============================================================================
CMD="${1:-}"; shift || true
case "$CMD" in
  extract) do_extract "${1:-portal-effects-dump-$(date +%Y%m%d-%H%M%S)}" ;;
  analyze) [ -n "${1:-}" ] || die "Geef de dumpmap op: ./portal-effects.sh analyze <dumpmap>"
           do_analyze "$1" ;;
  all)     OUT="${1:-portal-effects-dump-$(date +%Y%m%d-%H%M%S)}"
           do_extract "$OUT"; echo; do_analyze "$OUT" ;;
  ""|-h|--help|help) usage ;;
  *)       warn "Onbekend commando: $CMD"; usage; exit 1 ;;
esac
