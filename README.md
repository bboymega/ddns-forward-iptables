# DDNS-FORWARD-IPTABLES

A lightweight script that automatically creates iptables port forwarding rules for hosts defined by Dynamic DNS (DDNS) domains.

## Overview

This script:

- Resolves a DDNS hostname to its current IP address

- Creates or updates iptables DNAT rules

- Forwards traffic from a remote domain + port to a local IP + port

Useful when:

- Remote services use dynamic IPs

- You need stable forwarding rules based on domain names

- Managing multiple forwards with simple configuration

## Configuration

Forwarding rules are defined in the FORWARDS array as follows:

`REMOTE_TARGET | REMOTE_PORT | LOCAL_TARGET | LOCAL_PORT | PROTOCOL`

TARGETS can be Domain names, Hostnames, or raw IP addresses.

### Fields

| Field         | Description                                  | Example            |
|--------------|----------------------------------------------|--------------------|
| REMOTE_TARGET | Domain name to resolve (e.g., DDNS hostname) | `host.example.com` |
| REMOTE_PORT   | Port to accept traffic on                    | `8080`             |
| LOCAL_TARGET      | Internal destination                      | `192.168.1.10`     |
| LOCAL_PORT    | Internal destination port                    | `8080`             |
| PROTOCOL      | Protocol to forward (`tcp`, `udp`, or `both`) | `tcp`              |

### Example Configuration
```
FORWARDS=(
    "udp.example.com|8080|1.2.3.4|8080|udp"
    "api.example.com|8443|1.2.3.4|8443|tcp"
)
```

This will create the following forwarding rules:

| Domain          | Remote Port | Local Target | Protocol |
|-----------------|-------------|--------------|----------|
| udp.example.com | 8080        | 1.2.3.4:8080 | UDP      |
| api.example.com | 8443        | 1.2.3.4:8443 | TCP      |

### Protocol Options

| Value | Behavior                    |
|------|------------------------------|
| tcp  | Forward TCP traffic          |
| udp  | Forward UDP traffic          |
| both | Forward both TCP and UDP     |
