#!/bin/bash

# ═══════════════════════════════════════════════════
#   DOCKFORGE  v0.1
#   Gestione Container Docker
# ═══════════════════════════════════════════════════

# ─── Safety ───
# NOTA: set -e NON usato — script interattivo, errori vanno gestiti
#       esplicitamente con if/|| per dare feedback all'utente.
set -uo pipefail

# ─── Trap pulizia background jobs ───
cleanup_bg() {
    local pids
    pids=$(jobs -p 2>/dev/null)
    [ -n "$pids" ] && kill $pids 2>/dev/null || true
}
trap cleanup_bg EXIT

# ─── ANSI Colors ───
C_CIANO=$'\033[0;36m'
C_VERDE=$'\033[0;32m'
C_ROSSO=$'\033[0;31m'
C_GIALLO=$'\033[1;33m'
C_BLU=$'\033[0;34m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_RESET=$'\033[0m'

# ═══════════════════════════════════════════════════
#   HELPERS
# ═══════════════════════════════════════════════════

header() {
    clear
    echo ""
    echo -e "  ${C_BOLD}${C_CIANO}DOCKFORGE${C_BOLD}  ${C_DIM}v0.1${C_RESET} — ${C_DIM}Gestione Container Docker${C_RESET}"
    echo ""
}

# ─── Horizontal rule ───
hr() {
    echo "  ═══════════════════════════════════════════════"
}

# ─── Coloured status message ───
status_msg() {
    local type="$1" msg="$2"
    case "$type" in
        OK)   echo -e "  ${C_VERDE}OK${C_RESET}   $msg" ;;
        FAIL) echo -e "  ${C_ROSSO}FAIL${C_RESET}  $msg" ;;
        WARN) echo -e "  ${C_GIALLO}WARN${C_RESET}  $msg" ;;
    esac
}

pause() {
    echo ""
    echo "  Premi Invio per tornare al menu"
    read -r
}

show_help() {
    local section=$1
    header
    echo ""
    case "$section" in
        menu)
            echo "  │ ${C_BOLD}[1]${C_RESET} Nuovo Container     │ crea e avvia un nuovo container"
            echo "  │ ${C_BOLD}[2]${C_RESET} Gestisci Container  │ lista, elimina container"
            echo "  │ ${C_BOLD}[3]${C_RESET} Gestisci Immagini   │ lista, elimina immagini"
            echo "  │ ${C_BOLD}[4]${C_RESET} Gestisci Volumi     │ crea, collega, elimina volumi"
            echo "  │ ${C_BOLD}[5]${C_RESET} Pulizia Completa    │ rimuove tutto (container, immagini, volumi)"
            echo "  │ ${C_BOLD}[6]${C_RESET} Esci                │ chiude DockForge"
            echo "  │ ${C_BOLD}[h]${C_RESET} Aiuto               │ mostra questa schermata"
            ;;
        container)
            echo "  │ ${C_BOLD}[ID/Nome]${C_RESET} Elimina  │ inserisci ID o nome per eliminare"
            echo "  │ ${C_BOLD}[D]${C_RESET} Cancella tutti   │ rimuove TUTTI i container"
            echo "  │ ${C_BOLD}[Enter]${C_RESET} Torna al menu"
            echo ""
            echo "  ── Suggerimento ──"
            echo "  I container fermi occupano spazio su disco"
            ;;
        image)
            echo "  │ ${C_BOLD}[ID/Repo]${C_RESET} Elimina  │ inserisci ID o repository"
            echo "  │ ${C_BOLD}[D]${C_RESET} Cancella tutte   │ rimuove TUTTE le immagini"
            echo "  │ ${C_BOLD}[Enter]${C_RESET} Torna al menu"
            echo ""
            echo "  ── Suggerimento ──"
            echo "  docker rmi rimuove solo se nessun container usa l'immagine"
            ;;
        volume)
            echo "  │ ${C_BOLD}[C]${C_RESET} Crea volume       │ nuovo volume con nome personalizzato"
            echo "  │ ${C_BOLD}[D]${C_RESET} Cancella tutti    │ rimuove tutti i volumi NON in uso"
            echo "  │ ${C_BOLD}[N°]${C_RESET} Seleziona        │ gestisci volume (rimuovi, collega)"
            echo "  │ ${C_BOLD}[Enter]${C_RESET} Torna al menu"
            echo ""
            echo "  ── Da dentro volume ──"
            echo "  │ ${C_BOLD}[R]${C_RESET} Rimuovi volume      │ elimina volume (se in uso, blocca)"
            echo "  │ ${C_BOLD}[A]${C_RESET} Collega a container  │ monta volume su un container"
            echo ""
            echo "  ── Suggerimento ──"
            echo "  I volumi persistono anche dopo docker rm"
            ;;
        create)
            echo "  Creazione guidata di un nuovo container:"
            echo ""
            echo "  ── Passi ──"
            echo "  Step 1 — Scegli la distribuzione Linux"
            echo "  Step 2 — Configura: shell, utente, rete, nome, pacchetti, volume"
            echo "  Step 3 — Riepilogo e avvio"
            echo ""
            echo "  ── Durante la configurazione ──"
            echo "  │ ${C_BOLD}[X]${C_RESET} Modifica  │ torna all'inizio della configurazione"
            echo "  │ ${C_BOLD}[q]${C_RESET} Annulla   │ torna al menu principale"
            ;;
    esac
    echo ""
    echo "  Premi Invio per continuare"
    read -r
}

# ─── Progress bar wizard ───
progress_bar() {
    local step=$1
    if [ "$step" = "1" ]; then
        echo "  ── [1/3] ──  Distro  ─────────────────────────────────"
    elif [ "$step" = "2" ]; then
        echo -e "  ── ${C_VERDE}OK${C_RESET}  Distro  ── [2/3] ──  Config  ─────────────────────"
    else
        echo -e "  ── ${C_VERDE}OK${C_RESET}  Distro  ── ${C_VERDE}OK${C_RESET}  Config  ── [3/3] ──  Avvia  ───────────"
    fi
}

