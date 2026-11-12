# Integrated PHP v3.19 candidate

The exact source `113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b` was copied into the isolated package and validated there.

`Build-DisjointIntegration.py` merged three independently measured, hash-pinned edits onto frozen native base47c: private Throwable binding2527, import collisionc6dc and registered function collision53e8. It rejects broad or overlapping edits and writes a source/diff/provenance snapshot without updating package. `provenance.json` preserves its initial pre-verification state; subsequent acceptance evidence is separate.

[Actual package measurements and remaining differences](../../../reports/v3_19-validation-20261112/INTEGRATION_REVIEW.md): default965 pass, CLI37 selected matches, import23 matches, registered-name19 matches, cache10 matches, private12/14 with known dynamic function Error differences retained. Native23 match on full repetition after one initial timeout; original failure retained.

This is a development checkpoint, not full PHP compatibility. It does not include the separate synchronous callback prototype, Windows Web/Linux runtime acceptance or stage2 ALL language work.
