# payments-service

A CI-shaped beat. The lockfile pins `axios@1.14.1`, one of the two versions
compromised in the March 2026 npm maintainer-account attack.

```bash
npm ci
```

`npm ci` trusts the lockfile, so it skips version resolution and requests the
tarball URL directly. The firewall makes its decision before it contacts npm,
which is why this beat still works even though npm has removed the version.

The block message names the transitive dependency by name:

```
Reason: Known malware -- Has malicious plain-crypto-js@4.2.1 dependency.;
        Known malware -- Malicious code in axios (npm).
```

Compromised versions are `1.14.1` and `0.30.4`. `1.14.0` is clean.