spinner() {
    local pid=$1 base="$2"
    local spin=('-' '\' '|' '/')
    trap "kill $pid 2>/dev/null; printf '\n'; return 1" INT
    while kill -0 "$pid" 2>/dev/null; do
        for s in "${spin[@]}"; do
            printf "\r  [%s] Build ${C_CIANO}%s${C_RESET} ..." "$s" "$base"
            sleep 0.15
        done
    done
    trap - INT
    wait "$pid"; local rc=$?
    if [ "$rc" -eq 0 ]; then
        printf "\r  ${C_VERDE}OK${C_RESET}   Build ${C_CIANO}%s${C_RESET}\033[K\n" "$base"
    else
        printf "\r  ${C_ROSSO}FAIL${C_RESET}  Build %s fallito\033[K\n" "$base"
    fi
    return $rc
}

# ─── Stampa menu distro (riusata) ───
menu_distro() {
    echo "  Scegli l'immagine:"
    echo ""
    echo "  [1]  Ubuntu        [8]   Rocky Linux"
    echo "  [2]  Debian        [9]   AlmaLinux"
    echo "  [3]  Kali Linux    [10]  openSUSE"
    echo "  [4]  Alpine Linux  [11]  Linux Mint"
    echo "  [5]  Arch Linux    [12]  Parrot OS"
    echo "  [6]  Fedora        [13]  Black Arch"
    echo "  [7]  Oracle Linux  [14]  Red Hat"
    echo ""
    echo "  [Enter]  Torna al menu"
    echo ""
}

# ═══════════════════════════════════════════════════
#   DISTRO HELPERS
# ═══════════════════════════════════════════════════

distro_name() {
    case "$1" in
         1) echo "Ubuntu" ;;       2) echo "Debian" ;;
         3) echo "Kali Linux" ;;   4) echo "Alpine Linux" ;;
         5) echo "Arch Linux" ;;   6) echo "Fedora" ;;
         7) echo "Oracle Linux" ;; 8) echo "Rocky Linux" ;;
         9) echo "AlmaLinux" ;;   10) echo "openSUSE" ;;
        11) echo "Linux Mint" ;;  12) echo "Parrot OS" ;;
        13) echo "Black Arch" ;;  14) echo "Red Hat" ;;   *) echo "" ;;
    esac
}

distro_image() {
    case "$1" in
         1) echo "ubuntu:latest" ;;               2) echo "debian:latest" ;;
         3) echo "kalilinux/kali-rolling" ;;      4) echo "alpine:latest" ;;
         5) echo "archlinux:latest" ;;            6) echo "fedora:latest" ;;
         7) echo "oraclelinux:9" ;;               8) echo "rockylinux:9" ;;
         9) echo "almalinux:9" ;;                10) echo "opensuse/leap:latest" ;;
        11) echo "linuxmintd/mint22-amd64:latest" ;;     12) echo "parrotsec/core:latest" ;;
        13) echo "blackarchlinux/blackarch:latest" ;;
        14) echo "redhat/ubi9:latest" ;;  *) echo "" ;;
    esac
}

# Restituisce eval-able string — niente variabili globali
pkg_manager_init() {
    case "$1" in
        1|2|11)  # Ubuntu / Debian / Mint — coding
            echo "PKG_UPDATE='apt-get update'"
            echo "PKG_INSTALL='DEBIAN_FRONTEND=noninteractive apt-get install -y'"
            echo "PKG_CLEAN='rm -rf /var/lib/apt/lists/*'"
            echo "PKG_LIST='git build-essential python3 python3-pip'"
            echo "PKG_DISPLAY='git build-essential python3 python3-pip'"
            ;;
        3|12)  # Kali / Parrot — cybersec
            echo "PKG_UPDATE='apt-get update'"
            echo "PKG_INSTALL='DEBIAN_FRONTEND=noninteractive apt-get install -y'"
            echo "PKG_CLEAN='rm -rf /var/lib/apt/lists/*'"
            echo "PKG_LIST='git build-essential python3 python3-pip wget ufw net-tools'"
            echo "PKG_DISPLAY='git build-essential python3 python3-pip wget ufw net-tools'"
            ;;
        4)  # Alpine — coding
            echo "PKG_UPDATE='apk update'"
            echo "PKG_INSTALL='apk add --no-cache'"
            echo "PKG_CLEAN='rm -rf /var/cache/apk/*'"
            echo "PKG_LIST='git build-base python3 py3-pip'"
            echo "PKG_DISPLAY='git build-base python3 py3-pip'"
            ;;
        5)  # Arch — coding
            echo "PKG_UPDATE='pacman -Sy'"
            echo "PKG_INSTALL='pacman -S --noconfirm'"
            echo "PKG_CLEAN='pacman -Scc --noconfirm 2>/dev/null || true'"
            echo "PKG_LIST='git base-devel python python-pip'"
            echo "PKG_DISPLAY='git base-devel python python-pip'"
            ;;
        13)  # Black Arch — cybersec
            echo "PKG_UPDATE='pacman -Sy'"
            echo "PKG_INSTALL='pacman -S --noconfirm'"
            echo "PKG_CLEAN='pacman -Scc --noconfirm 2>/dev/null || true'"
            echo "PKG_LIST='git base-devel python python-pip wget ufw net-tools'"
            echo "PKG_DISPLAY='git base-devel python python-pip wget ufw net-tools'"
            ;;
        6|7|8|9|14)  # Fedora / Oracle / Rocky / Alma / Red Hat — coding
            echo "PKG_UPDATE='dnf check-update 2>/dev/null || true'"
            echo "PKG_INSTALL='dnf install -y --setopt=strict=0'"
            echo "PKG_CLEAN='dnf clean all 2>/dev/null || true'"
            echo "PKG_LIST='git gcc gcc-c++ make python3 python3-pip'"
            echo "PKG_DISPLAY='git gcc g++ make python3 python3-pip'"
            ;;
        10)  # openSUSE — coding
            echo "PKG_UPDATE='zypper refresh'"
            echo "PKG_INSTALL='zypper install -y'"
            echo "PKG_CLEAN='zypper clean 2>/dev/null || true'"
            echo "PKG_LIST='git gcc gcc-c++ make python3 python3-pip'"
            echo "PKG_DISPLAY='git gcc g++ make python3 python3-pip'"
            ;;
    esac
}

sudo_group_for() {
    case "$1" in
        4|5|6|7|8|9|10|13|14) echo "wheel" ;;
        *)                  echo "sudo" ;;
    esac
}

# Pacchetti sempre installati in ogni container
default_pkgs() {
    case "$1" in
        1|2|3|11|12) echo "nano procps net-tools bash zsh zip unzip sudo curl" ;;
        4)           echo "nano procps net-tools bash zsh zip unzip sudo curl" ;;
        5|13)        echo "nano procps-ng net-tools bash zsh zip unzip sudo curl" ;;
        6|7|8|9|14)  echo "nano procps-ng net-tools bash zsh zip unzip sudo curl" ;;
        10)          echo "nano procps net-tools bash zsh zip unzip sudo curl" ;;
    esac
}

# Pacchetti terminale (clear, ncurses) — extra non coperti da default_pkgs
pkg_term() {
    case "$1" in
        4|6|7|8|9|14) echo "ncurses" ;;
    esac
}

# ═══════════════════════════════════════════════════
#   CONTAINER ENGINE (tutti i comandi con error check)
# ═══════════════════════════════════════════════════

docker_rm_force() {
    local name=$1
    docker rm -f "$name" > /dev/null 2>&1 || true
}

