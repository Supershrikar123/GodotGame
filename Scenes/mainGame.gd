extends Control

# ============================================================
#  WORDHACK — Wordle-style roguelite
# ============================================================
#  8 systems ("blinds"), each with a score target.
#  Reach the target within N passwords to clear the system.
#  Fail = lose a life. 0 lives = run over. Clear all 8 = win.
# ============================================================

const WORDS = [
	"PASS", "123", "WORD", "A1", "B2", "QWERTY", "ADMIN", "ROOT",
	"LOGIN", "SUDO", "KEY", "0X1F", "NULL", "SHELL", "ZERO", "HACK",
	"TOKEN", "PORT", "BYTE", "ROUTE"
]

# --- Balance ---------------------------------------------------
# Tuned so that a row-1 crack needs: 1,2,2,2,3,3,3,3 cracks.
const TARGETS       = [250, 550, 700, 800, 1050, 1250, 1500, 1700]
const TRIES_BASE    = 5      # passwords per system
const SPARE_TRY_BONUS = 50   # points per unused password on clear
const START_CHANCES = 3
const MAX_CHANCES   = 5
const FOG_LEVEL     = 5      # from this system on, yellow is hidden

const CODE_LENGTH   = 5
const HAND_SIZE     = 8

# Scoring: points = (BASE + level*LVL_BONUS + rows_left*ROW_BONUS) * mult
const SCORE_BASE        = 100
const SCORE_LEVEL_BONUS = 60
const SCORE_ROW_BONUS   = 40

const GREEN  = Color("8fd37a")
const YELLOW = Color("e6c84a")
const GREY   = Color("5c5c5c")
const SAVE_PATH = "user://wordhack_best.save"

const PERKS = {
	"chance": "+1 LIFE",
	"try":    "+1 PASSWORD",
	"purge":  "-1 DECOY",
	"leak":   "+1 LEAK",
	"score":  "+50% SCORE",
	"row":    "+1 ROW",
}

# --- State -----------------------------------------------------
var secret = []
var placed = []       # [{"word": String, "card": Button}, ...]
var offered = []      # perk ids on offer
var hint = ""
var row = 0
var level = 1
var target = 0
var system_score = 0
var tries_left = 0
var chances = START_CHANCES
var score = 0
var best_score = 0
var rows_allowed = 4
var max_rows = 4
var message = ""
var state = "play"    # play | grading | next | perk | retry | dead | won

# --- Upgrades (reset each run) ---------------------------------
var extra_tries = 0
var purge = 0
var leaks = 0
var extra_rows = 0
var multiplier = 1.0

@onready var grid         = find_child("GuessGrid", true, false)
@onready var hand_box     = find_child("HandBox", true, false)
@onready var crack_button = find_child("CrackButton", true, false)
@onready var title_label  = find_child("Label", true, false)
@onready var status_label = find_child("StatusLabel", true, false)


func _ready():
	randomize()
	load_best()
	max_rows = floori(grid.get_child_count() / float(CODE_LENGTH))

	# Pad hand up to HAND_SIZE by cloning the template card.
	if hand_box.get_child_count() > 0:
		var template = hand_box.get_child(0)
		while hand_box.get_child_count() < HAND_SIZE:
			hand_box.add_child(template.duplicate())

	for card in hand_box.get_children():
		card.pressed.connect(on_card_pressed.bind(card))
	for i in grid.get_child_count():
		grid.get_child(i).pressed.connect(on_slot_pressed.bind(i))
	crack_button.pressed.connect(on_crack_pressed)
	new_run()


func _unhandled_input(event):
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_BACKSPACE and state == "play" and placed.size() > 0:
		placed.pop_back()
		redraw_row()
	elif event.keycode == KEY_ENTER and state == "play":
		on_crack_pressed()


# ---------- helpers ----------

func final_level() -> int:
	return TARGETS.size()

func row_of(slot_index: int) -> int:
	return floori(slot_index / float(CODE_LENGTH))

func calc_rows(lvl: int) -> int:
	var base = 4 if lvl < 3 else 3
	return min(max_rows, base + extra_rows)

func pop(node: Node):
	node.pivot_offset = node.size / 2.0
	node.scale = Vector2(1.12, 1.12)
	create_tween().tween_property(node, "scale", Vector2.ONE, 0.12)

