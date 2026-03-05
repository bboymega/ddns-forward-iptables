#!/bin/bash

# Format: "REMOTE_DOMAIN | REMOTE_PORT | LOCAL_IP | LOCAL_PORT | PROTOCOL"
# PROTOCOL options: TCP, UDP, or BOTH

FORWARDS=(
    "udp.example.com|8080|1.2.3.4|8080|udp"
    "api.example.com|8443|1.2.3.4|8443|tcp"
)

CHECK_INTERVAL=30

while true; do
    for ENTRY in "${FORWARDS[@]}"; do
        IFS='|' read -r REMOTE_DOMAIN REMOTE_PORT LOCAL_IP LOCAL_PORT PROTO <<< "$ENTRY"
        
        PROTO=$(echo "$PROTO" | tr '[:upper:]' '[:lower:]')
        
        PROTOS_TO_APPLY=()
        if [[ "$PROTO" == "both" ]]; then
            PROTOS_TO_APPLY=("tcp" "udp")
        else
            PROTOS_TO_APPLY=("$PROTO")
        fi

        CACHE_FILE="/var/run/ip_cache_${LOCAL_IP}_${LOCAL_PORT}_${PROTO}.txt"
        CURRENT_IP=$(dig +short "$REMOTE_DOMAIN" | tail -n1)

        if [ -z "$CURRENT_IP" ]; then
            echo "Error: Could not resolve $REMOTE_DOMAIN. Skipping..."
            continue
        fi

        OLD_IP=""
        [ -f "$CACHE_FILE" ] && OLD_IP=$(cat "$CACHE_FILE")

        if [ "$CURRENT_IP" != "$OLD_IP" ]; then
            echo "Updating Remote $REMOTE_DOMAIN ($OLD_IP -> $CURRENT_IP) Port $REMOTE_PORT on Local $LOCAL_IP Port $LOCAL_PORT for $PROTO"

            for p in "${PROTOS_TO_APPLY[@]}"; do
                if [ -n "$OLD_IP" ]; then
                    /usr/sbin/iptables -t nat -D PREROUTING -p "$p" --dport "$LOCAL_PORT" -j DNAT --to-destination "$OLD_IP:$REMOTE_PORT" 2>/dev/null
                    /usr/sbin/iptables -t nat -D POSTROUTING -p "$p" -d "$OLD_IP" --dport "$REMOTE_PORT" -j SNAT --to-source "$LOCAL_IP" 2>/dev/null
                fi

                /usr/sbin/iptables -t nat -A PREROUTING -p "$p" --dport "$LOCAL_PORT" -j DNAT --to-destination "$CURRENT_IP:$REMOTE_PORT"
                /usr/sbin/iptables -t nat -A POSTROUTING -p "$p" -d "$CURRENT_IP" --dport "$REMOTE_PORT" -j SNAT --to-source "$LOCAL_IP"
            done

            echo "$CURRENT_IP" > "$CACHE_FILE"
        fi
    done

    sleep "$CHECK_INTERVAL"
done