docker_generate_dockerfile() {
    local dir=$1 idx=$2 user=$3 use_extra=$4 pass=$5 shell=$6 fix_hostname=${7:-false}
    local df="$dir/Dockerfile"
    local base_img sudo_group
    base_img=$(distro_image "$idx")
    sudo_group=$(sudo_group_for "$idx")
    eval "$(pkg_manager_init "$idx")"

    > "$df"

    printf '%s\n\n' "FROM $base_img" >> "$df"

    if [ "$use_extra" = true ]; then
        printf '%s\n\n' "RUN $PKG_UPDATE && $PKG_INSTALL $PKG_LIST && $PKG_CLEAN" >> "$df"
    fi

    local base_pkgs extra_shell=""
    base_pkgs="$(default_pkgs "$idx") $(pkg_term "$idx")"
    base_pkgs="${base_pkgs% }"
    case "$shell" in
        /bin/zsh)       extra_shell="zsh" ;;
        /usr/bin/fish)  extra_shell="fish" ;;
        /bin/ksh)       extra_shell="ksh" ;;
        /bin/dash)      extra_shell="dash" ;;
        /bin/bash)      [ "$idx" = "4" ] && extra_shell="bash" ;;
    esac
    [ -n "$extra_shell" ] && base_pkgs="$base_pkgs $extra_shell"
    printf '%s\n\n' "RUN $PKG_UPDATE && $PKG_INSTALL $base_pkgs && $PKG_CLEAN" >> "$df"

    if [ -n "$user" ]; then
        local uid gid
        uid=$(shuf -i 1001-9999 -n 1)
        gid=$(shuf -i 1001-9999 -n 1)
        printf '%s\n' "ARG USERNAME=$user" >> "$df"
        printf '%s\n' "ARG UID=$uid" >> "$df"
        printf '%s\n\n' "ARG GID=$gid" >> "$df"

        if [ "$idx" = "4" ]; then
            printf '%s\n' "RUN adduser -D -s $shell -u \$UID \$USERNAME" >> "$df"
            printf '%s\n' "RUN addgroup \$USERNAME $sudo_group" >> "$df"
            printf '%s\n\n' "RUN echo '%${sudo_group} ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers" >> "$df"
        else
            printf '%s\n' "RUN groupadd --force -g \$GID \$USERNAME" >> "$df"
            printf '%s\n' "RUN useradd --no-log-init -m -u \$UID -g \$GID -s $shell \$USERNAME" >> "$df"
            printf '%s\n' "RUN groupadd -f $sudo_group && usermod -aG $sudo_group \$USERNAME" >> "$df"
            printf '%s\n\n' "RUN mkdir -p /etc/sudoers.d && echo \"\$USERNAME ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/\$USERNAME && chmod 440 /etc/sudoers.d/\$USERNAME" >> "$df"
        fi

        if [ -n "$pass" ]; then
            printf '%s\n' 'RUN --mount=type=secret,id=password sh -c '"'"'echo "$USERNAME:$(cat /run/secrets/password)" | chpasswd'"'" >> "$df"
            printf '\n' >> "$df"
        fi

        printf '%s\n' "USER \$USERNAME" >> "$df"
        printf '%s\n' "WORKDIR /home/\$USERNAME" >> "$df"
    else
        printf '%s\n' "USER root" >> "$df"
        printf '%s\n' "WORKDIR /root" >> "$df"
        printf 'SHELL ["%s", "-c"]\n\n' "$shell" >> "$df"
    fi

    if [ "$fix_hostname" = true ]; then
        case "$shell" in
            /bin/bash|/bin/zsh|/bin/ksh)
                if [ -n "$user" ]; then
                    local rc_path="/home/\$USERNAME"
                    case "$shell" in
                        /bin/zsh) rc_path="$rc_path/.zshrc" ;;
                        *)       rc_path="$rc_path/.bashrc" ;;
                    esac
                else
                    local rc_path="/root"
                    case "$shell" in
                        /bin/zsh) rc_path="$rc_path/.zshrc" ;;
                        *)       rc_path="$rc_path/.bashrc" ;;
                    esac
                fi
                printf '%s\n' "RUN cat >> $rc_path << 'DOCKFORGE_RC'" >> "$df"
                printf '%s\n' 'if [ -n "$CONTAINER_NAME" ] && [ "$CONTAINER_NAME" != "$(hostname 2>/dev/null)" ]; then' >> "$df"
                printf '%s\n' '  if [ -n "$ZSH_VERSION" ]; then' >> "$df"
                printf '%s\n' '    PROMPT="${PROMPT//%m/$CONTAINER_NAME}"' >> "$df"
                printf '%s\n' '    PROMPT="${PROMPT//%M/$CONTAINER_NAME}"' >> "$df"
                printf '%s\n' '  else' >> "$df"
                printf '%s\n' '    PS1="${PS1//\\h/$CONTAINER_NAME}"' >> "$df"
                printf '%s\n' '    PS1="${PS1//\\H/$CONTAINER_NAME}"' >> "$df"
                printf '%s\n' '  fi' >> "$df"
                printf '%s\n' 'fi' >> "$df"
                printf '%s\n' 'DOCKFORGE_RC' >> "$df"
                ;;
            /bin/dash)
                if [ -n "$user" ]; then
                    local rc_path="/home/\$USERNAME/.profile"
                else
                    local rc_path="/root/.profile"
                fi
                printf '%s\n' "RUN cat >> $rc_path << 'DOCKFORGE_RC'" >> "$df"
                printf '%s\n' 'if [ -n "$CONTAINER_NAME" ] && [ "$CONTAINER_NAME" != "$(hostname 2>/dev/null)" ]; then' >> "$df"
                printf '%s\n' '  PS1="$CONTAINER_NAME# "' >> "$df"
                printf '%s\n' 'fi' >> "$df"
                printf '%s\n' 'DOCKFORGE_RC' >> "$df"
                ;;
            /usr/bin/fish)
                if [ -n "$user" ]; then
                    local rc_path="/home/\$USERNAME/.config/fish/config.fish"
                else
                    local rc_path="/root/.config/fish/config.fish"
                fi
                local rc_dir="${rc_path%/*}"
                printf '%s\n' "RUN mkdir -p $rc_dir && cat >> $rc_path << 'DOCKFORGE_RC'" >> "$df"
                printf '%s\n' 'if set -q CONTAINER_NAME; and test "$CONTAINER_NAME" != (hostname 2>/dev/null)' >> "$df"
                printf '%s\n' '    function fish_prompt' >> "$df"
                printf '%s\n' "        printf '%s@%s %s%s%s> ' (whoami) \$CONTAINER_NAME (set_color green) (prompt_pwd) (set_color normal)" >> "$df"
                printf '%s\n' '    end' >> "$df"
                printf '%s\n' 'end' >> "$df"
                printf '%s\n' 'DOCKFORGE_RC' >> "$df"
                ;;
        esac
    fi

    printf '\n%s\n' 'CMD ["sleep", "infinity"]' >> "$df"
}

