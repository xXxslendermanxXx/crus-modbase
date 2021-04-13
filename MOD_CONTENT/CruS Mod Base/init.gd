extends Node

var MOD_NAME = "CruS Mod Base"
var Audio = load("res://MOD_CONTENT/" + MOD_NAME + "/GDScriptAudioImport.gd").new()
var loaded_level_names = []

func is_valid_level_json(m: Dictionary) -> bool:
	return m.has_all(["author", "version", "description", "objectives", "level_scene"])

func get_file_path(key: String, dict: Dictionary) -> String:
	var p = ""
	if !dict.has(key) or !dict.get(key): return p
	
	var f = File.new()
	if f.open(dict[key], File.READ) == OK or ResourceLoader.exists(dict[key]):
		p = dict[key]
	elif f.open("res://MOD_CONTENT/" + dict["name"] + "/" + dict[key], File.READ) == OK:
		p = "res://MOD_CONTENT/" + dict["name"] + "/" + dict[key]
	elif f.open("user://levels/" + dict["name"] + "/" + dict[key], File.READ) == OK:
		p = "user://levels/" + dict["name"] + "/" + dict[key]
	f.close()
	return p

func handle_level_data(lvl: Dictionary) -> bool:
	# handle tscn
	var scene_path = get_file_path("level_scene", lvl)
	if scene_path != "":
		G_Steam.mod_log("...found level scene at: " + scene_path, MOD_NAME)
		lvl["scene_path"] = scene_path
	else:
		G_Steam.mod_log("ERROR: Missing level scene!", MOD_NAME)
		return false
		
	# handle image
	var image_path = get_file_path("image", lvl)
	if image_path != "":
		G_Steam.mod_log("...found level preview image at: " + image_path, MOD_NAME)
		var img = Image.new()
		if image_path.begins_with("res://"):
			lvl["image"] = load(image_path)
		else:
			var err = img.load(image_path)
			if err == OK:
				var tex = ImageTexture.new()
				tex.create_from_image(img, 0)
				lvl["image"] = tex
			else:
				G_Steam.mod_log("WARNING: Failed to open level preview image at path: " + lvl.get("image"), MOD_NAME)
				lvl["image"] = null
	else:
		if lvl.get("image"):
			G_Steam.mod_log("WARNING: Couldn't get level preview image from path: " + lvl.get("image"), MOD_NAME)
		lvl["image"] = null

	# handle music
	var music_path = get_file_path("music", lvl)
	if music_path != "":
		G_Steam.mod_log("...found level music at: " + music_path, MOD_NAME)
		lvl["music"] = load(music_path) if music_path.begins_with("res://") else Audio.loadfile(music_path)
	else:
		if lvl.get("music"):
			G_Steam.mod_log("WARNING: Couldn't get level music from path: " + lvl.get("music"), MOD_NAME)
		lvl["music"] = null

	# handle ambience
	var amb_path = get_file_path("ambience", lvl)
	if amb_path != "":
		G_Steam.mod_log("...found level ambience track at: " + amb_path, MOD_NAME)
		lvl["ambience"] = load(amb_path) if amb_path.begins_with("res://") else Audio.loadfile(amb_path)
	else:
		if lvl.get("ambience"):
			G_Steam.mod_log("WARNING: Couldn't get level ambience track from path: " + lvl.get("ambience"), MOD_NAME)
		lvl["ambience"] = null
	
	# handle dialogue
	var dialogue_path = ""
	var dialogue_init = false
	if lvl.has("dialogue"):
		if lvl["dialogue"] is String:
			dialogue_path = get_file_path("dialogue", lvl)
		elif lvl["dialogue"] is float:
			G_Steam.mod_log("...level will use the dialogue from level " + str(lvl["dialogue"]), MOD_NAME)
			lvl["dialogue"] = int(lvl["dialogue"])
			dialogue_init = true
		elif lvl["dialogue"] is Array:
			if (lvl["dialogue"].size() > 0):
				G_Steam.mod_log("...loaded " + str(lvl["dialogue"].size()) + " lines of NPC dialogue", MOD_NAME)
				dialogue_init = true
			else:
				G_Steam.mod_log("Empty dialogue array!", MOD_NAME)
		else:
			G_Steam.mod_log("Invalid dialogue value, must be a string (Godot file path), string array (direct input) or integer (level number)", MOD_NAME)
	
	var f = File.new()
	if f.open(dialogue_path, File.READ) == OK:
		G_Steam.mod_log("...found dialogue file at: " + dialogue_path, MOD_NAME)
		var json = JSON.parse(f.get_as_text())
		if json.error == OK and json.result is Array:
			if json.result.size() == 0:
				G_Steam.mod_log("No lines of level dialogue in dialogue file!", MOD_NAME)
				f.close()
				return false
			lvl["dialogue"] = json.result
			G_Steam.mod_log("...loaded " + str(lvl["dialogue"].size()) + " lines of NPC dialogue", MOD_NAME)
			dialogue_init = true
		else:
			var err = json.error_string
			if !(json.result is Array):
				err = "file isn't an array"
			G_Steam.mod_log("Failed to parse dialogue file!" + " (line: " + str(json.error_line) + ", error: " + json.error_string + ")", MOD_NAME)
	else:
		G_Steam.mod_log("Failed to open dialogue file at: " + lvl["dialogue"], MOD_NAME)
	if !dialogue_init:
		G_Steam.mod_log("WARNING: Couldn't add dialogue, this level will have no NPC dialogue", MOD_NAME)
	f.close()
	return true

