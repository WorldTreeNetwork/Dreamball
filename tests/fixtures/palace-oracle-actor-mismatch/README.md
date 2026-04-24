palace-oracle-actor-mismatch: oracle actor fp mismatch fixture (AC10)
The palace.oracle.key is absent; AC10 check is skipped without it.
This fixture demonstrates the structural mismatch that would fail if
a real oracle.key with identity fp != 0x55*32 were present.