docker_build_with_spinner() {
    local dir=$1 tag=$2 base_image=$3 pass=${4:-}
    local tmp rc pass_file=""
    echo ""
    tmp=$(mktemp /tmp/dockforge_build_XXXXX.log 2>/dev/null)

    if [ -n "$pass" ]; then
        pass_file=$(mktemp /tmp/dockforge_pass_XXXXX 2>/dev/null)
        [ -n "$pass_file" ] && printf '%s' "$pass" > "$pass_file"
    fi

    (
        if [ -n "$pass_file" ] && [ -f "$pass_file" ]; then
            DOCKER_BUILDKIT=1 docker build --pull -t "$tag" --secret id=password,src="$pass_file" "$dir"
        else
            docker build --pull -t "$tag" "$dir"
        fi
    ) > "$tmp" 2>&1 &
    local pid=$!

    spinner "$pid" "$base_image"
    rc=$?

    rm -f "$pass_file"
    LOG_BUF+=$(<"$tmp")$'\n'
    rm -f "$tmp"
    return $rc
}

cleanup_dockerfile_dir() {
    local dir=$1
    [ -n "$dir" ] && [ -d "$dir" ] && rm -rf "$dir"
    local parent="${dir%/*}"
    [ -n "$parent" ] && [ -d "$parent" ] && rmdir "$parent" 2>/dev/null || true
    return 0
}

# ═══════════════════════════════════════════════════
#   PAGES
# ═══════════════════════════════════════════════════

page_welcome() {
    while true; do
        clear
        header
        echo "  ${C_BOLD}[1]${C_RESET}  Nuovo Container"
        echo "  ${C_BOLD}[2]${C_RESET}  Gestisci Container"
        echo "  ${C_BOLD}[3]${C_RESET}  Gestisci Immagini"
        echo "  ${C_BOLD}[4]${C_RESET}  Gestisci Volumi"
        echo "  ${C_BOLD}[5]${C_RESET}  Pulizia Completa"
        echo "  ${C_BOLD}[6]${C_RESET}  Esci"
        echo "  ${C_BOLD}[h]${C_RESET}  Aiuto"
        echo ""
        echo -n "  Seleziona [1-6, h]: "
        read -r scelta
        case "$scelta" in
            1) page_new_container ;;
            2) page_manage_containers ;;
            3) page_manage_images ;;
            4) page_manage_volumes ;;
            5) page_full_cleanup ;;
            6) clear; exit 0 ;;
            [Hh]) show_help menu ;;
            *) ;;
        esac
    done
}

page_full_cleanup() {
    while true; do
        header
        status_msg WARN "Pulizia Completa"
        echo ""
        echo "  Cosa verrà rimosso:"
        echo "    - Container arrestati"
        echo "    - Reti inutilizzate"
        echo "    - Cache di build"
        echo "    - Volumi non utilizzati"
        echo "    - Tutte le immagini"
        echo ""
        status_msg WARN "Questa operazione è irreversibile."
        echo ""
        echo -n "  Procedere [S/n]: "
        read -r confirm

        if [[ "$confirm" =~ ^[Ss]$ ]]; then
            LOG_BUF=""

            clear
            header
            status_msg WARN "Pulizia Completa"
            echo ""

            # Fase 1: arresto container
            local running rm_out rmi_out prune_out
            echo -n "  Arresto container...                     "
            running=$(docker ps -q)
            if [ -n "$running" ]; then
                rm_out=$(docker stop $running 2>&1)
            else
                rm_out=""
            fi
            LOG_BUF+="════════════════════════════════════════════════"$'\n'
            LOG_BUF+="  ARRESTO CONTAINER"$'\n'
            LOG_BUF+="════════════════════════════════════════════════"$'\n'
            LOG_BUF+="${rm_out:-(nessuno attivo)}"$'\n'
            LOG_BUF+=$'\n'
            local n_stop=$(echo "$rm_out" | grep -c .)
            status_msg OK "$n_stop fermati"

            # Fase 2: rimozione container
            echo -n "  Rimozione container...                    "
            rm_out=$(docker rm -f $(docker ps -aq) 2>&1)
            LOG_BUF+="════════════════════════════════════════════════"$'\n'
            LOG_BUF+="  RIMOZIONE CONTAINER"$'\n'
            LOG_BUF+="════════════════════════════════════════════════"$'\n'
            LOG_BUF+="${rm_out}"$'\n'
            LOG_BUF+=$'\n'
            local n_rm=$(echo "$rm_out" | grep -c .)
            [ "$rm_out" = "" ] && n_rm=0
            status_msg OK "$n_rm rimossi"

            # Fase 3: rimozione immagini
            echo -n "  Rimozione immagini...                     "
            rmi_out=$(docker rmi -f $(docker images -q) 2>&1)
            LOG_BUF+="════════════════════════════════════════════════"$'\n'
            LOG_BUF+="  RIMOZIONE IMMAGINI"$'\n'
            LOG_BUF+="════════════════════════════════════════════════"$'\n'
            LOG_BUF+="${rmi_out}"$'\n'
            LOG_BUF+=$'\n'
            local n_img=$(echo "$rmi_out" | grep -c "Deleted:")
            status_msg OK "$n_img rimosse"

            # Fase 4: prune profondo
            echo -n "  Pulizia profondata (cache/reti/volumi)...  "
            prune_out=$(docker system prune -a --volumes -f 2>&1)
            LOG_BUF+="════════════════════════════════════════════════"$'\n'
            LOG_BUF+="  PULIZIA PROFONDATA"$'\n'
            LOG_BUF+="════════════════════════════════════════════════"$'\n'
            LOG_BUF+="${prune_out}"$'\n'
            status_msg OK "fatto"

            echo ""
            status_msg OK "Pulizia completata con successo"
        else
            echo ""
            echo "  Pulizia annullata"
            pause
            return
        fi

        if [ -n "$LOG_BUF" ]; then
            echo ""
            read -r -p "  [L] Log  [Invio]: " show_logs
            if [[ "$show_logs" =~ ^[Ll]$ ]]; then
                clear; header
                echo "  Log Pulizia"
                echo ""
                echo "$LOG_BUF" | while IFS= read -r log_line; do
                    echo "  $log_line"
                done
                echo ""
                pause
            fi
        fi
        return
    done
}

