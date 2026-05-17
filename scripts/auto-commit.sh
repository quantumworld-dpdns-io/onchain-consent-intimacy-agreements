#!/bin/bash
# Auto-commit agent: commits and pushes to dev branch every 10 seconds
# Runs in background during implementation

REPO_DIR="/Users/dennis_leedennis_lee/Documents/GitHub/onchain-consent-intimacy-agreements"
COUNT=0

while true; do
  cd "$REPO_DIR" || exit 1
  
  # Check if there are changes
  if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    git add -A 2>/dev/null
    git commit -m "auto: implementation progress - $(date '+%Y-%m-%d %H:%M:%S') [commit #$COUNT]" 2>/dev/null
    
    # Push to dev (with force only if needed)
    git push origin dev 2>/dev/null || echo "[auto-commit] Push failed, will retry"
    
    COUNT=$((COUNT + 1))
    echo "[auto-commit] Commit #$COUNT pushed at $(date)"
  fi
  
  sleep 10
done
