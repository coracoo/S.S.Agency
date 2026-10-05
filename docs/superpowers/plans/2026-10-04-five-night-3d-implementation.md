# 五夜全三维主线 Implementation Plan

> 用户已确认本计划范围，按下列检查项实施、验证和交付。

**Goal:** 五夜全部3D移动，一条正式入口串起剧情、RPG、返场、仪式、存档及两结局，再可回退归档历史。
**Architecture:** 复用RPG模型和原子存档，增加正式chapter profile、统一ChapterSession、严格章节登记表。通用3D舞台消费登记表，场景仅呈现与请求事件。人物与敌图表现单独接线。
**Tech Stack:** Godot 4.6.3, GDScript, JSON, Python验证工具，现有透明PNG与3D参道。
**Spec:** `docs/superpowers/specs/2026-10-04-five-night-3d-design.md`

## Global Constraints
- 五夜全3D。保留六身份选三人与焰华双形态；双形态共享同一身份，不增加第二份HP或行动资源。
- 默认队凛音/薄荷/岑照，沿用L5；五场RPG普通40XP×4、Boss120XP。
- 正式存档schema_version=2，独立 `user://campaign_v1/slot_01.json`；旧档保持原样。
- 38个探索与14个结案节点正文与分支保留；hd5移至胜利返场。
- 守灯改辨认/安放/引路三步场景互动。无新故事、职业、技能、敌人或额外玩法。
- 保留高清七形态、小夜、新参道背景；接六张已交付右向敌图。
- 不改账号/权限/部署，不push、不合并main；不删未跟踪用户文件。Godot测试均先验证隔离user目录。
- 只在独立feature工作树改动；只操作任务文件，不覆盖其他未提交修改。

## Review Focus
- 存档写失败、损坏、未知版本、重复battle_id：不前推、不覆盖、不重复奖励（Task 1故障注入）。
- 对话/菜单期间按键未释放、双击、返回标题/重进：不移动、不重入、不跨夜（Task 2输入用例）。
- 3D安全锚点、位置越界、不同夜晚返回快照：恢复正确场景且位置有限（Task 1和2）。
- 六身份选队、焰华形态切换、高清加载取消：不复制角色、不串贴图、不过期发布（Task 3）。
- 发布包动态JSON/PNG/manifest/UID引用和旧class_name：干净导入、打包、清理后仍可完整通关（Task 4）。

## Shared interfaces
- `scripts/campaign/chapter_catalog.gd` (Task 1) defines `static func night(id:int)->Dictionary`, `static func scene_path(id:int)->String`, `static func initial_world(id:int)->Dictionary`, `static func validate_world(world:Dictionary)->Array[String]`.
- Catalog night dictionary: `night`, `id`, `title`, `scene_path`, `dialogue_stage`, `encounter_id`, `clue_id`, `intro`, `anchors` (spawn, battle_return, exit), `bounds` (x and z pairs), `required_events`, `interactions` (array of id,label,position,kind,dialogue,clue_id,requires). Kinds: dialogue, battle, ritual, exit.
- Scene paths fixed `res://scenes/campaign/night_1.tscn` through `night_5.tscn`. All attach `scripts/campaign/chapter_stage.gd` (Task 2) with exported `night_id`.
- World: `world_version=3, space="3d", night, scene_id, scene_path, position[3], facing, return_anchor, event_flags, resolved, dlg_fired`; flags are dictionaries of true values. Rpg compatibility scalar fields may be retained by Task 1; scene must preserve unknown valid fields.
- `scripts/campaign/chapter_session.gd` (Task 1) has static `current`, vars `campaign`, `router`, `bundle`; `start_new(replace_confirmed:bool,class_ids:Array[String]=["swordsman","ranger","guard"])->Dictionary`, `resume()->Dictionary`, `save_world(world:Dictionary)->Dictionary`, `commit_event(world:Dictionary,event_id:String)->Dictionary`, `begin_encounter(world:Dictionary,clue_id:String)->Dictionary`, `advance_night(world:Dictionary)->Dictionary`, `choose_resolution(world:Dictionary,resolution:String)->Dictionary`, `finish_ending(world:Dictionary)->Dictionary`, `prepare_assets()->Dictionary`, `close()->void`.
- Every mutator returns `{ok:bool,error:String,world:Dictionary}` plus `next_scene`/`battle_scene` when navigating. Do not claim success or mutate UI progression when `ok=false`. `commit_event` accepts only catalog event IDs. Dialogue root completion uses `dialogue:<root_id>`, ritual uses `ritual:identify`, `ritual:place`, `ritual:guide`.
- Campaign keeps existing RpgCampaign APIs used by battle view/router: `safe_snapshot`, `snapshot`, `begin_battle`, `apply_result`, `retry_battle`, `set_party`, `rest`, `use_item_outside`. Add `set_form(actor_id:String,form_id:String)->Dictionary` for valid homura forms only. Exploration/preparation changes must be saved atomically.
- Bindings: p_swordsman=rinne/rinne, p_ranger=mint/mint, p_guard=guard/guard, p_mage=homura/mage, p_healer=healer/healer, p_controller=controller/controller. Persisted homura form_id is mage/sword (manifest canonical values); directory aliases homura_mage/homura_sword are accepted only as input and normalized. Homura remains one actor with shared HP/MP/equipment/statuses/cooldowns/action slot. New runs start sword with existing swordsman skills; first-night victory unlocks mage. switch_form during Homura action swaps the actual four-skill set without spending or refreshing resources/actions; base actor stats remain unchanged in this integration. This supersedes the earlier visual-only interpretation, corrected against the original user instruction.
- `scripts/campaign/party_panel.gd` (Task 3) extends CanvasLayer, signal `closed`, `open(session:RefCounted)->void`; after closure scene resumes from saved world. Existing six classes' skills/equipment/item abilities remain available.
- Title path `res://scenes/campaign/title.tscn` (Task 2); ending path `res://scenes/campaign/ending.tscn` (Task 2); existing `res://scenes/rpg/battle.tscn` is sole combat scene.
- Task 1 notifies consumers immediately if a contract detail needs change; update this plan and exact consumer together, no silent name changes.