func load_level(current_dir: String, dir_name: String) -> Dictionary:
	var path = current_dir + "/" + dir_name
	G_Steam.mod_log("Scanning " + path, MOD_NAME)
	var dir = Directory.new()
	var lvl = null
	var files = []
	var loaded_count = 0
	var json_valid = false
	dir.open(path)
	dir.list_dir_begin(true, true)
	var fname = dir.get_next()
	while fname != "":
		var ext = fname.get_extension()
		if ext == "pck" or ext == "zip":
			files.append(dir.get_current_dir() + "/" + fname)
		elif fname == "level.json":
			lvl = {}
			var json = File.new()
			if json.open(dir.get_current_dir() + "/" + fname, File.READ) == OK:
				lvl = JSON.parse(json.get_as_text())
				if lvl.error == OK and lvl.result is Dictionary and is_valid_level_json(lvl.result):
					if lvl.result.has("name") and loaded_level_names.find(lvl.result.name) != -1:
						G_Steam.mod_log("WARNING: Level with name \"" + lvl.result.name + "\" already exists, not loading this level", MOD_NAME)
						return {}
					json_valid = true
				elif lvl.error != OK:
					match lvl.error:
						ERR_PARSE_ERROR: G_Steam.mod_log("ERROR: Problem on line " + str(lvl.error_line) + " of level.json in " + path, MOD_NAME)
						_: G_Steam.mod_log("ERROR: Unspecified, code " + lvl.error, MOD_NAME)
				elif !(lvl.result is Dictionary):
					G_Steam.mod_log("ERROR: JSON is not an object (not enclosed in {}) for level.json in " + path, MOD_NAME)
				elif !is_valid_level_json(lvl.result):
					G_Steam.mod_log("ERROR: Missing name, author, version, description, objectives, level_scene and/or image for level.json in " + path, MOD_NAME)
				json.close()
			else:
				G_Steam.mod_log("ERROR: Failed to open level.json!", MOD_NAME)
		fname = dir.get_next()
	if json_valid:
		for f in files:
			var loaded = ProjectSettings.load_resource_pack(f)
			if loaded:
				G_Steam.mod_log("...loaded " + f)
				loaded_count += 1
			else: G_Steam.mod_log("...failed to load " + f)
		if !lvl.result.has("name"):
			lvl.result["name"] = dir_name
		if !handle_level_data(lvl.result):
			loaded_count = -1
		return lvl.result if loaded_count > -1 else {}
	elif lvl == null:
		G_Steam.mod_log("ERROR: No level.json found!", MOD_NAME)
	return {}

func load_levels() -> Array:
	var levels = []
	var dir = Directory.new()
	if dir.open('user://') == OK:
		if !dir.dir_exists('user://levels'):
			dir.make_dir('user://levels')
		else:
			dir.change_dir('user://levels')
			dir.list_dir_begin(true, true)
			var fname = dir.get_next()
			while fname != "":
				if dir.current_is_dir():
					var cur_dir = dir.get_current_dir()
					var lvl = load_level(cur_dir, fname)
					if lvl.has("name"):
						levels.append(lvl)
						loaded_level_names.append(lvl.name)
						G_Steam.mod_log("Finished loading level \"" + lvl["name"] + "\" by \"" + lvl["author"] + "\"", MOD_NAME)
					else:
						G_Steam.mod_log("Couldn't load level!", MOD_NAME)
				fname = dir.get_next()
	return levels

func _init():
	G_Steam.mod_log("Loading user levels...", MOD_NAME)
	var data = G_Steam.MOD_DATA[MOD_NAME]
	data["levels"] = load_levels()
	if data["levels"].size() > 0:
		G_Steam.mod_log("LEVEL LOADING COMPLETE: Successfully loaded " + str(data["levels"].size()) + " level(s)", MOD_NAME)
	else:
		G_Steam.mod_log("No levels were loaded!", MOD_NAME)
	pass