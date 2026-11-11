#!/usr/bin/env bash
# test_network_gateway_detector.sh
#
# Tests for network_gateway_detector. Run with: bash test_network_gateway_detector.sh
# The test script sources the library and calls its functions directly.

set -euo pipefail

# Locate the library relative to this test script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=network_gateway_detector.sh
source "$SCRIPT_DIR/network_gateway_detector.sh"

# assert_eq <expected> <actual> <message>
# Print TAP-like output and exit non-zero on mismatch.
assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf 'ok - %s\n' "$message"
    else
        printf 'not ok - %s\n' "$message"
        printf '  expected: %q\n' "$expected"
        printf '  actual:   %q\n' "$actual"
        exit 1
    fi
}

# assert_status <expected_status> <actual_status> <message>
assert_status() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    if [[ "$expected" -eq "$actual" ]]; then
        printf 'ok - %s\n' "$message"
    else
        printf 'not ok - %s\n' "$message"
        printf '  expected status: %d\n' "$expected"
        printf '  actual status:   %d\n' "$actual"
        exit 1
    fi
}

# Test 1: Linux ip route format.
linux_input='default via 192.168.1.1 dev eth0 proto dhcp metric 100
10.0.0.0/8 via 10.0.0.1 dev eth1'
output=$(printf '%s\n' "$linux_input" | network_gateway_detector)
status=$?
assert_status 0 "$status" "Linux ip route returns success"
assert_eq "192.168.1.1" "$output" "Linux ip route extracts gateway"

# Test 2: BSD netstat -rn format.
bsd_input='Routing tables

Internet:
Destination        Gateway            Flags        Netif Expire
default            10.0.0.1           UGScg        en0
127.0.0.1          127.0.0.1          UH           lo0'
output=$(printf '%s\n' "$bsd_input" | network_gateway_detector)
status=$?
assert_status 0 "$status" "BSD netstat -rn returns success"
assert_eq "10.0.0.1" "$output" "BSD netstat -rn extracts gateway"

# Test 3: No default route.
no_default='10.0.0.0/8 via 10.0.0.1 dev eth1'
output=$(printf '%s\n' "$no_default" | network_gateway_detector) || status=$?
status=${status:-0}
assert_status 1 "$status" "No default route returns failure"
assert_eq "" "$output" "No default route prints nothing"

# Test 4: Empty input.
output=$(printf '' | network_gateway_detector) || status=$?
status=${status:-0}
assert_status 1 "$status" "Empty input returns failure"
assert_eq "" "$output" "Empty input prints nothing"

# Test 5: Default route with IPv6 gateway only should fail (IPv4 only).
ipv6_input='default via fe80::1 dev eth0 proto ra metric 100'
output=$(printf '%s\n' "$ipv6_input" | network_gateway_detector) || status=$?
status=${status:-0}
assert_status 1 "$status" "IPv6 gateway is not accepted"
assert_eq "" "$output" "IPv6 gateway prints nothing"

# Test 6: Leading zeros in octets are rejected.
leading_zero='default via 010.0.0.1 dev eth0'
output=$(printf '%s\n' "$leading_zero" | network_gateway_detector) || status=$?
status=${status:-0}
assert_status 1 "$status" "Leading zeros rejected"
assert_eq "" "$output" "Leading zeros prints nothing"

# Test 7: Octet out of range is rejected.
out_of_range='default via 256.1.1.1 dev eth0'
output=$(printf '%s\n' "$out_of_range" | network_gateway_detector) || status=$?
status=${status:-0}
assert_status 1 "$status" "Out-of-range octet rejected"
assert_eq "" "$output" "Out-of-range octet prints nothing"

# Test 8: Multiple default routes, first wins.
multi='default via 192.168.1.1 dev eth0 metric 100
default via 10.0.0.1 dev eth1 metric 200'
output=$(printf '%s\n' "$multi" | network_gateway_detector)
status=$?
assert_status 0 "$status" "Multiple default routes returns success"
assert_eq "192.168.1.1" "$output" "Multiple default routes picks first"

# Test 9: Whitespace tolerance in netstat output.
whitespace='default    172.16.0.1    UGSc    en0'
output=$(printf '%s\n' "$whitespace" | network_gateway_detector)
status=$?
assert_status 0 "$status" "Whitespace tolerance succeeds"
assert_eq "172.16.0.1" "$output" "Whitespace tolerance extracts gateway"

# Test 10: Non-default lines are ignored.
non_default='192.168.0.0/24 dev eth0 proto kernel scope link src 192.168.0.2'
output=$(printf '%s\n' "$non_default" | network_gateway_detector) || status=$?
status=${status:-0}
assert_status 1 "$status" "Non-default lines ignored"
assert_eq "" "$output" "Non-default lines print nothing"

printf '1..10\n'
