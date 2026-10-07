# 独立呈现矩阵；不导入伤害、消耗或状态规则。
extends RefCounted
const ROWS := [
	["firebolt","firebolt","single_enemy",["damage"],true,224.0,"ember","ffc777"],
	["flame_wave","flame_wave","all_enemies",["damage"],true,258.0,"ember","ffbe64"],
	["ice_arrow","ice_arrow","single_enemy",["damage"],true,232.0,"shard","beefff"],
	["burn_brand","burn_brand","single_enemy",["damage"],true,212.0,"ember","ffa461"],
	["heal","heal","single_ally",["healed"],true,234.0,"petal","c5f7d2"],
	["group_heal","group_heal","all_allies",["healed"],false,250.0,"petal","eff5b7"],
	["cleanse","cleanse","single_ally",["status_removed","cleansed"],true,228.0,"petal","d9fdf1"],
	["holy_shield","holy_shield","single_ally",["shield_applied","shield_refreshed"],true,242.0,"shard","e8edbe"],
	["weaken","weaken","single_enemy",["status_applied","status_refreshed"],true,220.0,"paper","b9a4df"],
	["slow","slow","all_enemies",["status_applied","status_refreshed"],false,228.0,"paper","b6c2eb"],
	["seal","seal","single_enemy",["status_applied","status_refreshed","charge_interrupted"],true,240.0,"paper","eeb3a9"],
	["magic_break","magic_break","single_enemy",["damage"],true,246.0,"shard","edc4ff"],
	["cover","protect","other_ally",["status_applied","status_refreshed"],false,224.0,"shard","b7d6ee"],
	["shield_bash","shield_bash","single_enemy",["damage"],false,222.0,"shard","e5d1a2"],
	["iron_wall","protect","self",["shield_applied","shield_refreshed"],false,268.0,"shard","aacced"],
	["taunt","taunt","single_enemy",["status_applied","status_refreshed"],false,208.0,"spark","ffd798"],
	["heavy_slash","slash","single_enemy",["damage"],false,256.0,"spark","dbefde"],
	["armor_break","armor_break","single_enemy",["damage"],false,240.0,"shard","dbeacb"],
	["sweep","sweep","all_enemies",["damage"],false,250.0,"spark","f0d1a2"],
	["battle_spirit","battle_spirit","self",["status_applied","status_refreshed"],false,228.0,"ember","f3d5a1"],
	["mark","mark","single_enemy",["status_applied","status_refreshed"],false,206.0,"spark","ffe5a2"],
	["hunt","hunt","single_enemy",["damage"],true,248.0,"spark","ffe3a2"],
	["ambush","slash","single_enemy",["damage"],false,216.0,"spark","e5dcac"],
	["smoke_screen","smoke_screen","self",["shield_applied","shield_refreshed"],false,256.0,"paper","adb6ca"]
]
static func get_profile(ability_id: String) -> Dictionary:
	for row in ROWS:
		if row[0] == ability_id:
			return {"atlas":row[1],"target_rule":row[2],"events":row[3].duplicate(),"projectile":row[4],"size":row[5],"particle":row[6],"color":row[7]}
	return {}