page_new_container() {
    local idx_distro= nome_distro= docker_image=
    local extra_choice= use_extra=false
    local native_shell= shell=
    local username= password=
    local container_name= use_net_host=false fix_hostname=false
    local use_volume=false vol_mount_point="" vol_name=""
    local step=1

    while true; do
        # ─── Step 1: Distro ───
        if [ "$step" = "1" ]; then
            clear; header
            progress_bar 1
            echo ""
            menu_distro
            echo -ne "  Distro ${C_BLU}[1-14]${C_RESET}: "
            read -r idx_distro

            [ -z "$idx_distro" ] && return
            [[ "$idx_distro" =~ ^[Xx]$ ]] && return

            if ! [[ "$idx_distro" =~ ^(1[0-4]|[1-9])$ ]]; then
                status_msg FAIL "Seleziona 1-14"
                sleep 1
                continue
            fi

            nome_distro=$(distro_name "$idx_distro")
            docker_image=$(distro_image "$idx_distro")
            step=2
        fi

        # ─── Step 2: Config ───
        if [ "$step" = "2" ]; then
            # Reset per ripetizione
            extra_choice=S; use_extra=false
            native_shell="/bin/bash"; [ "$idx_distro" = "4" ] && native_shell="/bin/sh"
            shell="$native_shell"
            username=; password=
            container_name=
            use_net_host=false
            fix_hostname=false
            use_volume=false; vol_mount_point=""; vol_name=""

            local phase=0
            while true; do
                clear
                header
                progress_bar 2

                # Shell
                local sh_hd="  ── Shell ──"
                [ "$phase" = "0" ] && sh_hd="  ${C_BOLD}▸ Shell${C_RESET}"
                echo "$sh_hd"
                if [ "$phase" = "0" ]; then
                    local options=("bash" "sh" "zsh" "fish" "ksh" "dash")
                    local values=("/bin/bash" "/bin/sh" "/bin/zsh" "/usr/bin/fish" "/bin/ksh" "/bin/dash")
                    local idx=0; local i
                    for i in "${!values[@]}"; do
                        [ "${values[$i]}" = "$shell" ] && idx=$i
                    done
                    local opt_count=${#options[@]}

                    local old_stty=$(stty -g 2>/dev/null)
                    stty raw -echo 2>/dev/null

                    for i in "${!options[@]}"; do
                        echo -ne "\r     $( [ $i -eq $idx ] && printf "●" || echo "○" ) ${options[$i]}\033[K"
                        [ $i -lt $((opt_count - 1)) ] && echo -ne "\r\n"
                    done

                    while true; do
                        local key
                        IFS= read -r -n1 key
                        if [ "$key" = $'\033' ]; then
                            read -r -n2 key2
                            key+="$key2"
                        fi
                        case "$key" in
                            $'\033[A') [ $idx -gt 0 ] && idx=$((idx - 1)) ;;
                            $'\033[B') [ $idx -lt $((opt_count - 1)) ] && idx=$((idx + 1)) ;;
                            $'\r'|$'\n'|'') break ;;
                        esac
                        printf "\033[%dA" $((opt_count - 1))
                        for i in "${!options[@]}"; do
                            echo -ne "\r     $( [ $i -eq $idx ] && printf "●" || echo "○" ) ${options[$i]}\033[K"
                            [ $i -lt $((opt_count - 1)) ] && echo -ne "\r\n"
                        done
                    done

                    echo -ne "\r\n"
                    stty "$old_stty" 2>/dev/null
                    shell="${values[$idx]}"
                    phase=1; continue
                fi
                local s=$(basename "$shell")
                echo "     $( [ "$s" = "bash" ] && echo "●" || echo "○" ) bash"
                echo "     $( [ "$s" = "sh" ] && echo "●" || echo "○" ) sh"
                echo "     $( [ "$s" = "zsh" ] && echo "●" || echo "○" ) zsh"
                echo "     $( [ "$s" = "fish" ] && echo "●" || echo "○" ) fish"
                echo "     $( [ "$s" = "ksh" ] && echo "●" || echo "○" ) ksh"
                echo "     $( [ "$s" = "dash" ] && echo "●" || echo "○" ) dash"
                echo ""

                # Profilo
                local us_hd="  ── Profilo Utente ──"
                [ "$phase" = "1" ] && us_hd="  ${C_BOLD}▸ Profilo Utente${C_RESET}"
                echo -e "$us_hd"
                if [ "$phase" = "1" ]; then
                    read -r -p "     ├─ Utente? [S/n]: " user_choice
                    if [[ "$user_choice" =~ ^[Nn]$ ]]; then
                        username=; password=; phase=2; continue
                    fi
                    read -r -p "     ├─ Nome: " username
                    if [ -z "$username" ]; then return; fi
                    read -r -p "     └─ Password? [S/n]: " pass_choice
                    if [[ ! "$pass_choice" =~ ^[Nn]$ ]]; then
                        read -r -s -p "        Password: " password
                        echo ""
                        if [ -z "$password" ]; then return; fi
                    fi
                    phase=2; continue
                fi
                if [ -n "$username" ]; then
                    echo "     ├─ Nome:      $username"
                    local pw=$( [ -n "$password" ] && echo "********" || echo "(nessuna)" )
                    echo "     └─ Password:  $pw"
                else
                    echo -e "     └─ ${C_DIM}(utente non creato)${C_RESET}"
                fi
                echo ""

                # Rete
                local re_hd="  ── Rete Host ──"
                [ "$phase" = "2" ] && re_hd="  ${C_BOLD}▸ Rete Host${C_RESET}"
                echo -e "$re_hd"
                if [ "$phase" = "2" ]; then
                    read -r -p "     └─ Abilita [S/n]: " net_choice
                    net_choice="${net_choice:-S}"
                    use_net_host=false; [[ ! "$net_choice" =~ ^[Nn]$ ]] && use_net_host=true
                    if [ "$use_net_host" = true ]; then
                        phase=21
                    else
                        fix_hostname=false
                        phase=3
                    fi
                    continue
                fi
                local net=$( [ "$use_net_host" = true ] && echo "${C_VERDE}[SI]${C_RESET} / no" || echo "si / ${C_VERDE}[NO]${C_RESET}" )
                echo -e "     └─ Abilita:   $net"
                echo ""

                # Mostra nome container nel prompt
                local fx_hd="  ── Mostra nome container nel prompt ──"
                [ "$phase" = "21" ] && fx_hd="  ${C_BOLD}▸ Mostra nome container nel prompt${C_RESET}"
                if [ "$use_net_host" = true ]; then
                    echo "$fx_hd"
                    if [ "$phase" = "21" ]; then
                        read -r -p "     └─ Mostra [S/n]: " fx_choice
                        fx_choice="${fx_choice:-S}"
                        fix_hostname=false; [[ ! "$fx_choice" =~ ^[Nn]$ ]] && fix_hostname=true
                        phase=3; continue
                    fi
                    local fx=$( [ "$fix_hostname" = true ] && echo "${C_VERDE}[SI]${C_RESET} / no" || echo "si / ${C_VERDE}[NO]${C_RESET}" )
                    echo -e "     └─ Mostra:   $fx"
                fi
                echo ""

                # Nome Container
                local nm_hd="  ── Nome Container ──"
                [ "$phase" = "3" ] && nm_hd="  ${C_BOLD}▸ Nome Container${C_RESET}"
                echo -e "$nm_hd"
                if [ "$phase" = "3" ]; then
                    read -r -p "     └─ Nome: " raw_name
                    container_name=$(echo "$raw_name" | tr ' ' '-' | tr -cd 'a-zA-Z0-9_.-')
                    if [ -z "$container_name" ]; then return; fi
                    if [ "$raw_name" != "$container_name" ]; then
                        status_msg WARN "Sanitizzato: '$raw_name' → '$container_name'"
                        sleep 1
                    fi
                    phase=4; continue
                fi
                echo -e "     └─ Nome:      ${C_CIANO}$container_name${C_RESET}"
                echo ""

                # Extra
                local ex_hd="  ── Pacchetti extra ──"
                [ "$phase" = "4" ] && ex_hd="  ${C_BOLD}▸ Pacchetti extra${C_RESET}"
                echo -e "$ex_hd"
                if [ "$phase" = "4" ]; then
                    read -r -p "     └─ Installa [S/n]: " extra_choice
                    extra_choice="${extra_choice:-S}"
                    if [[ "$extra_choice" =~ ^[Nn]$ ]]; then
                        use_extra=false
                    elif [[ "$extra_choice" =~ ^[Ss]$ ]]; then
                        use_extra=true
                    else
                        status_msg FAIL "Rispondi S o n"; sleep 1; continue
                    fi
                    phase=5; continue
                fi
                echo -e "     └─ $([ "$use_extra" = true ] && echo "${C_VERDE}Sì${C_RESET}" || echo "No")"
                echo ""

                # Volume
                if [ "$phase" = "5" ]; then
                    read -r -p "  Creare volume persistente [S/n]: " vol_choice
                    vol_choice="${vol_choice:-S}"
                    if [[ ! "$vol_choice" =~ ^[Nn]$ ]]; then
                        use_volume=true
                        echo "     Punto di mount: [1] /data  [2] /home/${username:-user}"
                        read -r -p "     └─ Scelta [1-2]: " mp_choice
                        vol_mount_point="/data"
                        [ "$mp_choice" = "2" ] && vol_mount_point="/home/${username:-user}"
                        vol_name="${container_name}"
                    else
                        use_volume=false
                    fi
                    phase=6; continue
                fi
                echo -e "     └─ Volume persistente path: $([ "$use_volume" = true ] && echo "${C_CIANO}$vol_mount_point${C_RESET}" || echo "${C_DIM}(nessuno)${C_RESET}")"
                echo ""

                # Conferma — va direttamente in esecuzione
                hr
                echo "     Shell:     $(basename $shell)"
                echo "     Utente:    ${username:-root}"
                echo "     Extra:     $([ "$use_extra" = true ] && echo "Sì" || echo "No")"
                if [ "$use_net_host" = true ]; then
                    if [ "$fix_hostname" = true ]; then
                        echo "     Hostname:  $container_name"
                    else
                        echo "     Host:      $(hostname)"
                    fi
                    echo -e "     Rete:      ${C_VERDE}Sì${C_RESET}"
                    echo "     Nome:      $container_name"
                fi
                echo -e "     Volume:    $([ "$use_volume" = true ] && echo "${C_CIANO}$vol_mount_point${C_RESET}" || echo "${C_DIM}(nessuno)${C_RESET}")"
                echo -e "  ${C_BOLD}[Invio]${C_RESET} Avvia  │  ${C_BOLD}[X]${C_RESET} Modifica  │  ${C_BOLD}${C_ROSSO}[q]${C_RESET}${C_BOLD}${C_RESET} Annulla"
                read -r conferma
                [[ "$conferma" =~ ^[Xx]$ ]] && { phase=0; continue; }
                [[ "$conferma" =~ ^[Qq]$ ]] && return
                [ -z "$conferma" ] || continue

                # ─── Esecuzione ───
                clear; header
                local df_dir="$HOME/Dockerfile/$container_name"
                LOG_BUF=""
                local setup_ok=true

                # Dockerfile
                LOG_BUF+=$'\n\n'
                LOG_BUF+="╔═══════════════════════════════════════════"$'\n'
                LOG_BUF+="║  DOCKERFILE"$'\n'
                LOG_BUF+="╚═══════════════════════════════════════════"$'\n'
                LOG_BUF+=$'\n'

                mkdir -p "$df_dir" || { status_msg FAIL "Impossibile creare $df_dir"; setup_ok=false; }

                if [ "$setup_ok" = true ]; then
                    docker_generate_dockerfile "$df_dir" "$idx_distro" "$username" "$use_extra" "$password" "$shell" "$fix_hostname"
                    LOG_BUF+="$(<"$df_dir/Dockerfile")"$'\n'
                fi

                # Build
                LOG_BUF+=$'\n\n'
                LOG_BUF+="╔═══════════════════════════════════════════"$'\n'
                LOG_BUF+="║  BUILD"$'\n'
                LOG_BUF+="╚═══════════════════════════════════════════"$'\n'
                LOG_BUF+=$'\n'

                local build_tag=$(shuf -i 100000-999999 -n 1)
                if [ "$setup_ok" = true ]; then
                    if ! docker_build_with_spinner "$df_dir" "${docker_image%:*}:${build_tag}" "$docker_image" "$password"; then
                        status_msg FAIL "Build fallito"
                        setup_ok=false
                    fi
                fi

                # Clean temp
                cleanup_dockerfile_dir "$df_dir"

                # Run
                if [ "$setup_ok" = true ]; then
                    docker_rm_force "$container_name"
                    local net_opt="" host_opt="" vol_opt=""
                    [ "$use_net_host" = true ] && net_opt="--network host"
                    if [ "$use_net_host" = false ] || [ "$fix_hostname" = true ]; then
                        host_opt="--hostname $container_name"
                    fi
                    if [ "$use_volume" = true ]; then
                        docker volume create "$vol_name" > /dev/null 2>&1 || true
                        vol_opt="-v ${vol_name}:${vol_mount_point}"
                    fi
                    local output
                    output=$(docker run -d $net_opt --name "$container_name" $host_opt $vol_opt -e CONTAINER_NAME="$container_name" "${docker_image%:*}:${build_tag}" 2>&1) || {
                        LOG_BUF+="$output"$'\n'
                        status_msg FAIL "Impossibile avviare il container"
                        setup_ok=false
                    }
                    LOG_BUF+="$output"$'\n'
                    if [ "$setup_ok" = true ] && [ "$use_volume" = true ] && [ "$vol_mount_point" = "/home/$username" ]; then
                        docker exec "$container_name" bash -c 'if [ ! -f "$HOME/.bashrc" ]; then cp -r /etc/skel/. "$HOME/" 2>/dev/null; sudo chown -R "$(whoami):$(whoami)" "$HOME" 2>/dev/null || chown -R "$(whoami):$(whoami)" "$HOME" 2>/dev/null; fi' > /dev/null 2>&1 || true
                    fi
                fi

                # Output
                if [ "$setup_ok" = true ]; then
                    hr
                    echo -e "  Container avviato: ${C_CIANO}$container_name${C_RESET}"
                    if [ -n "$username" ]; then
                        echo -e "     Utente:   ${C_CIANO}$username${C_RESET}"
                    fi
                    eval "$(pkg_manager_init "$idx_distro")"
                    local displayed_pkgs
                    if [ "$use_extra" = true ]; then
                        displayed_pkgs="$PKG_DISPLAY"
                    else
                        displayed_pkgs="base"
                    fi
                    echo -e "     Default:  ${C_CIANO}$(default_pkgs "$idx_distro")${C_RESET}"
                    echo -e "     Extra:    ${C_CIANO}$displayed_pkgs${C_RESET}"
                    if [ "$use_net_host" = true ]; then
                        if [ "$fix_hostname" = true ]; then
                            echo -e "     Hostname: ${C_CIANO}$container_name${C_RESET}"
                        else
                            echo -e "     Host:     ${C_CIANO}$(hostname)${C_RESET}"
                        fi
                    fi
                    if [ "$use_volume" = true ]; then
                        echo -e "     Volume:   ${C_CIANO}$vol_name → $vol_mount_point${C_RESET}"
                    fi
                fi

                # Log viewer
                local viewed_log=false
                if [ -n "$LOG_BUF" ]; then
                    hr
                    read -r -p "  ${C_BOLD}[L]${C_RESET} Log  │  ${C_BOLD}[Invio]${C_RESET} Continua: " show_logs
                    if [[ "$show_logs" =~ ^[Ll]$ ]]; then
                        viewed_log=true
                        clear; header
                        echo "  Build Log: $container_name"
                        echo ""
                        echo "$LOG_BUF" | while IFS= read -r log_line; do
                            echo "  $log_line"
                        done
                        echo ""
                        pause
                    fi
                fi

                if [ "$setup_ok" = false ] && [ "$viewed_log" = false ]; then
                    pause
                fi
                return
            done
        fi
    done
}

