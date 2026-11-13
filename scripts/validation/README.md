# Local system validation

Run from any directory with Python 3.11+, Node 24, uv, installed locked backend and contract dependencies, Flutter, and a dedicated PostgreSQL test database. The database account must be able to create and drop schemas. Do not point this at a production or shared database: tests create and drop temporary schemas, while the local-chain integration deploys contracts and advances chain time. No installation, database reset, or remote-chain use is performed by this runner.

```powershell
$env:TEST_DATABASE_URL = 'postgresql+psycopg://postgres@127.0.0.1:55643/prepaidguard_validation'
python scripts/validation/validate.py --repo-root . --node-executable 'C:/path/to/node.exe' --rpc-url http://127.0.0.1:18545 --output-dir validation-results
```

Use `--start-local-evm` to start and stop a node owned by the runner on an unoccupied loopback address (`--rpc-url` selects the address; default port 8545). Without this flag an existing chain must already be running. Only HTTP loopback RPCs with chain ID 31337 are accepted. An existing node is never stopped by this script. Integration tests change that chain's state and clock.

`--phase contracts|backend|integration|frontend` reruns one phase; `--phase all` is the default. `--database-url-env NAME` chooses the environment variable containing the database URL. `--timeout SECONDS` controls each subprocess (default 600); `--retries N` retries failed subprocesses (default 0). Run after resolving failures; retrying does not make a failed step pass unless a subsequent attempt succeeds. A phase run validates only that phase; a complete acceptance requires `--phase all`.

The runner emits `report.json` and `report.md` in the output directory, overwriting previous reports. Each required check is pass, fail or blocked, and any fail or blocked check produces a nonzero exit. Unselected phases are explicitly marked skipped; they are outside a single-phase result and prevent that result from representing full-system acceptance. Subprocess output is intentionally withheld to avoid leaking credentials. Re-run the reported command manually in a secure environment for diagnostics. Isolated export checks use a temporary copy of the contracts and shared directories, including dependencies, so allow disk space and time. Migration checks use a temporary schema and attempt cleanup; a blocked cleanup is a failure requiring manual removal of the `pp_validate_` schema. Test fixtures create and remove their own schemas.
