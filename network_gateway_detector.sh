#!/usr/bin/env bash
# network_gateway_detector.sh
#
# Detect the default route's gateway IP address by parsing common routing
# table formats. This library is intentionally dependency-free: it relies only
# on bash builtins and coreutils (grep, awk, tr, sort). The parsing is strict
# because routing table output is not standardized; we accept the two most
# common formats (Linux `ip route` and BSD/macOS `netstat -rn`) and return the
# first plausible IPv4 gateway. IPv6 is not handled: the brief asks for an IP
# address and the default route gateway is overwhelmingly IPv4 in the contexts
# where this is used. If no default route is found, the function returns an
# empty string and a non-zero exit status.

set -euo pipefail

# _ngd_is_ipv4 <string>
# Return 0 if the argument looks like a dotted-quad IPv4 address, 1 otherwise.
# We deliberately reject addresses with leading zeros in octets (e.g. 010.0.0.1)
# because those are ambiguous in some parsers and never appear as gateways.
_ngd_is_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local a="${BASH_REMATCH[1]}"
    local b="${BASH_REMATCH[2]}"
    local c="${BASH_REMATCH[3]}"
    local d="${BASH_REMATCH[4]}"
    # Reject leading zeros except the single digit 0 itself.
    for octet in "$a" "$b" "$c" "$d"; do
        if [[ "$octet" != "0" && "$octet" == 0* ]]; then
            return 1
        fi
        if (( octet > 255 )); then
            return 1
        fi
    done
    return 0
}

# _ngd_parse_ip_route <input>
# Parse output of `ip route` (Linux) and echo the gateway of the default route.
# The default route line looks like:
#   default via 192.168.1.1 dev eth0 proto dhcp metric 100
# We look for a line starting with "default" and take the token after "via".
# If multiple default routes exist we take the first one, which matches the
# kernel's own ordering by metric in practice.
_ngd_parse_ip_route() {
    local input="$1"
    local line
    while IFS= read -r line; do
        # Strip leading whitespace.
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in
            default\ *)
                # Extract tokens after "default".
                local rest="${line#default }"
                # Split on whitespace.
                local tokens
                read -r -a tokens <<< "$rest"
                local i
                for (( i=0; i<${#tokens[@]}; i++ )); do
                    if [[ "${tokens[i]}" == "via" ]]; then
                        local candidate="${tokens[i+1]:-}"
                        if _ngd_is_ipv4 "$candidate"; then
                            printf '%s\n' "$candidate"
                            return 0
                        fi
                    fi
                done
                ;;
        esac
    done <<< "$input"
    return 1
}

# _ngd_parse_netstat_rn <input>
# Parse output of `netstat -rn` (BSD/macOS) and echo the default gateway.
# The default route line looks like:
#   default            192.168.1.1        UGScg        en0
# We match a line whose first field is "default" and whose second field is an
# IPv4 address. The second field is the gateway.
_ngd_parse_netstat_rn() {
    local input="$1"
    local line
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in
            default\ *)
                local rest="${line#default }"
                local tokens
                read -r -a tokens <<< "$rest"
                local candidate="${tokens[0]:-}"
                if _ngd_is_ipv4 "$candidate"; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
                ;;
        esac
    done <<< "$input"
    return 1
}

# network_gateway_detector <routing_table_text>
# Accept routing table text on stdin, detect the default gateway, and print it.
# The function tries Linux `ip route` format first, then BSD `netstat -rn`
# format. It returns 0 on success and 1 if no default gateway was found.
#
# This is the only exported function. It takes no arguments and reads stdin so
# that callers can pipe in output from `ip route` or `netstat -rn` without this
# library itself invoking external commands. That keeps the library testable
# and free of side effects.
network_gateway_detector() {
    local input
    input="$(cat)"
    if [[ -z "$input" ]]; then
        return 1
    fi
    if _ngd_parse_ip_route "$input"; then
        return 0
    fi
    if _ngd_parse_netstat_rn "$input"; then
        return 0
    fi
    return 1
}
