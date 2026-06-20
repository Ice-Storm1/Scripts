#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[94m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'
SEP="  ────────────────────────────────────────────"

OK="${GREEN}[ OK ]${NC}"
ERR="${RED}[ERR]${NC}"
WARN="${YELLOW}[WARN]${NC}"
INFO="${CYAN}[INFO]${NC}"
PROC="${WHITE}[ .. ]${NC}"

SCRIPT_DIR=$(dirname "$(readlink -f "$0")" 2>/dev/null || echo "$HOME/Scrivania")
BACKUP_PREFIX="plsctlconfig"

trap '
  echo ""
  kstart5 plasmashell 2>/dev/null &
  exit 1
' INT TERM

check_prereqs() {
  local missing=0
  for cmd in kwriteconfig6 kquitapp5 kstart5 \
             plasma-apply-lookandfeel plasma-apply-desktoptheme \
             plasma-apply-colorscheme plasma-apply-icons; do
    command -v "$cmd" &>/dev/null && continue
    echo -e "  ${WARN} $cmd non trovato"
    ((missing++))
  done
  [ $missing -gt 0 ] && echo ""
  return $missing
}

THEME_DIRS=(
  "$HOME/.local/share/plasma/desktoptheme"
  "$HOME/.local/share/plasma/look-and-feel"
  "$HOME/.local/share/plasma/plasmoids"
  "$HOME/.local/share/plasma/splash"
  "$HOME/.local/share/aurorae/themes"
  "$HOME/.local/share/color-schemes"
  "$HOME/.local/share/icons"
  "$HOME/.local/share/themes"
  "$HOME/.local/share/wallpapers"
  "$HOME/.local/share/kwin/scripts"
)

CONFIG_FILES=(
  "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
  "$HOME/.config/plasmashellrc"
  "$HOME/.config/plasmarc"
  "$HOME/.config/kwinrc"
  "$HOME/.config/kdeglobals"
  "$HOME/.config/kded6rc"
  "$HOME/.config/breezerc"
  "$HOME/.config/ksplashrc"
  "$HOME/.config/kscreenlockerrc"
  "$HOME/.config/gtk-3.0/settings.ini"
  "$HOME/.config/gtk-4.0/settings.ini"
)

KEEP_DESKTHEME='^(breeze|breeze-dark|breeze-light|fedora|fedora-dark|fedora-light)$'
KEEP_COLORS='^Breeze'
KEEP_ICONS='^(hicolor|breeze|breeze-dark|breeze-light|distrobox)$'
KEEP_AURORAE='^(Breeze|Breeze-light|Breeze-dark)$'

