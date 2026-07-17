class_name QuotaMath
## Dynamic quota scaling — the formula that punishes hoarding.
##
##   surplus = max(lifetime_earned − quota_paid, 0)
##   greed   = K · (surplus / R)^P
##   quota   = snap50( base_quota · (1 + greed) )
##
## with K = 0.35, P = 1.25, R = 10 000, snap50 = round UP to the next $50.
##
## Design properties:
##  - Only SURPLUS counts: cash you already surrendered to quota doesn't
##    haunt you — hoarded wealth does. Feeding the bank into the quota (or
##    losing it at the tables) is the only way to keep future quotas sane.
##  - P > 1 makes the punishment superlinear: doubling your hoard more
##    than doubles the greed term. The house notices winners.
##  - snap-up to $50 keeps targets readable on the HUD and guarantees the
##    displayed quota is never below the true requirement.
##
## Worked examples (base 5 000, i.e. Floor 1):
##   surplus      0 -> quota  5 000
##   surplus 10 000 -> quota  6 750   (greed = 0.35)
##   surplus 20 000 -> quota  9 200   (greed = 0.833)
##   surplus 50 000 -> quota 17 550   (greed = 2.616... it compounds)

const GREED_COEFF := 0.35
const GREED_POWER := 1.25
const GREED_REFERENCE := 10_000.0
const SNAP := 50


static func scaled_quota(base_quota: int, lifetime_earned: int, quota_paid: int) -> int:
	var surplus := maxf(float(lifetime_earned - quota_paid), 0.0)
	var greed := GREED_COEFF * pow(surplus / GREED_REFERENCE, GREED_POWER)
	return snap_up(float(base_quota) * (1.0 + greed))


static func snap_up(value: float) -> int:
	return int(ceilf(value / float(SNAP))) * SNAP
