extends Node
## Economy (autoload): the crew's shared wallets, host-authoritative and
## replicated over the WebRTC mesh.
##
##  - cash:    the run bank the quota is measured against (HUD-bound).
##  - tickets: the shop currency spent at the truck.
##
## Sync model: truth lives on the HOST (peer 1). Any peer may REQUEST a
## change via @rpc("any_peer", "call_local", "reliable") — the request
## executes on every peer, but only the host's execution mutates state,
## after which the host broadcasts ABSOLUTE values with an authority RPC.
## Absolute-value echoes (never deltas) make the system self-healing: any
## divergence is overwritten by the next broadcast. Under the default
## OfflineMultiplayerPeer these same RPCs run purely locally, so
## single-player uses this exact code path with no session.
##
## The Phase 4 public API (deposit_cash / try_spend_tickets / grant_tickets)
## is unchanged — callers never see the network.

signal cash_changed(balance: int)
signal tickets_changed(balance: int)

const STARTING_TICKETS := 100
## Sanity clamp per request: a desynced or hostile peer can't swing the
## bank further than one house-limit-scale event per call.
const MAX_SINGLE_DELTA := 100_000

var cash := 0:
	set(value):
		cash = maxi(value, 0)
		cash_changed.emit(cash)

var tickets := STARTING_TICKETS:
	set(value):
		tickets = maxi(value, 0)
		tickets_changed.emit(tickets)

## Total cash ever deposited this save — feeds QuotaMath greed scaling.
var lifetime_earned := 0
## Total quota paid off so far — subtracts from the greed surplus.
var quota_paid := 0


## --- Public API (unchanged since Phase 4) --------------------------------


func deposit_cash(amount: int) -> void:
	if amount > 0:
		rpc_request_cash_delta.rpc(amount, "deposit")


func try_spend_tickets(cost: int) -> bool:
	if cost < 0 or cost > tickets:
		return false
	rpc_request_ticket_delta.rpc(-cost)
	if not multiplayer.is_server():
		# Optimistic local prediction; the host's absolute echo is truth.
		tickets -= cost
	return true


func grant_tickets(amount: int) -> void:
	if amount > 0:
		rpc_request_ticket_delta.rpc(amount)


func pay_quota(amount: int) -> void:
	if amount > 0:
		rpc_request_quota_payment.rpc(amount)


## --- Request RPCs (any peer asks, only the host decides) -----------------


@rpc("any_peer", "call_local", "reliable")
func rpc_request_cash_delta(amount: int, _reason: String) -> void:
	if not multiplayer.is_server():
		return
	amount = clampi(amount, -MAX_SINGLE_DELTA, MAX_SINGLE_DELTA)
	cash += amount
	if amount > 0:
		lifetime_earned += amount
	_broadcast()


@rpc("any_peer", "call_local", "reliable")
func rpc_request_ticket_delta(amount: int) -> void:
	if not multiplayer.is_server():
		return
	if amount < 0 and -amount > tickets:
		# Can't afford: reject silently; the echo below corrects any
		# optimistic client prediction.
		_broadcast()
		return
	tickets += clampi(amount, -MAX_SINGLE_DELTA, MAX_SINGLE_DELTA)
	_broadcast()


@rpc("any_peer", "call_local", "reliable")
func rpc_request_quota_payment(amount: int) -> void:
	if not multiplayer.is_server() or amount <= 0 or amount > cash:
		return
	cash -= amount
	quota_paid += amount
	_broadcast()


## --- Authority sync (host publishes absolute truth) ----------------------


@rpc("authority", "call_local", "reliable")
func rpc_sync_wallets(cash_value: int, tickets_value: int,
		lifetime_value: int, quota_paid_value: int) -> void:
	cash = cash_value
	tickets = tickets_value
	lifetime_earned = lifetime_value
	quota_paid = quota_paid_value


## Time Machine hook: authoritative overwrite during a rollback, bypassing
## the request path (TableRng already validated on the host).
func apply_authoritative(cash_value: int, tickets_value: int,
		lifetime_value: int, quota_paid_value: int) -> void:
	cash = cash_value
	tickets = tickets_value
	lifetime_earned = lifetime_value
	quota_paid = quota_paid_value


func _broadcast() -> void:
	rpc_sync_wallets.rpc(cash, tickets, lifetime_earned, quota_paid)
