#!/usr/bin/env bash
. "$(dirname "$0")/_common.sh"; cd "$ROOT"
printf '#!/usr/bin/env bash\nexec "$(git rev-parse --show-toplevel)/scripts/check_secrets.sh"\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
echo "Đã cài hook pre-commit (quét bí mật)."
