#!/bin/bash

# Format: "REMOTE_TARGET | REMOTE_PORT | LOCAL_TARGET | LOCAL_PORT | PROTOCOL"
FORWARDS=(
    "udp.example.com|8080|1.2.3.4|8080|udp"
    "api.example.com|8443|1.2.3.4|8443|tcp"
)

CHECK_INTERVAL=30
CACHE_DIR="/var/run"

CLEAN=false
RELOAD=false

# --------- ARG PARSING ----------
for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN=true ;;
        --reload) RELOAD=true ;;
    esac
done

# --------- HELPERS ----------
is_ip() {
    [[ $1 =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]
}

resolve_target() {
    local TARGET=$1
    if is_ip "$TARGET"; then
        echo "$TARGET"
    else
        dig +short "$TARGET" | tail -n1
    fi
}

log_rule() {
    local ACTION=$1
    local LOCAL_IP=$2
    local LOCAL_PORT=$3
    local REMOTE_IP=$4
    local REMOTE_PORT=$5
    local PROTO=$6

    echo "[$ACTION][$PROTO] src=${LOCAL_IP}:${LOCAL_PORT} -> dst=${REMOTE_IP}:${REMOTE_PORT}"
}

delete_rules() {
    local REMOTE_IP=$1
    local REMOTE_PORT=$2
    local LOCAL_IP=$3
    local LOCAL_PORT=$4
    local PROTO=$5

    /usr/sbin/iptables -t nat -D PREROUTING -p "$PROTO" --dport "$LOCAL_PORT" \
        -j DNAT --to-destination "$REMOTE_IP:$REMOTE_PORT" 2>/dev/null

    /usr/sbin/iptables -t nat -D POSTROUTING -p "$PROTO" -d "$REMOTE_IP" \
        --dport "$REMOTE_PORT" -j SNAT --to-source "$LOCAL_IP" 2>/dev/null

    log_rule "DEL" "$LOCAL_IP" "$LOCAL_PORT" "$REMOTE_IP" "$REMOTE_PORT" "$PROTO"
}

apply_rules() {
    local REMOTE_IP=$1
    local REMOTE_PORT=$2
    local LOCAL_IP=$3
    local LOCAL_PORT=$4
    local PROTO=$5

    /usr/sbin/iptables -t nat -A PREROUTING -p "$PROTO" --dport "$LOCAL_PORT" \
        -j DNAT --to-destination "$REMOTE_IP:$REMOTE_PORT"

    /usr/sbin/iptables -t nat -A POSTROUTING -p "$PROTO" -d "$REMOTE_IP" \
        --dport "$REMOTE_PORT" -j SNAT --to-source "$LOCAL_IP"

    log_rule "ADD" "$LOCAL_IP" "$LOCAL_PORT" "$REMOTE_IP" "$REMOTE_PORT" "$PROTO"
}

clean_all() {
    echo "Cleaning all managed iptables rules and cache..."

    for ENTRY in "${FORWARDS[@]}"; do
        IFS='|' read -r REMOTE_TARGET REMOTE_PORT LOCAL_TARGET LOCAL_PORT PROTO <<< "$ENTRY"
        PROTO=$(echo "$PROTO" | tr '[:upper:]' '[:lower:]')
        [[ "$PROTO" == "both" ]] && PROTOS=("tcp" "udp") || PROTOS=("$PROTO")

        SAFE_REMOTE=$(echo "$REMOTE_TARGET" | tr '.' '_')
        SAFE_LOCAL=$(echo "$LOCAL_TARGET" | tr '.' '_')
        CACHE_FILE="$CACHE_DIR/fwd_cache_${SAFE_REMOTE}_${REMOTE_PORT}_to_${SAFE_LOCAL}_${LOCAL_PORT}.state"

        if [ -f "$CACHE_FILE" ]; then
            IFS='|' read -r OLD_REMOTE_IP OLD_LOCAL_IP < "$CACHE_FILE"

            for p in "${PROTOS[@]}"; do
                delete_rules "$OLD_REMOTE_IP" "$REMOTE_PORT" "$OLD_LOCAL_IP" "$LOCAL_PORT" "$p"
            done

            rm -f "$CACHE_FILE"

            OLD_SRC="${OLD_LOCAL_IP:+$OLD_LOCAL_IP:$LOCAL_PORT}"
            OLD_DST="${OLD_REMOTE_IP:+$OLD_REMOTE_IP:$REMOTE_PORT}"
            echo "CLEAN ${REMOTE_TARGET}:${REMOTE_PORT} -> ${LOCAL_TARGET}:${LOCAL_PORT} | Old: src=${OLD_SRC:-none} -> dst=${OLD_DST:-none}"
        fi
    done
}

# --------- CLEAN MODE ----------
if $CLEAN; then
    clean_all
    exit 0
fi

# --------- RELOAD (one-shot) ----------
if $RELOAD; then
    echo "Reload requested: flushing managed rules and applying current targets..."
    clean_all

    for ENTRY in "${FORWARDS[@]}"; do
        IFS='|' read -r REMOTE_TARGET REMOTE_PORT LOCAL_TARGET LOCAL_PORT PROTO <<< "$ENTRY"
        PROTO=$(echo "$PROTO" | tr '[:upper:]' '[:lower:]')
        [[ "$PROTO" == "both" ]] && PROTOS_TO_APPLY=("tcp" "udp") || PROTOS_TO_APPLY=("$PROTO")

        CURRENT_REMOTE_IP=$(resolve_target "$REMOTE_TARGET")
        CURRENT_LOCAL_IP=$(resolve_target "$LOCAL_TARGET")

        if [ -z "$CURRENT_REMOTE_IP" ] || [ -z "$CURRENT_LOCAL_IP" ]; then
            echo "Error: Could not resolve $REMOTE_TARGET or $LOCAL_TARGET. Skipping..."
            continue
        fi

        for p in "${PROTOS_TO_APPLY[@]}"; do
            apply_rules "$CURRENT_REMOTE_IP" "$REMOTE_PORT" "$CURRENT_LOCAL_IP" "$LOCAL_PORT" "$p"
        done

        echo "${CURRENT_REMOTE_IP}|${CURRENT_LOCAL_IP}" > "$CACHE_DIR/fwd_cache_$(echo "$REMOTE_TARGET" | tr '.' '_')_${REMOTE_PORT}_to_$(echo "$LOCAL_TARGET" | tr '.' '_')_${LOCAL_PORT}.state"
    done

    echo "Reload complete."
    exit 0
fi

# --------- MAIN LOOP ----------
while true; do
    for ENTRY in "${FORWARDS[@]}"; do
        IFS='|' read -r REMOTE_TARGET REMOTE_PORT LOCAL_TARGET LOCAL_PORT PROTO <<< "$ENTRY"
        PROTO=$(echo "$PROTO" | tr '[:upper:]' '[:lower:]')
        [[ "$PROTO" == "both" ]] && PROTOS_TO_APPLY=("tcp" "udp") || PROTOS_TO_APPLY=("$PROTO")

        CURRENT_REMOTE_IP=$(resolve_target "$REMOTE_TARGET")
        CURRENT_LOCAL_IP=$(resolve_target "$LOCAL_TARGET")

        if [ -z "$CURRENT_REMOTE_IP" ] || [ -z "$CURRENT_LOCAL_IP" ]; then
            echo "Error: Could not resolve $REMOTE_TARGET or $LOCAL_TARGET. Skipping..."
            continue
        fi

        SAFE_REMOTE=$(echo "$REMOTE_TARGET" | tr '.' '_')
        SAFE_LOCAL=$(echo "$LOCAL_TARGET" | tr '.' '_')
        CACHE_FILE="$CACHE_DIR/fwd_cache_${SAFE_REMOTE}_${REMOTE_PORT}_to_${SAFE_LOCAL}_${LOCAL_PORT}.state"

        OLD_REMOTE_IP=""
        OLD_LOCAL_IP=""

        if [ -f "$CACHE_FILE" ]; then
            IFS='|' read -r OLD_REMOTE_IP OLD_LOCAL_IP < "$CACHE_FILE"
        fi

        if [ "$CURRENT_REMOTE_IP" != "$OLD_REMOTE_IP" ] || [ "$CURRENT_LOCAL_IP" != "$OLD_LOCAL_IP" ]; then

            OLD_SRC="${OLD_LOCAL_IP:+$OLD_LOCAL_IP:$LOCAL_PORT}"
            OLD_DST="${OLD_REMOTE_IP:+$OLD_REMOTE_IP:$REMOTE_PORT}"

            echo "Change Detected for ${REMOTE_TARGET}:${REMOTE_PORT} -> ${LOCAL_TARGET}:${LOCAL_PORT} | Old: src=${OLD_SRC:-none} -> dst=${OLD_DST:-none} ; New: src=${CURRENT_LOCAL_IP}:${LOCAL_PORT} -> dst=${CURRENT_REMOTE_IP}:${REMOTE_PORT}"

            for p in "${PROTOS_TO_APPLY[@]}"; do
                if [ -n "$OLD_REMOTE_IP" ] && [ -n "$OLD_LOCAL_IP" ]; then
                    delete_rules "$OLD_REMOTE_IP" "$REMOTE_PORT" "$OLD_LOCAL_IP" "$LOCAL_PORT" "$p"
                fi

                apply_rules "$CURRENT_REMOTE_IP" "$REMOTE_PORT" "$CURRENT_LOCAL_IP" "$LOCAL_PORT" "$p"
            done

            echo "${CURRENT_REMOTE_IP}|${CURRENT_LOCAL_IP}" > "$CACHE_FILE"
        fi
    done

    sleep "$CHECK_INTERVAL"
done