page_manage_containers() {
    while true; do
        header

        local containers_list
        containers_list=$(docker ps -a --format '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null)

        if [ -z "$containers_list" ]; then
            status_msg WARN "Nessun container trovato"
            echo ""
            echo -n "  Premi Invio per tornare al menu "
            read -r
            return
        fi

        echo "  [N°]  ID             NOME                      IMMAGINE                       STATO"
        echo "  ----  -----------    ---------------------    ----------------------------    --------"

        local idx=1
        while IFS= read -r line; do
            local id nome image status
            id=$(echo "$line" | awk '{print $1}')
            nome=$(echo "$line" | awk '{print $2}')
            image=$(echo "$line" | awk '{print $3}')
            status=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | xargs)

            local stato_ico
            if echo "$status" | grep -qi "up"; then
                stato_ico="Running"
            elif echo "$status" | grep -qi "exited"; then
                stato_ico="Stopped"
            elif echo "$status" | grep -qi "paused"; then
                stato_ico="Paused"
            else
                stato_ico="$status"
            fi

            printf "  %-4s %-13s %-22s %-28s %s\n" "$idx)" "$id" "$nome" "$image" "$stato_ico"
            idx=$((idx + 1))
        done <<< "$containers_list"
        echo ""
        echo -e "  ${C_BOLD}[ID o NOME]${C_RESET}  Elimina  │  ${C_BOLD}[D]${C_RESET}  Cancella tutti  │  ${C_BOLD}[h]${C_RESET}  Aiuto  │  ${C_BOLD}[Enter]${C_RESET}  Torna al menu"
    read -r scelta

    if [ -z "$scelta" ]; then
        return
    fi

    if [[ "$scelta" =~ ^[Hh]$ ]]; then
        show_help container
        continue
    fi

    if [[ "$scelta" =~ ^[Dd]$ ]]; then
        read -r -p "  Eliminare TUTTI i container? [S/n]: " confirm
        if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
            docker rm -f $(docker ps -aq) > /dev/null 2>&1
            status_msg OK "Tutti i container eliminati"
        fi
        pause
        continue
    fi

    local target
    if [[ "$scelta" =~ ^[0-9]+$ ]]; then
        target=$(echo "$containers_list" | sed -n "${scelta}p" | awk '{print $2}')
    else
        target="$scelta"
    fi

    if [ -n "$target" ]; then
        hr
        if docker rm -f "$target" > /dev/null 2>&1; then
            status_msg OK "Container '$target' eliminato"
        else
            status_msg FAIL "Container '$target' non trovato"
        fi
    fi

    pause
    # loop back instead of recursion
    done
}

