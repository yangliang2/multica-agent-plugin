# Multica CLI Reference

> Generated: 2026-05-23
> Source: `multica --help` and subcommand help output (live binary at `/usr/local/bin/multica`)

---

## multica

```
Work seamlessly with Multica from the command line.

USAGE
  multica <command> <subcommand> [flags]

CORE COMMANDS
  agent:      Work with agents
  autopilot:  Manage autopilots (scheduled/triggered agent automations)
  issue:      Work with issues
  label:      Work with issue labels
  project:    Work with projects
  repo:       Work with repositories
  skill:      Work with skills
  squad:      Work with squads
  workspace:  Work with workspaces

RUNTIME COMMANDS
  daemon:   Control the local agent runtime daemon
  runtime:  Work with agent runtimes

ADDITIONAL COMMANDS
  attachment:  Work with attachments
  auth:        Authenticate multica with Multica
  config:      Manage configuration for multica
  login:       Authenticate and set up workspaces
  setup:       Configure the CLI, authenticate, and start the daemon
  update:      Update multica to the latest version
  user:        Work with your user account
  version:     Print version information

FLAGS
  -h, --help                  help for multica
      --profile string        Configuration profile name (e.g. dev) — isolates config, daemon state, and workspaces
      --server-url string     Multica server URL (env: MULTICA_SERVER_URL)
  -v, --version               version for multica
      --workspace-id string   Workspace ID (env: MULTICA_WORKSPACE_ID)

EXAMPLES
  $ multica login
  $ multica issue list --output json
  $ multica daemon start
  $ multica agent list --output json

ENVIRONMENT VARIABLES
  MULTICA_SERVER_URL    Override the default server URL
  MULTICA_WORKSPACE_ID  Set the active workspace

LEARN MORE
  Use `multica <command> <subcommand> --help` for more information about a command.
```

---

## multica issue

```
Work with issues

USAGE
  multica issue <command> [flags]

COMMANDS
  assign:        Assign an issue to a member, agent, or squad
  cancel-task:   Cancel a running or queued task (interrupts in-flight agent)
  comment:       Work with issue comments
  create:        Create a new issue
  get:           Get issue details
  label:         Manage labels on an issue
  list:          List issues in the workspace
  rerun:         Re-enqueue an issue's current agent assignment as a fresh task
  run-messages:  List messages for an execution
  runs:          List execution history for an issue
  search:        Search issues by title or description
  status:        Change issue status
  subscriber:    Work with issue subscribers
  update:        Update an issue

INHERITED FLAGS
  --help   Show help for command

LEARN MORE
  Use `multica issue <command> --help` for more information about a command.
```

---

## multica issue get

```
Get issue details

USAGE
  multica issue get <id> [flags]

FLAGS
  -h, --help            help for get
      --output string   Output format: table or json (default "json")

INHERITED FLAGS
  --help   Show help for command

LEARN MORE
  Use `multica <command> <subcommand> --help` for more information about a command.
```

**Examples:**

```bash
multica issue get MUL-123
multica issue get MUL-123 --output json
multica issue get 5fb87ac7-23b5-4a7a-81fa-ed295a54545d
```

---

## multica issue comment

```
Work with issue comments

USAGE
  multica issue comment <command> [flags]

COMMANDS
  add:     Add a comment to an issue
  delete:  Delete a comment
  list:    List comments on an issue

INHERITED FLAGS
  --help   Show help for command

LEARN MORE
  Use `multica issue comment <command> --help` for more information about a command.
```

---

## multica issue comment add

```
Add a comment to an issue

USAGE
  multica issue comment add <issue-id> [flags]

FLAGS
      --attachment strings    File path(s) to attach (can be specified multiple times)
      --content string        Comment content (decodes \n, \r, \t, \\; pipe via --content-stdin for multi-line bodies or to preserve literal backslashes)
      --content-file string   Read comment content from a UTF-8 file (preserves multi-line content verbatim; use this on Windows when stdin piping mangles non-ASCII bytes)
      --content-stdin         Read comment content from stdin (preserves multi-line content verbatim)
  -h, --help                  help for add
      --output string         Output format: table or json (default "json")
      --parent string         Parent comment ID (reply to a specific comment)

INHERITED FLAGS
  --help   Show help for command

LEARN MORE
  Use `multica <command> <subcommand> --help` for more information about a command.
```