func load_best():
	if FileAccess.file_exists(SAVE_PATH):
		var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			best_score = f.get_32()

func save_best():
	if score > best_score:
		best_score = score
		var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_32(best_score)


# ---------- runs / systems / passwords ----------

func new_run():
	level = 1
	chances = START_CHANCES
	score = 0
	extra_tries = 0
	purge = 0
	leaks = 0
	extra_rows = 0
	multiplier = 1.0
	start_system()


func start_system():
	rows_allowed = calc_rows(level)
	target = TARGETS[level - 1]
	system_score = 0
	tries_left = TRIES_BASE + extra_tries
	new_password()
	message = "SYSTEM %d ONLINE — REACH %d POINTS." % [level, target]
	if level >= FOG_LEVEL:
		message += "  FOG: YELLOW DISABLED."
	update_status()


func new_password():
	state = "play"
	row = 0
	placed.clear()

	# Hand = 5 real code words + decoys, shuffled together.
	var pool = WORDS.duplicate()
	pool.shuffle()
	secret = pool.slice(0, CODE_LENGTH)
	var hand_words = pool.slice(0, hand_box.get_child_count())
	hand_words.shuffle()

	# DECOY purge: replace some decoy cards with blank slots.
	var decoys_to_remove = purge
	var cards = hand_box.get_children()
	for i in cards.size():
		var word = hand_words[i]
		var purged = false
		if decoys_to_remove > 0 and not secret.has(word):
			purged = true
			decoys_to_remove -= 1
		cards[i].visible = true
		cards[i].set_meta("word", word)
		cards[i].set_meta("purged", purged)
		cards[i].text = "[ ---- ]" if purged else "[ " + word + " ]"
	refresh_cards()

	# LEAK: reveal a few slot→word mappings.
	hint = ""
	if leaks > 0:
		var idxs = [0, 1, 2, 3, 4]
		idxs.shuffle()
		var parts = []
		for k in min(leaks, CODE_LENGTH):
			parts.append("S%d=%s" % [idxs[k] + 1, secret[idxs[k]]])
		hint = "LEAK: " + " ".join(parts)

	for i in grid.get_child_count():
		var slot = grid.get_child(i)
		slot.text = ""
		slot.self_modulate = Color.WHITE
		slot.scale = Vector2.ONE
		slot.modulate = Color(1, 1, 1, 1) if row_of(i) < rows_allowed \
			else Color(1, 1, 1, 0.25)

	crack_button.disabled = false
	crack_button.text = "INITIATE CRACK"
	message = "NEW PASSWORD — %d POINTS TO GO." % max(0, target - system_score)
	update_status()


func update_status():
	var guess_number = min(row + 1, rows_allowed)
	var line1 = "SYSTEM %d/%d   SCORE %d/%d   PASSWORDS %d   GUESS %d/%d" % [
		level, final_level(), system_score, target,
		tries_left, guess_number, rows_allowed
	]
	var line2 = "LIVES %d   TOTAL %d   BEST %d   MULT x%.1f" % [
		chances, score, best_score, multiplier
	]
	var line3 = message
	if hint != "" and state == "play":
		line3 += "   " + hint
	var text = line1 + "\n" + line2 + "\n" + line3
	if status_label:
		status_label.text = text
	else:
		title_label.text = text


# ---------- row / cards ----------

func refresh_cards():
	for card in hand_box.get_children():
		var used = false
		for p in placed:
			if p["card"] == card:
				used = true
				break
		card.disabled = card.get_meta("purged", false) or used


func redraw_row():
	for i in CODE_LENGTH:
		var slot = grid.get_child(row * CODE_LENGTH + i)
		slot.text = placed[i]["word"] if i < placed.size() else ""
	refresh_cards()


func on_card_pressed(card):
	if state == "perk":
		choose_perk(card.get_index())
		return
	if state != "play" or placed.size() >= CODE_LENGTH:
		return
	if card.get_meta("purged", false):
		return
	placed.append({"word": card.get_meta("word"), "card": card})
	redraw_row()
	pop(grid.get_child(row * CODE_LENGTH + placed.size() - 1))


