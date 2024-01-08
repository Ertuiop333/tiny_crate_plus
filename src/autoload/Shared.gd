extends Node

onready var node_ghost := $Ghost
onready var node_ghosts := $Ghosts
var ghosts := []
var ghost_count := 3

var node_map_solid : TileMap
var node_camera_game : Camera2D
var obscure_map

var is_quit := false
var is_level_select := false
var is_in_game := false

var map_dir := "res://src/map/"
var main_menu_path := "res://src/menu/StartMenu.tscn"
var options_menu_path := "res://src/menu/options/OptionsMenu.tscn"
var level_select_path := "res://src/menu/select.tscn"
var win_screen_path := "res://src/menu/WinScreen.tscn"
var credits_path := "res://src/menu/credits.tscn"
var splash_path := "res://src/menu/splash.tscn"
var creator_path := "res://src/menu/Creator.tscn"
var scene_path := level_select_path

var save_data := {}
var save_maps := {}
var replays := {}
var save_filename := "box.save"

var window_scale := 1
var view_size := Vector2(228, 128)
var bus_volume = [10, 10, 10]

var actors := []
var player

var map_select := 0
var maps := []
var map_name := ""
var map_frame := 0
var replay := {"frames" : 0, "x" : [], "y": [], "sprite" : []}
var replaying := []
var replay_map := ""
var count_gems := 0
var count_notes := 0

var is_win := false
var is_note := false
var is_replay := false
var is_replay_note := false

var username := "crate_kid"
export (Array, Color) var palette := []
var player_colors = [8, 0, 11, 13]
var preset_palettes = [[7, 13, 6, 3], [8, 0, 11, 13], [11, 7, 9, 0], [12, 1, 7, 5], [9, 8, 12, 3]]

var scene_dict := {}
var save_slot := 0
var save_path := "user://save/0/"

func _ready():
	print("Shared._ready(): ")
	randomize()
	
	# create player
	player_colors = preset_palettes[randi() % preset_palettes.size()]
	username = generate_username()
	
	# ghosts
	for i in ghost_count:
		var g = node_ghost.duplicate()
		node_ghosts.add_child(g)
		ghosts.append(g)
	node_ghost.visible = false
	
	# scale window
	window_scale = floor(OS.get_screen_size().x / get_viewport().size.x)
	window_scale = max(1, floor(window_scale * 0.9))
	set_window_scale()
	
	# lower volume
	for i in [1, 2]:
		set_bus_volume(i, 7)
	
	# get all maps
	for i in dir_list(map_dir):
		scene_dict[map_dir + i] = load(map_dir + i)
		maps.append(i.split(".")[0])
	print("maps: ", maps, " ", maps.size(), " ", scene_dict)
	
	var dir = Directory.new()
	if !dir.open("user://save") == OK:
		dir.make_dir("user://save")
	for i in 3:
		var s = "user://save/" + str(i)
		if !dir.open(s) == OK:
			dir.make_dir(s)
	
	# load save data
	load_save()
	load_replays()
	count_score()
	
	Wipe.connect("finish", self, "wipe_finish")

func _physics_process(delta):
	if is_in_game:
		# map time
		if !Pause.is_paused:
			map_frame += 1
			
			for i in ghosts.size():
				var g = ghosts[i]
				if i < replaying.size():
					var r = replaying[i]
					if r.has_all(["frames", "x", "y", "sprite"]) and map_frame < r["frames"]:
						var px = g.position.x
						var new_pos = Vector2(r["x"][map_frame], r["y"][map_frame])
						g.position = new_pos
						g.frame = r["sprite"][map_frame]
						
						if px != new_pos.x:
							g.flip_h = new_pos.x < px
					else:
						g.visible = false
			
			if is_instance_valid(player) and !is_win:
				replay["frames"] += 1
				replay["x"].append(player.position.x)
				replay["y"].append(player.position.y)
				replay["sprite"].append(player.node_sprite.frame)

