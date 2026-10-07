# Read-only checkpoint observer; all scheduling still delegates to the production scheduler.
extends RuleScheduler

var observed: Array = []

func checkpoint(context: RefCounted, stage: String) -> bool:
	var result = await super.checkpoint(context, stage)
	if context is EffectChain and stage == "damage_applied:after":
		observed.append({"source": context.damage.source, "target": context.damage.target, "committed": context.damage.committed})
	return result
