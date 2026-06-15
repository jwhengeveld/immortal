#!/usr/bin/env bash
#
# portal-effects.sh
# -----------------
# Eén hulpmiddel voor Meta Portal AR-effecten EN StoryTime-verhalen:
#
#   extract  -> trekt effecten/stories + catalogus-metadata uit een GEROOTE Portal
#   analyze  -> pakt zo'n dump uit en lijst de gevonden stories/effecten op
#               (met ID's en of de assets compleet lijken)
#   all      -> extract gevolgd door analyze
#
# Achtergrond: Portal AR-effecten en StoryTime-stories worden door het
# 'ardelivery'-systeem gedownload en bewaard in /data/data/<pkg>/cache, in caches
# met namen als *effect_asset_disk_cache* (msqrd / mixed hot|cold). Stories zijn
# zelf AR-effecten plus story-metadata (StoryStore / stories_config / thumbnails).
# Sinds Meta de effect-backend heeft uitgezet levert de server een lege catalogus;
# het enige wat nog te redden valt zijn effecten/stories die DESTIJDS al gecachet
# zijn. Die staan in interne opslag en vereisen ROOT om bij te komen.
#
# Gebruik:
#   ./portal-effects.sh extract [uitvoermap]
#   ./portal-effects.sh analyze <dumpmap>
#   ./portal-effects.sh all     [uitvoermap]
#
# Vereist op de pc: adb (voor extract), tar. Optioneel: sqlite3 (rijkere analyse).
# Vereist op het toestel (alleen extract): ROOT (Magisk/su of userdebug/eng-build).

set -euo pipefail

# ----------------------------------------------------------------------------
# Apps waarvan we de effect-/story-cache willen redden. Vrij aan te passen.
# ----------------------------------------------------------------------------
PACKAGES=(
  "com.facebook.aloha.app.storytime"     # StoryTime  (verhalen + AR)
  "com.facebook.aloha.app.photobooth"    # Photo Booth (AR-effecten)
  "com.facebook.alohaapps.superframe"    # Photos
  "com.facebook.aloha.app.cameraeditor"  # Camera/Avatar editor (AR)
)

# Submappen binnen /data/data/<pkg> die we proberen mee te nemen.
SUBDIRS=( "cache" "files" "shared_prefs" "databases" "app_ardelivery" )

# Werkmap op het toestel (schrijfbaar als root).
DEVICE_TMP="/data/local/tmp/portal_dump"

# Patronen om effect-/story-mappen te herkennen.
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
portal-effects.sh — Portal AR-effecten & StoryTime-verhalen redden/analyseren

  ./portal-effects.sh extract [uitvoermap]   van een GEROOTE Portal halen
  ./portal-effects.sh analyze <dumpmap>      een dump uitpakken + oplijsten
  ./portal-effects.sh all     [uitvoermap]   extract, daarna analyze

Standaard uitvoermap: ./portal-effects-dump-<datum>
EOF
}

# ============================================================================
#  EXTRACT
# ============================================================================
ROOT_MODE=""

detect_root() {
  adb root >/dev/null 2>&1 || true
  adb wait-for-device >/dev/null 2>&1 || true
  if [ "$(adb shell 'id -u' 2>/dev/null | tr -d '\r')" = "0" ]; then ROOT_MODE="adbroot"; return 0; fi
  if [ "$(adb shell 'su -c id -u' 2>/dev/null | tr -d '\r')" = "0" ]; then ROOT_MODE="su"; return 0; fi
  if [ "$(adb shell 'su 0 id -u' 2>/dev/null | tr -d '\r')" = "0" ]; then ROOT_MODE="su0"; return 0; fi
  return 1
}

RUN_ROOT() {
  case "$ROOT_MODE" in
    adbroot) adb shell "$1" ;;
    su)      adb shell "su -c '$1'" ;;
    su0)     adb shell "su 0 sh -c '$1'" ;;
    *)       die "Geen root-modus bepaald." ;;
  esac
}

