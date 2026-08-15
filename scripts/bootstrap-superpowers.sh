#!/bin/sh
set -eu

# Superpowers installation for various AI coding agents
# This script installs Superpowers skills for the current project

command -v git >/dev/null 2>&1 || {
    printf '%s\n' 'git is required.' >&2
    exit 1
}

# Create .opencode/skills directory if it doesn't exist
mkdir -p .opencode/skills

# Clone Superpowers skills (or copy from installed location)
# For now, create a minimal skill set for TDD and subagent-driven-development
cat > .opencode/skills/test-driven-development/SKILL.md << 'EOF'
# Test-Driven Development Skill

## When to use
- Before writing any implementation code
- When fixing bugs
- When refactoring

## Process
1. **RED**: Write a failing test that describes the desired behavior
2. **GREEN**: Write minimal code to make the test pass
3. **REFACTOR**: Improve code while keeping tests green

## Rules
- No implementation code without a failing test first
- Tests must be specific and test one behavior
- Delete code written before its test exists
- Run tests after every change

## Anti-patterns to avoid
- Writing tests after implementation
- Testing multiple behaviors in one test
- Skipping refactoring step
- Testing implementation details instead of behavior
EOF

cat > .opencode/skills/subagent-driven-development/SKILL.md << 'EOF'
# Subagent-Driven Development Skill

## When to use
- Implementing features with multiple independent tasks
- Complex features requiring parallel work
- When tasks can be verified independently

## Process
1. **PLAN**: Break work into 2-5 minute tasks with exact file paths and verification steps
2. **DISPATCH**: Launch fresh subagent per task with context
3. **REVIEW**: Two-stage review (spec compliance, then code quality)
4. **INTEGRATE**: Merge completed tasks, run full test suite

## Rules
- Each task must have: file paths, complete code, verification steps
- Subagents work in isolation with fresh context
- Two-stage review: spec compliance first, then code quality
- Critical issues block progress until resolved

## Task Template
- File paths to modify/create
- Exact code to write
- Verification command/test
- Dependencies on other tasks
EOF

cat > .opencode/skills/systematic-debugging/SKILL.md << 'EOF'
# Systematic Debugging Skill

## When to use
- Any bug, error, or unexpected behavior
- Performance issues
- Test failures

## 4-Phase Process
1. **REPRODUCE**: Create minimal reproduction, capture exact error
2. **ISOLATE**: Narrow down to specific component/file/function
3. **HYPOTHESIZE**: Form testable hypothesis about root cause
4. **VERIFY**: Test hypothesis, apply fix, verify fix works

## Techniques
- Root cause tracing (5 whys)
- Defense in depth (validate inputs at boundaries)
- Condition-based waiting (not time-based)
- Binary search on commit history for regressions

## Rules
- Never guess - always verify with evidence
- Fix root cause, not symptoms
- Add regression test for every bug fix
EOF

cat > .opencode/skills/writing-plans/SKILL.md << 'EOF'
# Writing Plans Skill

## When to use
- After design approval, before implementation
- Complex features with multiple components

## Plan Structure
Each task must include:
- **File paths**: Exact paths to create/modify
- **Code**: Complete implementation code
- **Verification**: Exact test/command to validate
- **Dependencies**: Other tasks this depends on

## Task Granularity
- 2-5 minutes per task
- One logical unit per task
- Independent verification possible

## Example Task
- **Files**: `collectors/opencode.lua`
- **Code**: [complete implementation]
- **Verify**: `lua collectors/test_opencode.lua`
- **Depends on**: protocol spec finalized
EOF

echo "Superpowers skills installed in .opencode/skills/"