### Changing Maps

func wipe_scene(arg := scene_path, timer := 0.0):
	if timer > 0.0: yield(get_tree().create_timer(timer), "timeout")
	scene_path = arg
	Wipe.start()
	Pause.set_process_input(false)

func wipe_quit():
	is_quit = true
	Wipe.start()

func wipe_finish():
	if is_quit:
		get_tree().quit()
	else:
		change_map()

func change_map():
	count_score()
	save()
	if is_win:
		save_replays()
	
	if !scene_dict.has(scene_path):
		scene_dict[scene_path] = load(scene_path)
	get_tree().change_scene_to(scene_dict[scene_path])
	
	is_win = false
	is_level_select = scene_path == level_select_path
	is_in_game = scene_path.begins_with(map_dir)
	map_name = "" if !is_in_game else scene_path.split("/")[-1].trim_suffix(".tscn")
	map_frame = 0
	replay = {"frames" : 0, "x" : [], "y" : [], "sprite" : []}
	replaying = []
	for i in ghosts:
		i.visible = false
	
	Pause.set_process_input(true)
	is_note = false
	UI.notes.visible = is_level_select
	UI.notes_label.text = str(count_notes)
	UI.gems.visible = is_level_select
	UI.gems_label.text = str(count_gems)
	UI.keys(false, false)
	UI.labels("pick", "erase" if scene_path == creator_path else "back", "score" if is_level_select else "menu")
	
	if is_in_game:
		TouchScreen.turn_arrows(false)
		TouchScreen.show_keys(true, true, true, true, true)
		
		if is_replay or is_replay_note:
			var m = map_name + ("-note" if is_replay_note else "")
		
			if replays.has(m):
				replays[m].sort_custom(self, "sort_replays")
				
				for i in min(3, replays[m].size()):
					var r = replays[m][i].duplicate()
					if r.has_all(["frames", "x", "y", "sprite"]):
						replaying.append(r)
						ghosts[i].visible = true
		
	elif is_level_select:
		is_replay = false
		is_replay_note = false
		UI.keys(true, true, true, true)
		TouchScreen.turn_arrows(false)
		TouchScreen.show_keys(true, true, true, true)
	elif scene_path == main_menu_path:
		UI.keys(true, true, false)
		TouchScreen.turn_arrows(true)
		TouchScreen.show_keys(true, false, true)
	elif scene_path == options_menu_path:
		UI.keys()
		TouchScreen.turn_arrows(true)
		TouchScreen.show_keys()
	elif scene_path == credits_path:
		UI.keys(false, true)
		TouchScreen.show_keys(false, true, false)
	elif scene_path == creator_path:
		UI.keys(true, true, false)

### Saving and Loading

func save_file(fname, arg):
	var file = File.new()
	file.open(str(fname), File.WRITE)
	file.store_string(arg)
	file.close()

func load_file(fname = ""):
	var file = File.new()
	file.open(str(fname), File.READ)
	var content = file.get_as_text()
	file.close()
	return content

func save():
	save_file(save_path + save_filename, JSON.print(save_data, "\t"))

func save_replays(arg := replay_map):
	save_file(save_path + arg + ".save", JSON.print(replays[arg], "\t"))

func load_save():
	var l = load_file(save_path + save_filename)
	if l:
		var p = JSON.parse(l).result
		if p is Dictionary:
			save_data = p
			
			# remove old keys
			for i in ["replays", "map", "notes", "times", "deaths"]:
				if save_data.has(i):
					save_data.erase(i)
			
			if save_data.has("username"):
				username = save_data["username"]
				
			if save_data.has("player_colors"):
				player_colors = save_data["player_colors"]
			
			if save_data.has("maps"):
				save_maps = save_data["maps"]
			
		else:
			create_save()
	else:
		print(save_path + save_filename + " not found")
		create_save()