func on_slot_pressed(slot_index):
	if state != "play" or row_of(slot_index) != row:
		return
	var idx = slot_index % CODE_LENGTH
	if idx < placed.size():
		placed.remove_at(idx)
		redraw_row()


func on_crack_pressed():
	match state:
		"next":          new_password()
		"retry":         start_system()
		"dead", "won":   new_run()
		"play":
			if placed.size() < CODE_LENGTH:
				message = "FILL ALL %d SLOTS FIRST." % CODE_LENGTH
				update_status()
			else:
				grade_row()


# ---------- grading ----------

func grade_row():
	state = "grading"
	var hits = 0
	var misplaced = 0
	var fog = level >= FOG_LEVEL
	var graded_row = row

	for i in CODE_LENGTH:
		var slot = grid.get_child(graded_row * CODE_LENGTH + i)
		var word = placed[i]["word"]
		if word == secret[i]:
			slot.self_modulate = GREEN
			hits += 1
		elif secret.has(word) and not fog:
			slot.self_modulate = YELLOW
			misplaced += 1
		else:
			slot.self_modulate = GREY
		pop(slot)
		await get_tree().create_timer(0.12).timeout

	row += 1
	placed.clear()
	refresh_cards()

	if hits == CODE_LENGTH:
		var remaining = rows_allowed - row
		var points = int((
			SCORE_BASE
			+ level * SCORE_LEVEL_BONUS
			+ remaining * SCORE_ROW_BONUS
		) * multiplier)
		system_score += points
		finish_password("CRACKED! +%d" % points)
	elif row >= rows_allowed:
		finish_password("TRACED! CODE WAS: " + " ".join(secret))
	else:
		state = "play"
		message = "%d CORRECT, %d MISPLACED. FOG HIDES THE REST." \
			% [hits, misplaced] if fog \
			else "%d CORRECT, %d MISPLACED." % [hits, misplaced]
		update_status()


func finish_password(result_text: String):
	tries_left -= 1
	message = result_text
	if system_score >= target:
		clear_system()
	elif tries_left <= 0:
		fail_system()
	else:
		state = "next"
		crack_button.text = "NEXT PASSWORD >"
		message += "   %d TO GO." % (target - system_score)
		update_status()


func clear_system():
	var bonus = tries_left * SPARE_TRY_BONUS
	score += system_score + bonus
	save_best()

	message = "SYSTEM CLEARED!"
	if bonus > 0:
		message += "  SPARE PASSWORDS +%d." % bonus

	if level >= final_level():
		state = "won"
		message = "MAINFRAME BREACHED!  FINAL SCORE %d." % score
		crack_button.text = "NEW RUN"
		update_status()
	else:
		offer_perks()


func fail_system():
	chances -= 1
	if chances <= 0:
		save_best()
		state = "dead"
		message = "LOCKED OUT AT SYSTEM %d.  FINAL SCORE %d." % [level, score]
		crack_button.text = "RESTART RUN"
	else:
		state = "retry"
		message += "   TARGET MISSED — LOSE 1 LIFE."
		crack_button.text = "RETRY SYSTEM"
	update_status()


# ---------- upgrades ----------

func offer_perks():
	var options = []
	if chances < MAX_CHANCES:            options.append("chance")
	if extra_tries < 2:                  options.append("try")
	if purge < HAND_SIZE - CODE_LENGTH:  options.append("purge")
	if leaks < 3:                        options.append("leak")
	options.append("score")
	if calc_rows(level + 1) < max_rows:  options.append("row")
	options.shuffle()
	offered = options.slice(0, 3)

	state = "perk"
	var cards = hand_box.get_children()
	for i in cards.size():
		if i < offered.size():
			cards[i].text = "[ " + PERKS[offered[i]] + " ]"
			cards[i].disabled = false
		else:
			cards[i].visible = false
	crack_button.text = "CHOOSE AN UPGRADE"
	crack_button.disabled = true
	message += "  PICK AN UPGRADE."
	update_status()


func choose_perk(i: int):
	if i >= offered.size():
		return
	match offered[i]:
		"chance": chances = min(MAX_CHANCES, chances + 1)
		"try":    extra_tries += 1
		"purge":  purge += 1
		"leak":   leaks += 1
		"score":  multiplier += 0.5
		"row":    extra_rows += 1
	level += 1
	start_system()