page_manage_images() {
    while true; do
        header

        local images_list
        images_list=$(docker images --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}' 2>/dev/null)

        if [ -z "$images_list" ]; then
            status_msg WARN "Nessuna immagine trovata"
            echo ""
            echo -n "  Premi Invio per tornare al menu "
            read -r
            return
        fi

        echo "  [N°]  ID             REPOSITORY                     TAG             SIZE"
        echo "  ----  -----------    ---------------------------   ------------    --------"

        local idx=1
        while IFS= read -r line; do
            local id repo tag size
            id=$(echo "$line" | awk '{print $1}')
            repo=$(echo "$line" | awk '{print $2}')
            tag=$(echo "$line" | awk '{print $3}')
            size=$(echo "$line" | awk '{print $4}')
            printf "  %-4s %-13s %-28s %-14s %s\n" "$idx)" "$id" "$repo" "$tag" "$size"
            idx=$((idx + 1))
        done <<< "$images_list"
        echo ""
        echo -e "  ${C_BOLD}[ID o REPOSITORY]${C_RESET}  Elimina  │  ${C_BOLD}[D]${C_RESET}  Cancella tutte  │  ${C_BOLD}[h]${C_RESET}  Aiuto  │  ${C_BOLD}[Enter]${C_RESET}  Torna al menu"
        read -r scelta

        if [ -z "$scelta" ]; then
            return
        fi

        if [[ "$scelta" =~ ^[Hh]$ ]]; then
            show_help image
            continue
        fi

        if [[ "$scelta" =~ ^[Dd]$ ]]; then
            read -r -p "  Eliminare TUTTE le immagini? [S/n]: " confirm
            if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                docker rmi -f $(docker images -q) > /dev/null 2>&1
                status_msg OK "Tutte le immagini eliminate"
            fi
            pause
            continue
        fi

        local target
        if [[ "$scelta" =~ ^[0-9]+$ ]]; then
            target=$(echo "$images_list" | sed -n "${scelta}p" | awk '{print $1}')
        else
            target="$scelta"
        fi

        if [ -n "$target" ]; then
            hr
            if docker rmi -f "$target" > /dev/null 2>&1; then
                status_msg OK "Immagine '$target' eliminata"
            else
                status_msg FAIL "Immagine '$target' non trovata"
            fi
        fi

        pause
        # loop back instead of recursion
    done
}

# ═══════════════════════════════════════════════════
#   VOLUMI
# ═══════════════════════════════════════════════════