func load_replays():
	for i in dir_list(save_path):
		var l = load_file(save_path  + i)
		if l:
			var p = JSON.parse(l).result
			if p is Array and p[0] is Dictionary and p[0].has("frames"):
				replays[i.split(".")[0]] = p
		else:
			print(save_path + i + " not found")

func generate_username():
	var u = ""
	var prefix = "crate box block square rect pack cube stack throw jump jumpin climb thinky brain spike skull pixel puzzle pico"
	var middle = [" ", "_", "-", "."]
	var suffix = "kid dude dood pal friend bud buddy guy gal boy girl homie person human robot cyborg man woman cousin cuz head face butt fart arms legs body hands feet mind"
	var pf : Array = prefix.split(" ", false)
	var sf : Array = suffix.split(" ", false)
	pf.shuffle()
	sf.shuffle()
	var end = middle.duplicate()
	end.append("")
	middle.shuffle()
	end.shuffle()
	var _name = pf[0] + middle[0] + sf[0] + end[0] + str(randi() % 100)
	return _name

func delete_save():
	print("delete save")
	create_save()

func create_save():
	save_data = {}
	save_data["map"] = 0
	save_data["notes"] = {}
	save_data["times"] = {}
	save_data["username"] = username
	save_data["player_colors"] = player_colors
	save()

func unlock():
	# nothing
	save()

func win():
	is_win = true
	
	# map
	if !save_maps.has(map_name):
		save_maps[map_name] = {}
	var s = save_maps[map_name]
	
	var hn = s.has("note")
	if is_note and (!hn or(hn and map_frame < s["note"])):
		s["note"] = map_frame
	
	var ht = s.has("time")
	if !ht or (ht and map_frame < s["time"]):
		s["time"] = map_frame
	
	save_data["maps"] = save_maps
	save_data["username"] = username
	
	# replays
	var m = map_name + ("-note" if is_note else "")
	replay_map = m
	
	if !replays.has(m):
		replays[m] = []
	replays[m].append(replay)
	replays[m].sort_custom(self, "sort_replays")
	if replays[m].size() > 5:
		replays[m].resize(5)
	
	print("map complete")
	
	Leaderboard.submit_score(m, -map_frame)
	
	wipe_scene(level_select_path)

func count_score():
	count_gems = 0
	count_notes = 0
	for i in save_maps.values():
		if i.has("time"): count_gems += 1
		if i.has("note"): count_notes += 1

func sort_replays(a, b):
	if a["frames"] < b["frames"]:
		return true
	return false

func die():
	if !save_maps.has(map_name):
		save_maps[map_name] = {}
	var s = save_maps[map_name]
	if !s.has("die"):
		s["die"] = 1
	else:
		s["die"] += 1
	
	Leaderboard.submit_score("death", 1)
	Leaderboard.submit_score("death", 1, map_name)
	print("you died")

# look into a folder and return a list of filenames without file extension
func dir_list(path : String):
	var array = []
	var dir = Directory.new()
	if dir.open(path) == OK:
		dir.list_dir_begin(true, true)
		var file_name = dir.get_next()
		while file_name:
			array.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	array.sort()
	return array

### Options

func set_bus_volume(_bus := 1, _vol := 5):
	bus_volume[_bus] = clamp(_vol, 0, 10)
	AudioServer.set_bus_volume_db(_bus, linear2db(bus_volume[_bus] / 10.0))

func set_window_scale(arg := window_scale):
	window_scale = max(1, arg if arg else window_scale)
	if OS.get_name() != "HTML5":
		OS.window_size = Vector2(view_size.x * window_scale, view_size.y * window_scale)
		# center window
		OS.set_window_position(OS.get_screen_size() * 0.5 - OS.get_window_size() * 0.5)
	return "window_scale: " + str(window_scale) + " - resolution: " + str(OS.get_window_size())

func get_all_children(n, a := []):
	if is_instance_valid(n):
		a.append(n)
		for i in n.get_children():
			a = get_all_children(i, a)
	return a