do_extract() {
  local OUTDIR="$1"
  command -v adb >/dev/null 2>&1 || die "adb niet gevonden in PATH."

  local DEV_COUNT; DEV_COUNT="$(adb devices | grep -cw device || true)"
  [ "$DEV_COUNT" -ge 1 ] || die "Geen ADB-apparaat verbonden (zie 'adb devices')."
  [ "$DEV_COUNT" -eq 1 ] || warn "Meerdere apparaten verbonden; zet eventueel ANDROID_SERIAL."

  log "Root-toegang detecteren..."
  if ! detect_root; then
    die "Geen root verkregen. Dit toestel moet geroot zijn (Magisk/su) of een userdebug/eng-build draaien.
     Test handmatig:  adb shell su -c id   (moet uid=0 geven)."
  fi
  ok "Root actief via modus: $ROOT_MODE"

  mkdir -p "$OUTDIR"
  local MANIFEST="$OUTDIR/MANIFEST.txt"
  : > "$MANIFEST"
  {
    echo "Portal effecten/stories dump"
    echo "Datum   : $(date -Iseconds)"
    echo "Root    : $ROOT_MODE"
    echo "Toestel : $(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r') / $(adb shell getprop ro.build.display.id 2>/dev/null | tr -d '\r')"
    echo "============================================================"
  } >> "$MANIFEST"

  RUN_ROOT "rm -rf $DEVICE_TMP; mkdir -p $DEVICE_TMP" >/dev/null 2>&1 || true

  # Bouw de find-expressie ( -name a -o -name b -o ... ).
  local FIND_EXPR=""
  local n
  for n in "${FIND_NAMES[@]}"; do
    if [ -z "$FIND_EXPR" ]; then FIND_EXPR="-name '$n'"; else FIND_EXPR="$FIND_EXPR -o -name '$n'"; fi
  done

  local TOTAL_PULLED=0
  local PKG SUB
  for PKG in "${PACKAGES[@]}"; do
    echo; log "=== $PKG ==="

    if [ "$(RUN_ROOT "[ -d /data/data/$PKG ] && echo yes || echo no" | tr -d '\r')" != "yes" ]; then
      warn "Geen /data/data/$PKG — app niet geïnstalleerd, overslaan."
      echo "[$PKG] NIET AANWEZIG" >> "$MANIFEST"; continue
    fi

    echo "" >> "$MANIFEST"; echo "[$PKG]" >> "$MANIFEST"
    log "Effect-/story-caches inventariseren..."
    local EFFECT_DIRS
    EFFECT_DIRS="$(RUN_ROOT "find /data/data/$PKG -type d \( $FIND_EXPR \) 2>/dev/null" | tr -d '\r' || true)"
    if [ -n "$EFFECT_DIRS" ]; then
      ok "Gevonden effect-/AR-/story-mappen:"
      while read -r d; do
        [ -n "$d" ] || continue
        local SZ; SZ="$(RUN_ROOT "du -sh '$d' 2>/dev/null" | tr -d '\r' | awk '{print $1}')"
        printf '    %-8s %s\n' "${SZ:-?}" "$d"
        printf '  cache  %-8s %s\n' "${SZ:-?}" "$d" >> "$MANIFEST"
      done <<< "$EFFECT_DIRS"
    else
      warn "Geen herkenbare effect-/story-cache gevonden (mogelijk al opgeruimd of nooit gecachet)."
      echo "  (geen herkenbare effect-/story-cache gevonden)" >> "$MANIFEST"
    fi

    for SUB in "${SUBDIRS[@]}"; do
      local SRC="/data/data/$PKG/$SUB"
      [ "$(RUN_ROOT "[ -d $SRC ] && echo yes || echo no" | tr -d '\r')" = "yes" ] || continue
      [ -n "$(RUN_ROOT "ls -A $SRC 2>/dev/null | head -1" | tr -d '\r')" ] || continue

      local TAR_DEV="$DEVICE_TMP/${PKG}__${SUB}.tar.gz"
      log "Inpakken: $SRC"
      if ! RUN_ROOT "tar -czf '$TAR_DEV' -C /data/data/$PKG '$SUB' 2>/dev/null"; then
        warn "tar mislukte voor $SRC (overslaan)."; continue
      fi
      RUN_ROOT "chmod 644 '$TAR_DEV'" >/dev/null 2>&1 || true

      local DST="$OUTDIR/${PKG}__${SUB}.tar.gz"
      if adb pull "$TAR_DEV" "$DST" >/dev/null 2>&1; then
        local BYTES HSZ
        BYTES="$(stat -c%s "$DST" 2>/dev/null || echo 0)"
        HSZ="$(du -h "$DST" 2>/dev/null | awk '{print $1}')"
        ok "Opgehaald: $(basename "$DST")  (${HSZ})"
        echo "  pulled ${HSZ:-?}  ${PKG}__${SUB}.tar.gz" >> "$MANIFEST"
        TOTAL_PULLED=$((TOTAL_PULLED + BYTES))
      else
        warn "adb pull mislukte voor $TAR_DEV"
      fi
      RUN_ROOT "rm -f '$TAR_DEV'" >/dev/null 2>&1 || true
    done
  done

  RUN_ROOT "rm -rf $DEVICE_TMP" >/dev/null 2>&1 || true
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
  # Spark/ardelivery-assets zijn vaak .zip-bundels of mappen met een manifest.
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
    warn "Geen losse bundel-/manifestbestanden herkend (assets kunnen hash-gebaseerd opgeslagen zijn)."
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
    echo "  Gecachete asset-bestanden in effect/ardelivery-caches: ${asset_files:-0}"
    echo "  Totale omvang van die caches: ${asset_bytes:-0} MiB"
    if [ "${asset_files:-0}" -gt 0 ]; then
      echo "  -> Er staat lokaal gecachete effect-/story-content. Combineer de asset-caches met"
      echo "     de ID's/metadata hierboven om te bepalen welke stories/effecten compleet zijn."
    else
      echo "  -> GEEN gecachete effect-/story-assets gevonden. Dit toestel heeft de content"
      echo "     waarschijnlijk nooit afgespeeld toen de Meta-backend nog leefde."
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
