# network-gateway-detector

Detect the default route's IPv4 gateway address by parsing routing table text.

```bash
source network_gateway_detector.sh

# Linux
ip route | network_gateway_detector
# => 192.168.1.1

# BSD/macOS
netstat -rn | network_gateway_detector
# => 10.0.0.1
```

The library exports one function:

- `network_gateway_detector` — reads routing table text from stdin, prints the
default gateway IPv4 address, and returns 0. If no default gateway is found it
prints nothing and returns 1.

## Why this exists

Routing table output differs between Linux (`ip route`) and BSD/macOS
(`netstat -rn`), and neither format is stable enough to parse with a single
regular expression. This library accepts both formats through one function so
callers do not need to know which platform they are on. It deliberately does
not invoke `ip` or `netstat` itself; the caller pipes in the output. That keeps
the library pure, easy to test, and free of external command dependencies.

## The trade-off

We only handle IPv4. IPv6 default routes exist but the brief asks for an IP
address and the gateway in the contexts this is used is almost always IPv4.
If you need IPv6, this library will return failure rather than guess.

## The awkward edge

Leading zeros in an octet (for example `010.0.0.1`) are rejected. Some tools
treat such addresses as octal, others as decimal; neither interpretation is
safe to assume for a gateway address, so we refuse to return one.
