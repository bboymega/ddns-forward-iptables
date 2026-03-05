# DDNS-FORWARD-IPTABLES

## Format: "REMOTE_DOMAIN | REMOTE_PORT | LOCAL_IP | LOCAL_PORT | PROTOCOL"
## PROTOCOL options: TCP, UDP, or BOTH

```
FORWARDS=(
    "udp.example.com|8080|1.2.3.4|8080|udp"
    "api.example.com|8443|1.2.3.4|8443|tcp"
)
```