**Examples:**

```bash
# Simple comment
multica issue comment add MUL-123 --content "Looks good, merging now"

# Reply to a specific comment
multica issue comment add MUL-123 --parent <comment-id> --content "Thanks!"

# Multi-line comment from stdin
echo "Line 1\nLine 2" | multica issue comment add MUL-123 --content-stdin

# Comment from a file
multica issue comment add MUL-123 --content-file ./report.md

# Comment with attachment
multica issue comment add MUL-123 --content "See attached" --attachment ./screenshot.png
```

---

## multica issue status

```
Change issue status

USAGE
  multica issue status <id> <status> [flags]

FLAGS
  -h, --help            help for status
      --output string   Output format: table or json (default "table")

INHERITED FLAGS
  --help   Show help for command

LEARN MORE
  Use `multica <command> <subcommand> --help` for more information about a command.
```

**Valid statuses:** `backlog`, `todo`, `in_progress`, `in_review`, `done`, `blocked`, `cancelled`

**Examples:**

```bash
multica issue status MUL-123 in_progress
multica issue status MUL-123 done
multica issue status MUL-123 blocked --output json
```

---

## Quick Reference: Issue Workflow

```bash
# List issues
multica issue list
multica issue list --status in_progress --output json
multica issue list --metadata pipeline_status=waiting_review

# Get issue
multica issue get <id>
multica issue get <id> --output json

# Create issue
multica issue create --title "Fix login bug" --description "..." --priority high --assignee "Lambda"

# Update issue
multica issue update <id> --title "New title" --priority urgent

# Assign issue
multica issue assign <id> --to "Lambda"
multica issue assign <id> --to-id <uuid>
multica issue assign <id> --unassign

# Change status
multica issue status <id> in_progress

# List comments (flat)
multica issue comment list <issue-id>

# List comments (single thread)
multica issue comment list <issue-id> --thread <comment-id>

# List comments (most recent threads)
multica issue comment list <issue-id> --recent 20

# Add comment
multica issue comment add <issue-id> --content "message"

# Reply to comment
multica issue comment add <issue-id> --parent <comment-id> --content "reply"

# Delete comment
multica issue comment delete <comment-id>

# Metadata
multica issue metadata list <issue-id>
multica issue metadata get <issue-id> --key pipeline_status
multica issue metadata set <issue-id> --key pipeline_status --value waiting_review
multica issue metadata delete <issue-id> --key pipeline_status
```

---

## Anchor Index

The following anchors are available for use with `tools/render-anchors.sh`:

| Anchor | Description |
|--------|-------------|
| `<<cli:issue.get>>` | `multica issue get <id>` |
| `<<cli:issue.comment.add>>` | `multica issue comment add <issue-id> --content "..."` |
| `<<cli:issue.comment.list>>` | `multica issue comment list <issue-id>` |
| `<<cli:issue.status>>` | `multica issue status <id> <status>` |
| `<<cli:issue.list>>` | `multica issue list` |
| `<<cli:issue.create>>` | `multica issue create --title "..." --assignee "..."` |
| `<<cli:issue.assign>>` | `multica issue assign <id> --to "..."` |
| `<<cli:issue.metadata.set>>` | `multica issue metadata set <issue-id> --key <k> --value <v>` |
| `<<cli:squad.activity>>` | `multica squad activity <issue-id> <outcome> --reason "..."` — outcomes: `action`, `no_action`, `failed` |
| `<<cli:issue.create.child>>` | `multica issue create --title "..." --status todo --assignee-id <uuid>` |
| `<<cli:issue.comment.list.thread>>` | `multica issue comment list <issue-id> --thread <comment-id> --tail 30 --output json` |
