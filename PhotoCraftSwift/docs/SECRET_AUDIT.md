# Public source credential audit

6 November 2026. Audited public commit `e5f23cb54a1161057b063fc04db99191cfd9ed23` of [ForensicIntelligence/Photato](https://github.com/ForensicIntelligence/Photato). The advertised public refs were unchanged when verification finished.

**No exposed real credentials were found.** A fresh public mirror contains one branch, no public tags, 69 reachable commits and 10,680 unique historical file blobs (2,630,062,448 bytes).

Gitleaks 8.30.1, downloaded from its official release and checked against the published SHA256 checksum, scanned full history, all historical blobs and commit/tag metadata. There was no file-size cutoff; inline allow comments and repository suppressions were not used. Archive depth 3 and decoding depth 5 were enabled. All 159 history and 650 blob findings were reviewed. They are source-file digests, prose, JSON field names and a TIFF metadata enum constant. 145 historical digest findings were independently matched to committed file bytes. No commit-metadata finding remained.

A separate byte scan checked private-key material, common provider-token formats, credential URLs and literal passwords/passphrases, and inventoried historical sensitive filenames. Its 12 findings are confined to Tests: 6 password references for owned encrypted-PDF fixtures or deliberately wrong inputs, and 6 synthetic userinfo URLs used in rejection tests. Fixture provenance explicitly identifies the test-only PDF password. There are no credential-file candidates or Git LFS pointers left outside this inventory.

GitHub secret scanning and push protection were disabled before this audit and are now enabled. GitHub reports zero alerts at the recorded verification time; completion of its initial background scan is not inferred. Generic/non-provider patterns remain disabled in GitHub, so independent generic detection was used. There are no public releases or Actions artifacts to scan. Five existing prerelease drafts remain unpublished and unchanged.

Raw candidate values and the fresh clone are retained privately, outside the repository. No app/test source, Git history, release or current fixture was changed; no found string was used to authenticate with a provider. This is a bounded scan and contextual review of the pinned Git state, not a guarantee about every possible encoding or future change. [Machine-readable evidence](SECRET_AUDIT_445.json).

Rechecked during checkpoint 447 on 6 November 2026: public main and all advertised refs still match the audited commit; all retained private audit evidence hashes match. GitHub still reports zero alerts, with secret scanning and push protection enabled. [Recheck](SECRET_AUDIT_447_RECHECK.json).
