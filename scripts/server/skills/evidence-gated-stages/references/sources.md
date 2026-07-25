# Sources (research grounding)

Load when authoring or auditing this skill; cite in RESEARCH sections when
adapting gates. Prefer primary docs over secondary blogs.

## Agent Skills format (progressive disclosure)

| Source | Use |
|--------|-----|
| [Agent Skills overview](https://agentskills.io/home) | Discovery → activation → resources |
| [Adding skills support](https://agentskills.io/client-implementation/adding-skills-support) | ~100 tok catalog; SKILL body on demand; refs/scripts later |
| [Cursor Agent Skills docs](https://cursor.com/docs/skills) | `name`/`description`/`paths`; keep SKILL lean |
| [Cursor agent best practices](https://cursor.com/blog/agent-best-practices) | Skills vs Rules; load on relevance |
| [Anthropic: Equipping agents with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) | Start from eval gaps; iterate description; split refs |
| [Anthropic skills platform overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview) | description = what + when; no XML in frontmatter |

**Authoring takeaways applied here:** description is the trigger; SKILL.md
under ~500 lines; one-level-deep `references/`; scripts for deterministic
checks; compose other skills instead of cloning.

## Verify-gated / admission control

| Source | Use |
|--------|-----|
| [arXiv:2605.17998](https://arxiv.org/abs/2605.17998) Verify-Gated Completion as Admission Control | Propose≠admit; read-only verifier; fail-closed φ; packetized evidence; claim grading; denominator hygiene |
| [agent-completion-gate STATE_MACHINE](https://github.com/zhjai/agent-completion-gate/blob/main/STATE_MACHINE.md) | Worker max = candidate_complete; canonical completion signal; hostile artifacts; overstep reject |

**Applied here:** see [propose-admit.md](propose-admit.md).

## Adjacent engineering practice

Continuous Delivery quality gates and IT decision rights — completion is a
**release/admission** decision, not a generative flourish. This skill adapts
that discipline to agent stages.

## Out of scope (do not overclaim)

The arXiv work is a bounded architecture case study — not proof that
verify-gating raises task success rates. This skill likewise claims
**inspectable fail-closed process**, not model quality or production SLOs.