page_manage_volumes() {
    while true; do
        header

        local volumes_list
        volumes_list=$(docker volume ls --format '{{.Name}}' 2>/dev/null)

        if [ -n "$volumes_list" ]; then
            echo "  [N°]  NOME VOLUME                    MONTATO SU"
            echo "  ----  ------------------------------  -------------------"

            local idx=1
            while IFS= read -r vol_name; do
                local mounted_on="(nessuno)"
                local cname
                cname=$(docker ps -a --filter "volume=$vol_name" --format '{{.Names}}' 2>/dev/null | head -1)
                if [ -n "$cname" ]; then
                    local mnt
                    mnt=$(docker inspect "$cname" --format '{{range .Mounts}}{{if eq .Name "'"$vol_name"'"}}{{.Destination}}{{end}}{{end}}' 2>/dev/null)
                    mounted_on="$cname:$mnt"
                fi
                printf "  %-4s %-31s %s\n" "$idx)" "$vol_name" "$mounted_on"
                idx=$((idx + 1))
            done <<< "$volumes_list"
        else
            status_msg WARN "Nessun volume trovato"
        fi

        echo ""
        echo -e "  ${C_BOLD}[C]${C_RESET}  Crea volume  │  ${C_BOLD}[D]${C_RESET}  Cancella tutti  │  ${C_BOLD}[h]${C_RESET}  Aiuto  │  ${C_BOLD}[N°]${C_RESET}  Seleziona  │  ${C_BOLD}[Enter]${C_RESET}  Torna al menu"
        read -r scelta

        [ -z "$scelta" ] && return

        if [[ "$scelta" =~ ^[Hh]$ ]]; then
            show_help volume
            continue
        fi

        if [[ "$scelta" =~ ^[Cc]$ ]]; then
            read -r -p "  Nome volume: " new_vol
            if [ -n "$new_vol" ]; then
                if docker volume create "$new_vol" > /dev/null 2>&1; then
                    status_msg OK "Volume '$new_vol' creato"
                else
                    status_msg FAIL "Impossibile creare volume '$new_vol'"
                fi
                pause
            fi
        elif [[ "$scelta" =~ ^[Dd]$ ]]; then
            read -r -p "  Eliminare TUTTI i volumi? [S/n]: " confirm
            if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                local rimossi=0 in_uso=0 in_uso_list=""
                while IFS= read -r v; do
                    if docker volume rm "$v" > /dev/null 2>&1; then
                        rimossi=$((rimossi + 1))
                    else
                        in_uso=$((in_uso + 1))
                        local cn
                        cn=$(docker ps -a --filter "volume=$v" --format '{{.Names}}' 2>/dev/null | head -1)
                        in_uso_list="$in_uso_list$v → $cn"$'\n'
                    fi
                done <<< "$(docker volume ls -q)"
                [ "$rimossi" -gt 0 ] && status_msg OK "$rimossi volumi rimossi"
                if [ "$in_uso" -gt 0 ]; then
                    status_msg WARN "$in_uso volumi in uso — arresta i container prima:"
                    echo "$in_uso_list" | while IFS= read -r line; do
                        [ -n "$line" ] && echo "     $line"
                    done
                fi
                [ "$rimossi" -eq 0 ] && [ "$in_uso" -eq 0 ] && status_msg WARN "Nessun volume da rimuovere"
            fi
            pause
        elif [[ "$scelta" =~ ^[0-9]+$ ]] && [ -n "$volumes_list" ]; then
            local selected_vol
            selected_vol=$(echo "$volumes_list" | sed -n "${scelta}p")
            [ -n "$selected_vol" ] && sub_manage_volume "$selected_vol"
        fi
    done
}

sub_manage_volume() {
    local vol_name=$1
    while true; do
        header
        echo ""
        local cname mnt
        cname=$(docker ps -a --filter "volume=$vol_name" --format '{{.Names}}' 2>/dev/null | head -1)
        mnt=""
        [ -n "$cname" ] && mnt=$(docker inspect "$cname" --format '{{range .Mounts}}{{if eq .Name "'"$vol_name"'"}}{{.Destination}}{{end}}{{end}}' 2>/dev/null)

        if [ -n "$cname" ]; then
            echo -e "  Container: ${C_VERDE}$cname${C_RESET} → $mnt"
        else
            echo -e "  Container: ${C_DIM}(nessuno)${C_RESET}"
        fi
        echo ""
        echo -e "  ${C_BOLD}[R]${C_RESET}  Rimuovi volume  │  ${C_BOLD}[A]${C_RESET}  Collega a container  │  ${C_BOLD}[h]${C_RESET}  Aiuto  │  ${C_BOLD}[Enter]${C_RESET}  Torna"
        read -r sub_scelta

        case "$sub_scelta" in
            [Hh]) show_help volume; continue ;;
            [Rr])
                read -r -p "  Eliminare '$vol_name'? [S/n]: " confirm
                if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                    local vol_out
                    vol_out=$(docker volume rm "$vol_name" 2>&1) || true
                    if echo "$vol_out" | grep -qi "in use"; then
                        status_msg FAIL "Volume in uso dal container '${cname:-?}'. Arrestalo o rimuovilo prima."
                    elif [ -n "$vol_out" ]; then
                        status_msg OK "Volume rimosso"
                    else
                        status_msg FAIL "Volume '$vol_name' non trovato"
                    fi
                    pause
                    return
                fi
                ;;
            [Aa])
                if [ -n "$cname" ]; then
                    status_msg WARN "Volume già collegato a '$cname'"
                    pause
                    continue
                fi
                echo ""
                local containers_list
                containers_list=$(docker ps -a --format '{{.Names}}' 2>/dev/null)
                if [ -z "$containers_list" ]; then
                    status_msg WARN "Nessun container disponibile"
                    pause
                    continue
                fi
                local idx=1
                while IFS= read -r cn; do
                    echo "  [$idx] $cn"
                    idx=$((idx + 1))
                done <<< "$containers_list"
                echo ""
                read -r -p "  Seleziona container: " c_choice
                if [[ "$c_choice" =~ ^[0-9]+$ ]]; then
                    local target
                    target=$(echo "$containers_list" | sed -n "${c_choice}p")
                    if [ -n "$target" ]; then
                        echo "  Punto di mount: [1] /data  [2] /home/[utente]"
                        read -r -p "  Scelta [1-2]: " mp
                        local mount_point="/data"
                        if [ "$mp" = "2" ]; then
                            local user_name
                            user_name=$(docker inspect --format '{{.Config.User}}' "$target" 2>/dev/null)
                            if [ -z "$user_name" ] || [[ "$user_name" =~ ^[0-9]+$ ]]; then
                                mount_point="/home/user"
                            else
                                mount_point="/home/$user_name"
                            fi
                        fi
                        local img
                        img=$(docker inspect --format '{{.Config.Image}}' "$target" 2>/dev/null)
                        if [ -z "$img" ]; then
                            status_msg FAIL "Impossibile leggere immagine container"
                            pause; continue
                        fi
                        status_msg WARN "Rimuovo '$target' e ricreo con volume..."
                        local net_attach="" hst_attach=""
                        local is_host
                        is_host=$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$target" 2>/dev/null)
                        [ "$is_host" = "host" ] && net_attach="--network host"
                        hst_attach="--hostname $target"
                        docker rm -f "$target" > /dev/null 2>&1
                        docker run -d --name "$target" $net_attach $hst_attach -v "$vol_name:$mount_point" "$img" > /dev/null 2>&1 && {
                            status_msg OK "Volume collegato a '$target' → $mount_point"
                        } || {
                            status_msg FAIL "Impossibile avviare il container"
                        }
                        pause; return
                    fi
                fi
                status_msg FAIL "Scelta non valida"
                pause
                ;;
            *) return ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
#   ENTRY
# ═══════════════════════════════════════════════════

if ! command -v docker &>/dev/null; then
    status_msg FAIL "Docker non trovato. Installa Docker prima di usare DockForge."
    exit 1
fi

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    page_welcome
fi

