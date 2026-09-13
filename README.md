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
See ddns-forward.ini

This will create the following forwarding rules:

| Domain          | Remote Port | Local Target | Protocol |
|-----------------|-------------|--------------|----------|
| mytcp.example.com | 7000        | 1.2.3.4:7000 | UDP      |
| myudp.example.com | 2096        | 1.2.3.4:2096 | TCP      |

### Protocol Options

| Value | Behavior                    |
|------|------------------------------|
| tcp  | Forward TCP traffic          |
| udp  | Forward UDP traffic          |
| both | Forward both TCP and UDP     |
