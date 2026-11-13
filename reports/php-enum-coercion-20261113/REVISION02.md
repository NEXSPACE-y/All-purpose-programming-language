# Selected enum patch revision02

The backing type is text metadata whose spelling may be STRING or INT. The
first helper used raw comparison against lowercase string, which would route an
uppercase STRING declaration through the wrong path. Revision02 changes only
that decision to the ASCII-only name comparer. Two additional unchanged-source
oracle controls confirm uppercase STRING and INT are accepted by PHP8.5.12.

Selected module SHA256:
`7a8eea1a7019d51380afbb99e27af1b891292db86a7362acc7e7d41769d90894`.
Selected candidate on composed09:
`4fe6f21610a29111eab0073c1249b11c2763bde232763a33b4d86b816ecf1b8e`.
It passed exact apply/second-apply guards, CRLF/LF equivalence and parsing only.
No interpreter runtime measurement has been performed for this module yet.

Revision01 and its 4369aeee module snapshot stay intact. The original
artifact-manifest.json is a historical receipt: its root module path now points
to the new revision, while revision01/EnumCoercionEdits.snapshot.py preserves the
exact old bytes. Use artifact-manifest-revision02.json for the current complete
artifact set. The original twelve source cases are unchanged; uppercase controls
are separate in enum-typecase2.cases.json. Strict caller state remains unimplemented.
