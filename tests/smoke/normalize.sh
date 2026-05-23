#!/usr/bin/env bash
# Normalize smoke output: replace timestamp, pid, issue-id with placeholders.
# Usage: cat output.txt | bash normalize.sh
sed -E \
  's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z/<TIMESTAMP>/g' |
sed -E 's/pid=[0-9]+/pid=<PID>/g' |
sed -E 's/issue_id=[a-zA-Z0-9-]+/issue_id=<ISSUE_ID>/g'