### Task 1: 正式主线状态与事务存档
**Files:** Create `scripts/campaign/chapter_catalog.gd`, `chapter_session.gd`, `chapter_world.gd` if useful; modify `scripts/rpg/campaign.gd`, `save_store.gd`, `encounter_router.gd`, `data/rpg/encounters.json`; tests under `tools/campaign/test_state.gd` plus isolated `tools/campaign/run_checks.py`.
**Interfaces:** Produces catalog/session and compatible Campaign/Router/Store APIs above; consumes existing RPG engine and Task 3 generalized PartyAssetBundle.
- [x] Write failing tests for five registered nights, no unregistered fallback, one next night only after required flags, 52-node references, schema2 path isolation.
- [x] Run isolated test and verify meaningful failure, then generalize profile/world handling without weakening old validators.
- [x] Add five encounter entries: night1 hound+shield_soldier, night2 hound+cultist, night3 shield_soldier+elite_shield_soldier, night4 cultist+fire_spirit, night5 gatekeeper.
- [x] Implement atomic event/ritual/chapter/ending transactions, pending same-seed retry, world scene history and branch state. Add failed-save/duplicate-result/invalid-world tests; run green.
- [x] Preserve existing three suites (data, campaign, approach) except obsolete explicit legacy scene-chain assertions are updated only in later integration task.
- [x] Write report with red/green evidence, exact contract and owned-file diff. Commit own files only under shared commit lock, report SHA.

### Task 2: 五夜三维场景与唯一入口
**Files:** Create `scripts/campaign/chapter_stage.gd`, `chapter_geometry.gd`, `title.gd`, `ending.gd`, `scenes/campaign/*.tscn`; modify `project.godot`, `play.bat`, `启动游戏.bat`, `scripts/ui/dialogue_overlay.gd` only for branch result/empty portrait if necessary. Tests `tools/campaign/test_scene_flow.gd`, visual capture scripts owned here.
**Interfaces:** Consumes Task 1 session/catalog and Task 3 party panel. No overlapping edits to the core/RPG/asset implementation.
- [x] Write tests for source-preserving dialogue graph roots, five Node3D scenes, required interaction dispatch, input locks and invalid callbacks after scene exit; observe red.
- [x] Reuse existing 3D approach art and movement/camera; build later corridor and honden geometry variants with floor, bounds, props, collision and usable interaction positions. No flat-background walking fallback.
- [x] Implement title start/continue/replace confirmation, chapter HUD, pause/party panel, E interaction with dialogue/confirmation and transition guards. Preserve r1-r3; split hd5 post-victory without editing source prose.
- [x] Implement three-step ritual and two-branch ending with save-before-advance; empty portrait clears prior speaker, not stale mint.
- [x] Run headless scene tests plus actual display capture/interaction (coordinate with controller for one active GUI). Confirm completion/defeat/retry/exit and correct ongoing scene.
- [x] Write report, own-file diff and commit under lock.

