# Client-Trust Test Certificates

Public, test-only certificates used by
`tests/tilt-prerequisites/test-client-trust.sh`. They are not the live
development CA and must never be installed into system or NSS trust.

Provenance: a human generated them on 2026-10-22 on the personal host with the
single command in the "Prerequisites and evidence" section of
`docs/plans/decoupling-review-remediation.md`. The private keys lived only in a
temporary directory that the command deleted; no key was transferred or
committed. Agents must not regenerate these files.

| File | Subject | Issuer | Not before | Not after | SHA-256 fingerprint |
| --- | --- | --- | --- | --- | --- |
| `root.pem` | `CN=Budget Analyzer Test Root` (CA) | self | 2026-10-22 03:57:08 UTC | 2126-09-28 03:57:08 UTC | `62:7E:7B:07:DB:8A:FE:E1:03:DA:49:4D:3E:3B:D2:94:6C:D5:F3:82:68:F9:0F:EE:DF:67:A2:D0:83:12:42:93` |
| `leaf.pem` | `CN=*.budgetanalyzer.localhost`, SAN `DNS:*.budgetanalyzer.localhost`, serverAuth | `CN=Budget Analyzer Test Root` | 2026-10-22 03:57:08 UTC | 2126-09-28 03:57:08 UTC | `2B:71:5B:BE:90:5F:D8:44:B3:8F:2F:EE:BD:EA:2A:F2:7D:1B:89:36:21:EA:75:99:95:35:7B:82:AA:19:AA:B5` |
| `unrelated-root.pem` | `CN=Budget Analyzer Unrelated Test Root` (CA) | self | 2026-10-22 03:57:08 UTC | 2126-09-28 03:57:08 UTC | `4C:E2:FD:F9:5D:05:F3:C7:E8:79:BF:EF:18:99:07:37:87:5E:0C:CA:9A:32:B7:24:2E:4C:25:80:1D:29:C1:3D` |

Tests verify at the current time; the 100-year validity avoids `-attime`
plumbing. Inspect with `openssl x509 -in FILE -noout -subject -issuer -dates`.