CAT_NAMES=(
  "stili plasma"
  "look-and-feel"
  "widget"
  "schermata iniziale"
  "decorazioni finestre"
  "schemi colore"
  "icone"
  "temi gtk"
  "sfondi"
  "script kwin"
  "layout e configurazione"
)
CAT_RELS=(
  ".local/share/plasma/desktoptheme"
  ".local/share/plasma/look-and-feel"
  ".local/share/plasma/plasmoids"
  ".local/share/plasma/splash"
  ".local/share/aurorae/themes"
  ".local/share/color-schemes"
  ".local/share/icons"
  ".local/share/themes"
  ".local/share/wallpapers"
  ".local/share/kwin/scripts"
  ".config"
)
CAT_COUNT=${#CAT_NAMES[@]}

header() {
  clear
  echo ""
  echo -e "  ${BOLD}plasmactl${NC} — gestore temi KDE Plasma"
  echo "$SEP"
}

pause() {
  echo ""
  echo -e "  ${INFO} invio per continuare..."
  read -r
}

confirm() {
  echo ""
  echo -n "  $1 [y/N]: "
  read -r ans
  [[ "$ans" =~ ^[YySs] ]] && return 0
  return 1
}

pick_backup() {
  local dirs=()
  for d in "$SCRIPT_DIR"/"$BACKUP_PREFIX"-*/; do
    [ -d "$d" ] && dirs+=("$d")
  done

  if [ ${#dirs[@]} -eq 0 ]; then
    echo -e "  ${ERR} nessun backup trovato in $SCRIPT_DIR"
    echo -e "  ${INFO} creane uno con: backup"
    pause
    return 1
  fi

  if [ ${#dirs[@]} -eq 1 ]; then
    BACKUP_DIR="${dirs[0]}"
    BACKUP_NAME=$(basename "$BACKUP_DIR" | sed "s/^$BACKUP_PREFIX-//")
    [ -f "$BACKUP_DIR/.meta/name" ] && BACKUP_NAME=$(cat "$BACKUP_DIR/.meta/name" 2>/dev/null)
    echo -e "  ${OK} backup: $BACKUP_NAME"
    return 0
  fi

  echo -e "  ${INFO} backup disponibili:"
  echo ""
  for i in "${!dirs[@]}"; do
    local display=$(basename "${dirs[$i]}" | sed "s/^$BACKUP_PREFIX-//")
    [ -f "${dirs[$i]}.meta/name" ] && display=$(cat "${dirs[$i]}.meta/name" 2>/dev/null)
    printf "  %2d  %s\n" "$((i+1))" "$display"
  done
  echo ""
  echo -n "  scegli [1]: "
  read -r choice
  choice=${choice:-1}
  local idx=$((choice - 1))
  if [ $idx -lt 0 ] || [ $idx -ge ${#dirs[@]} ]; then
    echo -e "  ${ERR} numero non valido"
    pause
    return 1
  fi
  BACKUP_DIR="${dirs[$idx]}"
  BACKUP_NAME=$(basename "$BACKUP_DIR" | sed "s/^$BACKUP_PREFIX-//")
  [ -f "$BACKUP_DIR/.meta/name" ] && BACKUP_NAME=$(cat "$BACKUP_DIR/.meta/name" 2>/dev/null)
  return 0
}

# ─── BACKUP ─────────────────────────────────────────────

backup() {
  header
  echo ""

  local has=0
  for d in "${THEME_DIRS[@]}"; do
    [ -d "$d" ] && [ -n "$(ls -A "$d" 2>/dev/null)" ] && { has=1; break; }
  done
  [ $has -eq 0 ] && for f in "${CONFIG_FILES[@]}"; do
    [ -f "$f" ] && { has=1; break; }
  done
  [ $has -eq 0 ] && {
    echo -e "  ${WARN} nessun tema o configurazione da salvare"
    pause; return
  }

  local default_name="backup-$(date +%Y-%m-%d)"
  echo -n "  nome del backup [$default_name]: "
  read -r input_name
  input_name="${input_name:-$default_name}"
  input_name="${input_name//[^a-zA-Z0-9_-]/}"
  [ -z "$input_name" ] && input_name="$default_name"

  local dir_name="$BACKUP_PREFIX-$input_name"
  BACKUP_DIR="$SCRIPT_DIR/$dir_name"

  if [ -d "$BACKUP_DIR" ]; then
    echo -e "  ${WARN} \"$input_name\" esiste già"
    confirm "sovrascrivere" || return
    rm -rf "$BACKUP_DIR"
  fi

  mkdir -p "$BACKUP_DIR/.meta" "$BACKUP_DIR/.config"
  echo "$input_name" > "$BACKUP_DIR/.meta/name"

  echo ""
  echo -e "  ${PROC} salvataggio cartelle temi..."
  local tot=0
  local -a backup_items
  for d in "${THEME_DIRS[@]}"; do
    [ -d "$d" ] || continue
    local rel="${d#$HOME/}"
    local dest="$BACKUP_DIR/$rel"
    mkdir -p "$dest"
    local c=0
    for item in "$d"/*; do
      [ -e "$item" ] || continue
      cp -a "$item" "$dest/" 2>/dev/null && ((c++))
    done
    [ $c -gt 0 ] && printf "  %-30s %d elementi\n" "$(basename "$d")" "$c"
    ((tot+=c))
  done

  echo ""
  echo -e "  ${PROC} salvataggio configurazione..."
  local cfg=0
  for f in "${CONFIG_FILES[@]}"; do
    [ -f "$f" ] && cp -a "$f" "$BACKUP_DIR/.config/" 2>/dev/null && ((cfg++))
  done
  printf "  %-30s %d file\n" "configurazione" "$cfg"

  echo ""
  echo -e "  ${PROC} estrazione metadati..."
  local lnf=$(grep -m1 "^LookAndFeelPackage=" "$HOME/.config/kdeglobals" 2>/dev/null | cut -d= -f2-)
  [ -n "$lnf" ] && echo "$lnf" > "$BACKUP_DIR/.meta/lookandfeel" && printf "  %-30s %s\n" "look-and-feel" "$lnf"

  local dt=$(grep -m1 "^name=" "$HOME/.config/plasmarc" 2>/dev/null | cut -d= -f2-)
  [ -n "$dt" ] && echo "$dt" > "$BACKUP_DIR/.meta/desktoptheme" && printf "  %-30s %s\n" "tema plasma" "$dt"

  local cs=$(grep -m1 "^ColorScheme=" "$HOME/.config/kdeglobals" 2>/dev/null | cut -d= -f2-)
  [ -n "$cs" ] && echo "$cs" > "$BACKUP_DIR/.meta/colorscheme" && printf "  %-30s %s\n" "schema colore" "$cs"

  local ic=$(grep -m1 "^Theme=" "$HOME/.config/kdeglobals" 2>/dev/null | cut -d= -f2-)
  [ -n "$ic" ] && echo "$ic" > "$BACKUP_DIR/.meta/icons" && printf "  %-30s %s\n" "icone" "$ic"

  local dc=$(grep -m1 "^theme=" "$HOME/.config/kwinrc" 2>/dev/null | cut -d= -f2-)
  [ -n "$dc" ] && echo "$dc" > "$BACKUP_DIR/.meta/decoration" && printf "  %-30s %s\n" "decorazione" "$dc"

  awk '/^\[Colors:/{f=1;print;next} /^\[/&&f{f=0;next} f' \
    "$HOME/.config/kdeglobals" 2>/dev/null > "$BACKUP_DIR/.meta/colors_values"
  [ -s "$BACKUP_DIR/.meta/colors_values" ] && printf "  %-30s %s\n" "colori custom" "salvati" || rm -f "$BACKUP_DIR/.meta/colors_values"

  echo ""
  echo "$SEP"
  echo -e "  ${OK} backup completato"
  printf "  %-30s %s\n" "destinazione" "$BACKUP_DIR"
  printf "  %-30s %d elementi, %d file config\n" "totale" "$tot" "$cfg"
  echo "$SEP"
  pause
}

# ─── RESET ──────────────────────────────────────────────

reset() {
  header
  echo ""
  echo "$SEP"
  echo ""
  echo -e "  ${WARN} verranno eliminate tutte le configurazioni KDE"
  echo ""
  confirm "procedere" || return

  echo ""
  echo -e "  ${PROC} pulizia temi e componenti..."
  local tot=0
  for dir in "${THEME_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    for item in "$dir"/*; do
      [ -e "$item" ] || continue
      local name=$(basename "$item")
      case "$dir" in
        */desktoptheme)  [[ "$name" =~ $KEEP_DESKTHEME ]] && continue ;;
        */color-schemes) [[ "$name" =~ $KEEP_COLORS ]] && continue ;;
        */icons)         [[ "$name" =~ $KEEP_ICONS ]] && continue ;;
        */aurorae/themes) [[ "$name" =~ $KEEP_AURORAE ]] && continue ;;
      esac
      rm -rf "$item" 2>/dev/null && ((tot++))
    done
  done
  printf "  %-30s %d elementi rimossi\n" "temi e componenti" "$tot"

  echo ""
  echo -e "  ${PROC} rimozione file di configurazione..."
  local cfg=0
  for f in "${CONFIG_FILES[@]}"; do
    [ -f "$f" ] && rm -f "$f" 2>/dev/null && ((cfg++))
  done
  printf "  %-30s %d file eliminati\n" "configurazione" "$cfg"

  echo ""
  echo -e "  ${PROC} applicazione tema breeze..."
  if command -v plasma-apply-lookandfeel &>/dev/null; then
    plasma-apply-lookandfeel -a org.kde.breeze.desktop 2>/dev/null
    printf "  %-30s %s\n" "tema applicato" "Breeze"
  elif command -v kwriteconfig6 &>/dev/null; then
    kwriteconfig6 --file "$HOME/.config/plasmarc" --group Theme --key name default 2>/dev/null
    kwriteconfig6 --file "$HOME/.config/kdeglobals" --group General --key ColorScheme Breeze 2>/dev/null
    kwriteconfig6 --file "$HOME/.config/kdeglobals" --group Icons --key Theme breeze 2>/dev/null
    printf "  %-30s %s\n" "tema applicato" "Breeze (fallback)"
  else
    echo -e "  ${WARN} impossibile applicare breeze"
  fi

  echo ""
  echo "$SEP"
  echo -e "  ${OK} reset completato"
  echo "$SEP"

  echo ""
  echo -e "  ${PROC} riavvio shell plasma..."
  kquitapp5 plasmashell 2>/dev/null; sleep 1
  kstart5 plasmashell 2>/dev/null &
  pause
}

# ─── RESTORE ────────────────────────────────────────────

restore() {
  header
  echo ""
  pick_backup || return
  echo ""

  local -a selected
  local mantieni=0
  local non_mantieni=0

  echo "  y = mantieni tema (ripristina dal backup)"
  echo "  N = non mantenere (reset a Breeze o default)"
  echo "  a = tieni tutto"
  echo "  o = resetta tutto"
  echo ""

  local global_choice=""
  echo -n "  >> (invio = chiedi singolarmente): "
  read -r global_choice

  if [[ "$global_choice" =~ ^[Aa]$ ]]; then
    for ((i=0; i<CAT_COUNT; i++)); do
      selected[$i]=1
    done
    ((mantieni=CAT_COUNT))
  elif [[ "$global_choice" =~ ^[Oo]$ ]]; then
    for ((i=0; i<CAT_COUNT; i++)); do
      selected[$i]=0
    done
    ((non_mantieni=CAT_COUNT))
  else
    for ((i=0; i<CAT_COUNT; i++)); do
      printf "  %2d  %-25s " "$((i+1))" "${CAT_NAMES[$i]}"
      echo -n "[y/N]: "
      read -r ans
      case "$ans" in
        [YySs]) selected[$i]=1; ((mantieni++)) ;;
        *)      selected[$i]=0; ((non_mantieni++)) ;;
      esac
    done
  fi

  clear
  echo ""
  echo -e "  ${BOLD}RIEPILOGO${NC}"
  echo "$SEP"
  printf "  %-30s %s\n" "backup" "$BACKUP_NAME"
  echo ""
  for ((i=0; i<CAT_COUNT; i++)); do
    if [ "${selected[$i]}" = "1" ]; then
      printf "  %2d  %-25s %s\n" "$((i+1))" "${CAT_NAMES[$i]}" "→ mantieni"
    else
      printf "  %2d  %-25s %s\n" "$((i+1))" "${CAT_NAMES[$i]}" "→ non mantenere"
    fi
  done
  echo "$SEP"
  echo "  $mantieni mantenuti, $non_mantieni non mantenuti"
  echo "$SEP"
  confirm "avviare il restore" || return

  # ── ESECUZIONE ──

  local step=0
  local mantieni_r=0
  local default_r=0
  local vuoti=0
  local -a recap_ris

  for ((i=0; i<CAT_COUNT; i++)); do
    recap_ris[$i]=""
  done

  clear
  echo ""
  echo -e "  ${BOLD}RESTORE IN CORSO${NC}"
  echo "$SEP"
  echo ""

  for ((i=0; i<CAT_COUNT; i++)); do
    local rel="${CAT_RELS[$i]}"
    local src="$BACKUP_DIR/$rel"
    local dest="$HOME/$rel"

    [ "$rel" = ".config" ] && continue

    if [ "${selected[$i]}" = "1" ]; then
      if [ ! -d "$src" ] || [ -z "$(ls -A "$src" 2>/dev/null)" ]; then
        recap_ris[$i]="— vuoto"
        ((vuoti++))
        continue
      fi
      ((step++))
      printf "  [%d] %-30s " "$step" "${CAT_NAMES[$i]}..."
      mkdir -p "$dest"
      local c=0
      for item in "$src"/*; do
        [ -e "$item" ] && cp -a "$item" "$dest/" 2>/dev/null && ((c++))
      done
      recap_ris[$i]="$c elementi"
      printf "\r  [%d] %-30s ${OK} %s\n" "$step" "${CAT_NAMES[$i]}" "$c elementi"
      ((mantieni_r++))
    else
      ((step++))
      printf "  [%d] %-30s " "$step" "${CAT_NAMES[$i]}..."
      local removed=0
      case "$rel" in
        .local/share/plasma/desktoptheme)
          [ -d "$dest" ] && for item in "$dest"/*; do
            [ -e "$item" ] || continue
            [[ "$(basename "$item")" =~ $KEEP_DESKTHEME ]] && continue
            rm -rf "$item" 2>/dev/null && ((removed++))
          done ;;
        .local/share/plasma/look-and-feel|.local/share/plasma/plasmoids|.local/share/plasma/splash)
          [ -d "$dest" ] && for item in "$dest"/*; do
            [ -e "$item" ] && rm -rf "$item" 2>/dev/null && ((removed++))
          done ;;
        .local/share/aurorae/themes)
          [ -d "$dest" ] && for item in "$dest"/*; do
            [ -e "$item" ] || continue
            [[ "$(basename "$item")" =~ $KEEP_AURORAE ]] && continue
            rm -rf "$item" 2>/dev/null && ((removed++))
          done ;;
        .local/share/color-schemes)
          [ -d "$dest" ] && for item in "$dest"/*; do
            [ -e "$item" ] || continue
            [[ "$(basename "$item")" =~ $KEEP_COLORS ]] && continue
            rm -rf "$item" 2>/dev/null && ((removed++))
          done ;;
        .local/share/icons)
          [ -d "$dest" ] && for item in "$dest"/*; do
            [ -e "$item" ] || continue
            [[ "$(basename "$item")" =~ $KEEP_ICONS ]] && continue
            rm -rf "$item" 2>/dev/null && ((removed++))
          done ;;
        .local/share/themes|.local/share/wallpapers|.local/share/kwin/scripts)
          [ -d "$dest" ] && for item in "$dest"/*; do
            [ -e "$item" ] && rm -rf "$item" 2>/dev/null && ((removed++))
          done ;;
      esac
      recap_ris[$i]="reset ($removed rimossi)"
      printf "\r  [%d] %-30s ${OK} %s\n" "$step" "${CAT_NAMES[$i]}" "reset ($removed rimossi)"
      ((default_r++))
    fi
  done

  echo ""
  echo -e "  ${PROC} arresto shell plasma..."
  kquitapp5 plasmashell 2>/dev/null; sleep 2
  killall -9 plasmashell 2>/dev/null; sleep 1

  echo ""
  echo -e "  ${PROC} configurazione..."

  local config_idx=10
  if [ "${selected[$config_idx]}" = "1" ]; then
    if [ -d "$BACKUP_DIR/.config" ] && [ -n "$(ls -A "$BACKUP_DIR/.config" 2>/dev/null)" ]; then
      local c=0
      for f in "$BACKUP_DIR/.config"/*; do
        [ -f "$f" ] && cp -a "$f" "$HOME/.config/" 2>/dev/null && ((c++))
      done
      recap_ris[$config_idx]="$c file"
      printf "  %-30s ${OK} %s\n" "layout e configurazione" "$c file"
      ((mantieni_r++))
    else
      recap_ris[$config_idx]="— vuoto"
      ((vuoti++))
    fi
  else
    local c=0
    for f in "${CONFIG_FILES[@]}"; do
      [ -f "$f" ] && rm -f "$f" 2>/dev/null && ((c++))
    done
    recap_ris[$config_idx]="reset ($c eliminati)"
    printf "  %-30s ${OK} %s\n" "layout e configurazione" "reset ($c eliminati)"
    ((default_r++))
  fi

  # ── APPLICAZIONE TEMI ──

  echo ""
  echo -e "  ${PROC} applicazione temi..."

  local meta="$BACKUP_DIR/.meta"

  # stili plasma (0)
  if [ "${selected[0]}" = "1" ]; then
    local style=""
    [ -f "$meta/desktoptheme" ] && style=$(cat "$meta/desktoptheme")
    if [ -z "$style" ] && [ -f "$meta/lookandfeel" ]; then
      local ls=$(cat "$meta/lookandfeel")
      case "$ls" in
        *.breezedark.desktop)    style="breeze-dark" ;;
        *.breezetwilight.desktop) style="breeze-light" ;;
        *.breeze.desktop)        style="default" ;;
        *.fedoradark.desktop)    style="breeze-dark" ;;
        *.fedora.desktop)        style="default" ;;
        *.fedoralight.desktop)   style="breeze-light" ;;
      esac
    fi
    [ -z "$style" ] && style="default"
    command -v plasma-apply-desktoptheme &>/dev/null && plasma-apply-desktoptheme "$style" 2>/dev/null
    printf "  %-30s %s\n" "stili plasma" "$style"
  else
    command -v plasma-apply-desktoptheme &>/dev/null && plasma-apply-desktoptheme default 2>/dev/null
    printf "  %-30s %s\n" "stili plasma" "Breeze"
  fi

  # look-and-feel (1)
  if [ "${selected[1]}" = "1" ]; then
    if [ -f "$meta/lookandfeel" ] && command -v plasma-apply-lookandfeel &>/dev/null; then
      local lf=$(cat "$meta/lookandfeel")
      plasma-apply-lookandfeel -a "$lf" 2>/dev/null
      printf "  %-30s %s\n" "look-and-feel" "$lf"
    else
      printf "  ${WARN} %-30s %s\n" "look-and-feel" "— vuoto"
    fi
  else
    command -v plasma-apply-lookandfeel &>/dev/null && plasma-apply-lookandfeel -a org.kde.breeze.desktop 2>/dev/null
    printf "  %-30s %s\n" "look-and-feel" "Breeze"
  fi

  # decorazioni finestre (4)
  if [ "${selected[4]}" = "1" ]; then
    if [ -f "$meta/decoration" ]; then
      local dc=$(cat "$meta/decoration")
      if [ -d "$HOME/.local/share/aurorae/themes/$dc" ]; then
        kwriteconfig6 --file "$HOME/.config/kwinrc" --group "org.kde.kdecoration2" --key theme "$dc" 2>/dev/null
        printf "  %-30s %s\n" "decorazioni finestre" "$dc"
      else
        kwriteconfig6 --file "$HOME/.config/kwinrc" --group "org.kde.kdecoration2" --key theme Breeze 2>/dev/null
        printf "  %-30s %s (non presente)\n" "decorazioni finestre" "$dc"
      fi
    else
      printf "  ${WARN} %-30s %s\n" "decorazioni finestre" "— vuoto"
    fi
  else
    kwriteconfig6 --file "$HOME/.config/kwinrc" --group "org.kde.kdecoration2" --key theme Breeze 2>/dev/null
    printf "  %-30s %s\n" "decorazioni finestre" "Breeze"
  fi

  # schemi colore (5)
  if [ "${selected[5]}" = "1" ]; then
    local sch=""
    local cst=""
    [ -f "$meta/colorscheme" ] && sch=$(cat "$meta/colorscheme")
    if [ -z "$sch" ] && [ -f "$meta/lookandfeel" ]; then
      local ls=$(cat "$meta/lookandfeel")
      case "$ls" in
        *.breezedark.desktop)    sch="BreezeDark" ;;
        *.breezetwilight.desktop) sch="BreezeLight" ;;
        *.fedoradark.desktop)    sch="BreezeDark" ;;
      esac
    fi
    [ -z "$sch" ] && sch="BreezeClassic"
    command -v plasma-apply-colorscheme &>/dev/null && plasma-apply-colorscheme "$sch" 2>/dev/null

    if [ -f "$meta/colors_values" ]; then
      local tmpf=$(mktemp)
      awk '/^\[Colors:/{f=1;next} /^\[/&&f{f=0;print;next} !f{print}' \
        "$HOME/.config/kdeglobals" > "$tmpf" 2>/dev/null
      cat "$meta/colors_values" >> "$tmpf"
      mv "$tmpf" "$HOME/.config/kdeglobals"
      cst=" (con colori custom)"
    fi
    printf "  %-30s %s%s\n" "schemi colore" "$sch" "$cst"
  else
    command -v plasma-apply-colorscheme &>/dev/null && plasma-apply-colorscheme BreezeClassic 2>/dev/null
    printf "  %-30s %s\n" "schemi colore" "BreezeClassic"
  fi

  # icone (6)
  if [ "${selected[6]}" = "1" ]; then
    if [ -f "$meta/icons" ]; then
      local ic=$(cat "$meta/icons")
      command -v plasma-apply-icons &>/dev/null && plasma-apply-icons "$ic" 2>/dev/null
      printf "  %-30s %s\n" "icone" "$ic"
    else
      printf "  ${WARN} %-30s %s\n" "icone" "— vuoto"
    fi
  else
    command -v plasma-apply-icons &>/dev/null && plasma-apply-icons breeze 2>/dev/null
    printf "  %-30s %s\n" "icone" "breeze"
  fi

  # safety check decorazione
  local dc_cur=$(grep -m1 "^theme=" "$HOME/.config/kwinrc" 2>/dev/null | cut -d= -f2-)
  if [ -n "$dc_cur" ] && [[ ! "$dc_cur" =~ ^[Bb]reeze ]]; then
    local found=0
    [ -d "$HOME/.local/share/aurorae/themes/$dc_cur" ] && found=1
    [ -d "/usr/share/aurorae/themes/$dc_cur" ] && found=1
    if [ $found -eq 0 ]; then
      kwriteconfig6 --file "$HOME/.config/kwinrc" --group "org.kde.kdecoration2" --key theme Breeze 2>/dev/null
      printf "  ${WARN} %-30s %s\n" "decorazione reset" "$dc_cur → Breeze (non presente)"
    fi
  fi

  # ── RECAP ──

  echo ""
  echo "$SEP"
  echo -e "  ${OK} restore completato"
  echo ""
  for ((i=0; i<CAT_COUNT; i++)); do
    local label="${CAT_NAMES[$i]}"
    local ris="${recap_ris[$i]}"
    [ -z "$ris" ] && continue
    if [ -n "$ris" ]; then
      printf "  %2d  %-25s %s\n" "$((i+1))" "$label" "$ris"
    fi
  done
  echo ""
  printf "  %d mantenuti, %d non mantenuti" "$mantieni_r" "$default_r"
  [ $vuoti -gt 0 ] && printf ", %d vuoti" "$vuoti"
  echo ""
  echo "$SEP"

  echo ""
  echo -e "  ${PROC} riavvio shell plasma..."
  kstart5 plasmashell 2>/dev/null &
  pause
}

# ─── MENU ───────────────────────────────────────────────

menu() {
  while true; do
    header
    echo ""
    printf "  ${CYAN}[1]${NC} %-9s %s\n" "backup"  "salva temi e configurazione attuali"
    printf "  ${CYAN}[2]${NC} %-9s %s\n" "reset"   "ripristina kde ai default breeze"
    printf "  ${CYAN}[3]${NC} %-9s %s\n" "restore" "ripristina selettivamente da backup"
    echo ""
    printf "  ${CYAN}[0]${NC} %-9s\n"    "exit"
    echo ""
    echo -n "  >> "
    read -r choice

    case "$choice" in
      backup|1)  backup ;;
      reset|2)   reset ;;
      restore|3) restore ;;
      exit|0|q)
        clear
        echo "plasmactl"
        echo "────────────────────────────────────────────"
        echo ""
        break
        ;;
      *) echo "" ; echo -e "  ${ERR} comando non valido" ; sleep 1 ;;
    esac
  done
}

check_prereqs
menu