### Task 3: 六身份编队与新敌人表现
**Files:** Modify `scripts/characters/party_asset_bundle.gd`, `identity_portraits.gd`, `scripts/rpg/ui/battle_view.gd`, `hd_actor_view.gd`/`battle_presenter.gd`/`ui_kit.gd` only if needed, `data/rpg/presentation.json`; create `scripts/campaign/party_panel.gd`; copy final assets to `assets/chars/enemies/current/`; tests `tools/campaign/test_presentation.gd` and Python asset integrity checks.
**Interfaces:** Consumes unified ChapterSession, existing RpgRouter and new campaign.set_form API. Does not edit core, scene scripts, catalog or RPG encounter data.
- [x] Write failing tests for six distinct identities, seven manifests, selected-three loading, homura shared actor and finalized enemy IDs/paths/directions; observe red.
- [x] Expand asset bundle to seven actual form manifests, keep async cancellation/teardown. Battle view accepts formal session and chooses form correctly, no silent fallback to old low-detail characters.
- [x] Implement six-select-three preparation panel with saved party, homura unlocked career toggle and current RPG item/branch/equipment abilities retained. Reject incomplete/duplicate parties. Never synthesize a seventh roster member.
- [x] Materialize final six PNGs from existing same-executor deliverable folder and asset_manifest; verify hashes, not candidate/QA images. Update enemy_art/asset_facings, foot anchors and per-night background from campaign encounter context.
- [x] Run integrity/presentation tests and graphical lineup captures for all identities, both homura forms, six enemies. Report exact assets plus commit own files under lock.

### Task 4: 集成验收与引用清理
**Files:** `tools/campaign/`, `docs/verification/`, active docs index/AGENTS, `export_presets.cfg`, explicit archive manifest and .gdignore. Do not move anything still reached from new entry.
**Interfaces:** Consumes all reviewed changes. Integration includes independent review and targeted fixes.
- [x] Run isolated full RPG suites and all new campaign tests; fix integration at owner boundaries. Obsolete old-route tests must be removed from release gate only with replacement new-mainline coverage, never mask real failures.
- [x] Run actual user-equivalent UI from new title through five nights and both endings, plus interrupted/battle retry/party cases; save screenshots and logs outside repo.
- [x] Build dependency inventory including dynamic paths, JSON/manifest/UID and export roots; split protected/current/shared/development/historical classes. Only move Git-tracked, proven unreachable historical code/assets with explicit manifest and separate reversible commit. No deletion by directory name.
- [ ] Export runnable pack; clean-user launch and replay one complete ending plus other branch. Check no missing imports or historical entry points in package. Retain tools and approved source art in repo/development scope.
- [ ] Independent spec+quality review for tasks and whole branch, fix blocking findings with re-review. Deliver runnable build/source patch, exact test results, caveats, commits and rollback instructions. No remote publication unless separately authorized.

## 已确认原始需求更正 焰华双职业

原始用户要求：焰华双职业，开局剑客，剧情后转为法师，战斗时自由切换。2026-10-04接入选择：首夜正式胜利解锁法师，不新增剧情；允许最短系统提示。模型与UI同时接线，原仅外观计划不再适用。新增双职业真实技能/CD/队列/RNG/资源/存读/重放/败北回滚测试与独立审查。


## Additional acceptance: stature and guard artwork

- [x] Introduce configurable body-crown/sole stature metadata and shared world/battle scaling. Values: Mint158, Rinne168, Guard186, Homura170 in both forms, Healer162, Controller166cm. Preserve image aspect and common feet baseline across all actions.
- [x] Verify source PNG provenance and real body heights, display cm in preparation, run shared-stature regression tests.
- [ ] Complete approved Guard head/rear-cloth correction for all22 original poses through image editing; preserve other roles. Register only canvas/anchors/atlas mechanically, inspect every pose, and run related final graphical checks.
- [ ] Finish manual five-night real-battle run and both ending branches; fix the night4 confirmation layout overlap, then independently review the final code diff.
- [ ] Freeze explicit tracked resources/UIDs, generate the final portable pack plus source and patch, validate empty-resource launch and affected packed asset checks after the guard asset replacement. Document Linux verification and the need for Godot4.6.3 on Windows; do not claim Windows runtime testing.

- [ ] Apply subsequently approved Rinne twin-tail readability correction to19 poses, preserving identity, body, equipment and poses; walk5/walk6 remain their original individual frames per explicit user acceptance at13:38; a later blocked down output also retains its original frame, without retry. Use image editing for art and mechanical registration only; inspect real small-scale presentation before final asset integration.
