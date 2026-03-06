#!/bin/bash

# Format: "REMOTE_TARGET | REMOTE_PORT | LOCAL_TARGET | LOCAL_PORT | PROTOCOL"
# TARGETS can be Domain names, Hostnames, or raw IP addresses.
FORWARDS=(
    "udp.example.com|8080|1.2.3.4|8080|udp"
    "api.example.com|8443|1.2.3.4|8443|tcp"
)

CHECK_INTERVAL=30

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

while true; do
    for ENTRY in "${FORWARDS[@]}"; do
        IFS='|' read -r REMOTE_TARGET REMOTE_PORT LOCAL_TARGET LOCAL_PORT PROTO <<< "$ENTRY"
        
        PROTO=$(echo "$PROTO" | tr '[:upper:]' '[:lower:]')
        PROTOS_TO_APPLY=()
        [[ "$PROTO" == "both" ]] && PROTOS_TO_APPLY=("tcp" "udp") || PROTOS_TO_APPLY=("$PROTO")

        # Resolve both ends
        CURRENT_REMOTE_IP=$(resolve_target "$REMOTE_TARGET")
        CURRENT_LOCAL_IP=$(resolve_target "$LOCAL_TARGET")

        if [ -z "$CURRENT_REMOTE_IP" ] || [ -z "$CURRENT_LOCAL_IP" ]; then
            echo "Error: Could not resolve $REMOTE_TARGET or $LOCAL_TARGET. Skipping..."
            continue
        fi

        SAFE_REMOTE=$(echo "$REMOTE_TARGET" | tr '.' '_')
        SAFE_LOCAL=$(echo "$LOCAL_TARGET" | tr '.' '_')
        CACHE_FILE="/var/run/fwd_cache_${SAFE_REMOTE}_${REMOTE_PORT}_to_${SAFE_LOCAL}_${LOCAL_PORT}.state"

        OLD_REMOTE_IP=""
        OLD_LOCAL_IP=""
        if [ -f "$CACHE_FILE" ]; then
            IFS='|' read -r OLD_REMOTE_IP OLD_LOCAL_IP < "$CACHE_FILE"
        fi

        if [ "$CURRENT_REMOTE_IP" != "$OLD_REMOTE_IP" ] || [ "$CURRENT_LOCAL_IP" != "$OLD_LOCAL_IP" ]; then
            echo "Change Detected for $REMOTE_TARGET -> $LOCAL_TARGET"
            
            for p in "${PROTOS_TO_APPLY[@]}"; do
                if [ -n "$OLD_REMOTE_IP" ] && [ -n "$OLD_LOCAL_IP" ]; then
                    /usr/sbin/iptables -t nat -D PREROUTING -p "$p" --dport "$LOCAL_PORT" -j DNAT --to-destination "$OLD_REMOTE_IP:$REMOTE_PORT" 2>/dev/null
                    /usr/sbin/iptables -t nat -D POSTROUTING -p "$p" -d "$OLD_REMOTE_IP" --dport "$REMOTE_PORT" -j SNAT --to-source "$OLD_LOCAL_IP" 2>/dev/null
                fi

                /usr/sbin/iptables -t nat -A PREROUTING -p "$p" --dport "$LOCAL_PORT" -j DNAT --to-destination "$CURRENT_REMOTE_IP:$REMOTE_PORT"
                /usr/sbin/iptables -t nat -A POSTROUTING -p "$p" -d "$CURRENT_REMOTE_IP" --dport "$REMOTE_PORT" -j SNAT --to-source "$CURRENT_LOCAL_IP"
            done

            echo "${CURRENT_REMOTE_IP}|${CURRENT_LOCAL_IP}" > "$CACHE_FILE"
            echo "Rules updated: Remote=$CURRENT_REMOTE_IP, Local=$CURRENT_LOCAL_IP"
        fi
    done

    sleep "$CHECK_INTERVAL"
done
