# trim down the file to exclude certain lines
import re, os

include_recipes = False
include_furnace_recipes = False
include_items = True
include_ore_dictionary = True
include_mods = True

filename = "RevelationCtrecipes.txt"
trimmed_filename = "trimmedRecipes.txt"
item_name_filename = "item_names_parsed.txt"
original_item_name_filename = "item_names.txt"

exclude_line_keywords = ["[buildcraft.facades]", "[chiselsandbits]", "[appliedenergistics2.facades]",
	"<forestry:bee_queen_ge>", "<forestry:bee_drone_ge>", "<genetics:serum_array>", "<refinedstorage:cover>.withTag(",
	"[FlatColoredBlocks]", "withTag(", "extratrees:", "<block:", "bibliocraft", "xtones",
	"""Blocks:
""", "A total of", """Recipes:
""",
"List of all registered Items:",
'"REGISTRY_NAME","DISPLAY_NAME","UNLOCALIZED","MAX_STACK_SIZE","MAX_ITEM_USE_DURATION","MAX_ITEM_DAMAGE","RARITY","REPAIR_COST","DAMAGEABLE","REPAIRABLE","CREATIVE_TABS","ENCHANTABILITY","BURN_TIME"',
]
exclude_multi_keywords = [["natura:overworld_planks", "recipes.add"],
						["microblockcbe:microblock:", ">.withTag"],
						["harvestcraft", "recipes.add"],
						["harvestcraft", "furnace.add"],
						["twilightforest", "recipes.add"],
						["natura", "recipes.add"],
						["forestry", "recipes.add"],
						] # remove the line if all of these are in the line
after_ore_entries = [
					"harvestcraft",
					"chisel",
					] # these lines are only removed after we enter the ore-dictionary section
remove_between_lines_with = [["[SERVER_STARTED][SERVER][ERROR]", "at java.lang.Thread.run("]]
		# remove the lines between and including these to remove the errors

# exclude_line_keywords = ["withTag("]
# exclude_multi_keywords = [] # remove the line if all of these are in the line


ogf = open(filename, "r")
tf = open(trimmed_filename, "w")
inf = open(item_name_filename, "w")
original_inf = open(original_item_name_filename, "r")

original_line_count = 0
new_line_count = 0
in_ore_dictionary = False
used_ore_dictionary_elements = {} # add ore dictionary elements that are used in recipes and remove the rest?
inside_remove_section = False
inside_item_section = False
inside_mods_section = False # "Mods list:"

all_display_names = {} # for checking duplicate display names

current_ore = ""
for line in ogf.readlines():
	include = True
	original_line_count += 1
	# also figure out what ore dictionaries are used in this line
	all_ores_used = re.findall("((<ore)(?:.*?)(>))", line)
	all_ores_used = [x[0].strip().replace("-", "") for x in all_ores_used]

	if '"REGISTRY_NAME","DISPLAY_NAME","UNLOCALIZED","MAX_STACK_SIZE","MAX_ITEM_USE_DURATION","MAX_ITEM_DAMAGE","RARITY","REPAIR_COST","DAMAGEABLE","REPAIRABLE","CREATIVE_TABS","ENCHANTABILITY","BURN_TIME"' in line:
		inside_item_section = True
		in_ore_dictionary = False
		inside_mods_section = False

	if "Mods list:" in line:
		inside_item_section = False
		in_ore_dictionary = False
		inside_mods_section = True

	for sections in remove_between_lines_with:
		if sections[0] in line:
			inside_remove_section = True
	for sections in remove_between_lines_with:
		if sections[1] in line:
			inside_remove_section = False
			include = False # remove this last line too

	if "Ore entries for <" in line:
		in_ore_dictionary = True
		inside_item_section = False
		inside_mods_section = False
		if len(all_ores_used) > 0:
			current_ore = all_ores_used[0]
	if not include_ore_dictionary and in_ore_dictionary:
		include = False
	if not include_recipes and "recipes.add" in line:
		include = False
	if not include_furnace_recipes and "furnace.add" in line:
		include = False
	if not include_mods and inside_mods_section:
		include = False
	for exclude in exclude_line_keywords:
		if exclude in line:
			include = False
			break
	for l in exclude_multi_keywords:
		has_all = True
		for exclude in l:
			if exclude not in line:
				has_all = False
		if has_all:
			include = False
	if in_ore_dictionary:
		for exclude in after_ore_entries:
			if exclude in line:
				include = False
				break
		if not current_ore in used_ore_dictionary_elements:
			# print("Excluding current ore line "+ line)
			include = False

	if include and not inside_remove_section:
		new_line_count += 1
		tf.write(line)
		# if len(all_ores_used) > 0:
		# 	print(all_ores_used)
		if not in_ore_dictionary:
			for ore in all_ores_used:
				used_ore_dictionary_elements[ore] = True

	# generate output files for use in CC!
	if inside_item_section and include and not inside_remove_section:
		# add the item names!
		# "REGISTRY_NAME","DISPLAY_NAME","UNLOCALIZED","MAX_STACK_SIZE","MAX_ITEM_USE_DURATION","MAX_ITEM_DAMAGE","RARITY","REPAIR_COST","DAMAGEABLE","REPAIRABLE","CREATIVE_TABS","ENCHANTABILITY","BURN_TIME"
		item_names = re.findall('(".*"),(".*"),(".*"),(".*"),(".*"),(".*"),(".*"),(".*"),(".*"),(".*"),(".*"),(".*"),(".*")', line)[0]
		item_key_string = item_names[0].replace('"', "").replace("<", "").replace(">", "")
		display_name = item_names[1].replace('"', "").strip()
		damage_value = item_key_string.split(":")
		damageable = item_names[8] == '"true"'
		repairable = item_names[9] == '"true"'
		max_stack_size = int(item_names[3].replace('"', ""))
		if len(damage_value) == 3:
			# then it has a damage value!
			item_key_string = damage_value[0] + ":" + damage_value[1]
			damage_value = damage_value[2].strip()
		else:
			damage_value = "0" # default 0 damage value
		inf.write(item_key_string + "," + damage_value + "," + str(max_stack_size) + "," + str(damageable) + ",\"" + display_name + "\"\n")

		# check duplicate display names:
		if display_name not in all_display_names:
			all_display_names[display_name] = []
		all_display_names[display_name].append((item_key_string, damage_value))

		if max_stack_size != 1 and damageable:
			print("max stack size is 1: " + display_name + " " + item_names[0].replace('"', "").replace("<", "").replace(">", ""))

ogf.close()
tf.close()
inf.close()


# check the item names to see if we're missing any
inf = open(item_name_filename, "r")
all_new_names = list(inf.readlines())


missingLines = 0
for line in original_inf.readlines():
	# check that that name is in all_new_names
	if line not in all_new_names:
		print("ERROR: missing name: " + str(line).strip())
		missingLines += 1
print("Missing " + str(missingLines) + " names")

# check duplicate display names
for key in all_display_names.keys():
	if len(all_display_names[key]) > 1:
		# then we have duplicates!
		print("Duplicate display name: " + key)
		for i in all_display_names[key]:
			print(i)
		print() # add a new line to space it out

inf.close()
original_inf.close()


print("Original line count: " + str(original_line_count) + " new line count: " + str(new_line_count))
print("Removed lines: " + str(original_line_count - new_line_count))
print("Trimmed size: " + str(os.path.getsize(trimmed_filename)/1000000) + " mb")

print()

print("Item file size: " + str(os.path.getsize(item_name_filename)/1000000) + " mb")