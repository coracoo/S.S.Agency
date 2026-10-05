// ---------- 通用 JSON 填表引擎（data/*.json 直接表格化维护） ----------
// 每个「簿」(book) = 若干「表」(sheet)；表 = headers + rows（与 xlsx 簿同构，前端零改动）。
// flatten：数组/字典拍平成叶子列；嵌套对象展开点路径；数组/空对象 → JSON 列（表头加 " (json)"，
//          前端已有 JSON 徽标+解析预检）。build 时按当前文件值的类型回写（数字/布尔还原，文本保持字符串）。
// 保存：服务端 JSON 列二次解析校验 + id 唯一性校验 → 每文件 .bak 备份后写盘。
// 这些 json 即游戏运行时源，写盘即生效（无需导出管线）。

import fs from "fs"
import path from "path"

export type JCell = string | number | boolean | null

export interface SheetData {
  headers: string[]
  rows: JCell[][]
}

export interface SheetAdapter {
  flatten(): SheetData
  /** 根据表格行重建各文件 json；发现错误写入 errors（调用方据此拒绝保存） */
  build(rows: JCell[][], errors: string[]): Record<string, unknown>
}

interface Book {
  desc: string
  sheets: Record<string, SheetAdapter>
}

const JSON_MARK = " (json)"

function isComplex(v: unknown): v is Record<string, unknown> | unknown[] {
  return v !== null && typeof v === "object"
}

function getPath(obj: unknown, dotted: string): unknown {
  let cur = obj
  for (const part of dotted.split(".")) {
    if (!isComplex(cur)) return undefined
    cur = (cur as Record<string, unknown>)[part]
  }
  return cur
}

function setPath(obj: Record<string, unknown>, dotted: string, v: unknown) {
  const parts = dotted.split(".")
  let cur: Record<string, unknown> = obj
  for (let i = 0; i < parts.length - 1; i++) {
    const k = parts[i]
    if (!isComplex(cur[k])) cur[k] = {}
    cur = cur[k] as Record<string, unknown>
  }
  cur[parts[parts.length - 1]] = v
}

function readJson(rel: string): unknown {
  return JSON.parse(fs.readFileSync(rel, "utf-8"))
}

function jsonFiles(dir: string): string[] {
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".json"))
    .sort()
    .map((f) => path.join(dir, f))
}

/** 叶子列并集（先见顺序）；数组与空对象视为叶子（JSON 列） */
function collectCols(items: Record<string, unknown>[], cols: string[], prefix: string) {
  for (const it of items) {
    for (const [k, v] of Object.entries(it)) {
      const key = prefix ? `${prefix}.${k}` : k
      if (isComplex(v)) {
        if (Array.isArray(v) || Object.keys(v).length === 0) {
          if (!cols.includes(key)) cols.push(key)
        } else {
          collectCols([v as Record<string, unknown>], cols, key)
        }
      } else if (!cols.includes(key)) {
        cols.push(key)
      }
    }
  }
}

/** 数组/字典列表 → SheetData */
export function flattenItems(items: Record<string, unknown>[]): SheetData {
  const cols: string[] = []
  collectCols(items, cols, "")
  const complex = new Set(
    cols.filter((c) => items.some((it) => isComplex(getPath(it, c))))
  )
  const headers = cols.map((c) => (complex.has(c) ? c + JSON_MARK : c))
  const rows = items.map((it) =>
    cols.map((c): JCell => {
      const v = getPath(it, c)
      if (v === undefined || v === null) return null
      if (isComplex(v)) return JSON.stringify(v)
      return v as string | number | boolean
    })
  )
  return { headers, rows }
}

/** SheetData → 列表；typeHints 用当前文件值推断列类型（number/boolean 回写，其余保持字符串） */
export function buildItems(
  sheet: SheetData,
  rows: JCell[][],
  errors: string[],
  typeHints?: Record<string, unknown>[],
  checkId = true
): Record<string, unknown>[] {
  const cols = sheet.headers.map((h) => ({
    key: h.endsWith(JSON_MARK) ? h.slice(0, -JSON_MARK.length) : h,
    json: h.endsWith(JSON_MARK),
    header: h,
  }))
  const out: Record<string, unknown>[] = []
  rows.forEach((r, ri) => {
    if (r.every((c) => c === null || c === "")) return
    const obj: Record<string, unknown> = {}
    cols.forEach((c, ci) => {
      const raw = r[ci]
      if (raw === null) return
      if (c.json) {
        if (raw === "") return
        try {
          setPath(obj, c.key, JSON.parse(String(raw)))
        } catch {
          errors.push(`第${ri + 2}行「${c.header}」JSON 解析失败`)
        }
        return
      }
      const s = String(raw)
      const hintV = typeHints ? getPath(typeHints.find((t) => getPath(t, c.key) !== undefined) ?? {}, c.key) : undefined
      const t = typeof hintV
      if (t === "number") {
        if (s === "") return
        const n = Number(s)
        if (Number.isNaN(n)) errors.push(`第${ri + 2}行「${c.header}」应为数字，得到 "${s}"`)
        else setPath(obj, c.key, n)
      } else if (t === "boolean") {
        if (s === "") return
        if (s !== "true" && s !== "false") errors.push(`第${ri + 2}行「${c.header}」应为 true/false`)
        else setPath(obj, c.key, s === "true")
      } else {
        // 字符串列保留空串（原文件可能显式为 ""，丢字段会破坏 roundtrip）
        setPath(obj, c.key, s)
      }
    })
    out.push(obj)
  })
  // id 唯一性（存在 id 列时）
  const idCol = cols.findIndex((c) => c.key === "id")
  if (checkId && idCol >= 0) {
    const seen = new Map<string, number>()
    out.forEach((o, i) => {
      const id = String(o.id ?? "")
      if (!id) return
      if (seen.has(id)) errors.push(`id "${id}" 重复（第${(seen.get(id) ?? 0) + 2}行 / 第${i + 2}行）`)
      else seen.set(id, i)
    })
  }
  return out
}

/** 简单列表簿：单文件，顶层数组或 {listKey: [...]}；保留字典 siblings（schema_version 等） */
function listAdapter(rel: string, listKey?: string): SheetAdapter {
  const file = () => path.resolve(__dirname, "..", "..", rel)
  const items = (): Record<string, unknown>[] => {
    const d = readJson(file()) as Record<string, unknown>
    const arr = listKey ? (d[listKey] as Record<string, unknown>[]) : (d as unknown as Record<string, unknown>[])
    return arr ?? []
  }
  return {
    flatten: () => flattenItems(items()),
    build: (rows, errors) => {
      const sheet = flattenItems(items()) // 仅取 headers 形状
      const rebuilt = buildItems(sheet, rows, errors, items())
      const d = readJson(file()) as Record<string, unknown>
      if (listKey) return { [rel]: { ...d, [listKey]: rebuilt } }
      return { [rel]: rebuilt }
    },
  }
}

/** 按舞台/案件分文件合并的列表簿：每行带分组键（stage/case_id），写回按组拆到各文件 */
function mergedAdapter(
  dirRel: string,
  listKey: string,
  groupCol: string,
  scalarKeys: string[]
): SheetAdapter {
  const dir = () => path.resolve(__dirname, "..", "..", dirRel)
  const perFile = (): { rel: string; group: string; scalars: Record<string, unknown>; items: Record<string, unknown>[] }[] =>
    jsonFiles(dir()).map((f) => {
      const d = readJson(f) as Record<string, unknown>
      return {
        rel: path.relative(path.resolve(__dirname, "..", ".."), f).split(path.sep).join("/"),
        group: String(d[groupCol] ?? path.basename(f, ".json")),
        scalars: Object.fromEntries(scalarKeys.filter((k) => k in d).map((k) => [k, d[k]])),
        items: (d[listKey] as Record<string, unknown>[]) ?? [],
      }
    })
  return {
    flatten: () => {
      const files = perFile()
      const withGroup = files.flatMap((f) =>
        f.items.map((it) => ({ [groupCol]: f.group, ...f.scalars, ...it }))
      )
      const sheet = flattenItems(withGroup)
      // 分组键与标量列提前
      const priors = [groupCol, ...scalarKeys.filter((k) => sheet.headers.includes(k))]
      sheet.headers = [...priors, ...sheet.headers.filter((h) => !priors.includes(h))]
      return sheet
    },
    build: (rows, errors) => {
      const files = perFile()
      const sheet = ((): SheetData => {
        const withGroup = files.flatMap((f) => f.items.map((it) => ({ [groupCol]: f.group, ...f.scalars, ...it })))
        const s = flattenItems(withGroup)
        const priors = [groupCol, ...scalarKeys.filter((k) => s.headers.includes(k))]
        s.headers = [...priors, ...s.headers.filter((h) => !priors.includes(h))]
        return s
      })()
      const rebuilt = buildItems(sheet, rows, errors, files.flatMap((f) => f.items))
      const out: Record<string, unknown> = {}
      for (const f of files) {
        const mine = rebuilt.filter((o) => String(o[groupCol]) === f.group)
        const scalars: Record<string, unknown> = {}
        for (const k of scalarKeys) {
          const v = mine[0]?.[k]
          if (v !== undefined && v !== "" && typeof v !== "object") scalars[k] = v
        }
        out[f.rel] = { ...f.scalars, ...scalars, [groupCol]: f.group, [listKey]: mine.map((o) => {
          const rest = { ...o }
          delete rest[groupCol]
          // 分组键与文件级标量列不属于列表项，回写时剥离（否则会被写进每条 item）
          for (const k of scalarKeys) delete rest[k]
          return rest
        }) }
      }
      return out
    },
  }
}

/** 键值簿：整棵 JSON 拍平成 path/value 两行列表（复合值走 JSON 列）。
 *  注意：键可能含 "."（如 asset_facings 的 "res://*.png"），因此回写不按路径解析，
 *  而是按 flatten 的 DFS 顺序位置对应——路径列仅作展示/校验，禁止增删改行顺序。 */
function keyValueAdapter(rel: string): SheetAdapter {
  const file = () => path.resolve(__dirname, "..", "..", rel)
  const flattenTree = (obj: unknown, prefix: string, rows: [string, unknown][]) => {
    if (!isComplex(obj) || Array.isArray(obj)) {
      rows.push([prefix, obj])
      return
    }
    const entries = Object.entries(obj)
    if (entries.length === 0) rows.push([prefix, obj])
    for (const [k, v] of entries) flattenTree(v, prefix ? `${prefix}.${k}` : k, rows)
  }
  /** 深度克隆树并按 rows 顺序位置回写叶子值（leafIndex 由 flatten 顺序决定） */
  const applyLeaves = (obj: unknown, rows: [string, unknown][], errors: string[]): unknown => {
    let i = 0
    const walk = (o: unknown): unknown => {
      const isLeaf = !isComplex(o) || Array.isArray(o) || Object.keys(o as object).length === 0
      if (isLeaf) {
        const row = rows[i]
        i++
        const raw = row?.[1]
        if (raw === undefined || raw === null || String(raw) === "") return o
        try { return JSON.parse(String(raw)) } catch {
          errors.push(`「${row?.[0] ?? `#${i}`}」JSON 解析失败`)
          return o
        }
      }
      const out: Record<string, unknown> = {}
      for (const [k, v] of Object.entries(o as Record<string, unknown>)) out[k] = walk(v)
      return out
    }
    return walk(obj)
  }
  return {
    flatten: () => {
      const rows: [string, unknown][] = []
      flattenTree(readJson(file()), "", rows)
      return {
        headers: ["路径", "值 (json)"],
        rows: rows.map(([p, v]): JCell[] => [p, JSON.stringify(v)]),
      }
    },
    build: (rows, errors) => {
      const d = readJson(file())
      const expected: [string, unknown][] = []
      flattenTree(d, "", expected)
      if (rows.length !== expected.length) {
        errors.push(`键值行数 ${rows.length} 与原文件 ${expected.length} 不一致（禁止增删行）`)
        return { [rel]: d }
      }
      for (const [i, r] of rows.entries()) {
        const p = String(r[0] ?? "").trim()
        if (p !== expected[i][0]) {
          errors.push(`第${i + 2}行路径 "${p}" 与原文件 "${expected[i][0]}" 不符（禁止改行顺序/路径）`)
          return { [rel]: d }
        }
      }
      return { [rel]: applyLeaves(d, rows.map((r) => [String(r[0]), r[1]] as [string, unknown]), errors) }
    },
  }
}

// ---------- 3D 探索场景（data/exploration_3d/<场景>.json）：锚点/调查点/场景参数 三表 ----------
/** 单场景三表（rel = 项目相对路径，如 data/exploration_3d/approach.json） */
function approachAdapter(rel: string): { sheets: Record<string, SheetAdapter> } {
  const file = () => path.resolve(__dirname, "..", "..", rel)
  const data = () => readJson(file()) as Record<string, unknown>
  const anchorsAdapter: SheetAdapter = {
    flatten: () => {
      const anchors = (data().anchors ?? {}) as Record<string, unknown>
      return {
        headers: ["锚点key", "x", "y", "z"],
        rows: Object.entries(anchors).map(([k, v]): JCell[] => {
          const a = v as number[]
          return [k, a[0] ?? null, a[1] ?? null, a[2] ?? null]
        }),
      }
    },
    build: (rows, errors) => {
      const d = data()
      const anchors: Record<string, unknown> = {}
      rows.forEach((r, i) => {
        const k = String(r[0] ?? "").trim()
        if (!k) return
        const xyz = r.slice(1, 4).map((c) => Number(c))
        if (xyz.some((n) => Number.isNaN(n))) errors.push(`第${i + 2}行锚点 "${k}" 坐标应为数字`)
        anchors[k] = xyz
      })
      return { [rel]: { ...d, anchors } }
    },
  }
  const targetsAdapter: SheetAdapter = {
    flatten: () => flattenItems(((data().targets ?? []) as Record<string, unknown>[])),
    build: (rows, errors) => {
      const d = data()
      const sheet = flattenItems((d.targets ?? []) as Record<string, unknown>[])
      return { [rel]: { ...d, targets: buildItems(sheet, rows, errors, (d.targets ?? []) as Record<string, unknown>[]) } }
    },
  }
  const paramsAdapter: SheetAdapter = {
    flatten: () => ({
      headers: ["scene_id", "bounds (json)", "walk_polygon (json)", "basin_visual_anchor (json)"],
      rows: [[
        String(data().scene_id ?? ""),
        JSON.stringify(data().bounds ?? null),
        JSON.stringify(data().walk_polygon ?? null),
        JSON.stringify(data().basin_visual_anchor ?? null),
      ]],
    }),
    build: (rows, errors) => {
      const d = data()
      const r = rows[0] ?? []
      const parse = (v: JCell, name: string): unknown => {
        if (v === null || v === "") return undefined
        try { return JSON.parse(String(v)) } catch { errors.push(`场景参数「${name}」JSON 解析失败`); return undefined }
      }
      const out = { ...d }
      if (r[0]) out.scene_id = String(r[0])
      const b = parse(r[1], "bounds"); if (b !== undefined) out.bounds = b
      const w = parse(r[2], "walk_polygon"); if (w !== undefined) out.walk_polygon = w
      const a = parse(r[3], "basin_visual_anchor"); if (a !== undefined) out.basin_visual_anchor = a
      return { [rel]: out }
    },
  }
  return { sheets: { 锚点: anchorsAdapter, 调查点: targetsAdapter, 场景参数: paramsAdapter } }
}

/** data/exploration_3d/ 下每个场景文件 → 三张表（<场景>·锚点 / <场景>·调查点 / <场景>·场景参数）。
 *  新增 3D 场景 JSON 即自动出现在簿里，无需改注册表。 */
function scene3dSheets(): Record<string, SheetAdapter> {
  const root = path.resolve(__dirname, "..", "..")
  const sheets: Record<string, SheetAdapter> = {}
  for (const f of jsonFiles(path.join(root, "data", "exploration_3d"))) {
    const rel = path.relative(root, f).split(path.sep).join("/")
    const name = path.basename(f, ".json")
    const a = approachAdapter(rel).sheets
    sheets[`${name}·锚点`] = a["锚点"]
    sheets[`${name}·调查点`] = a["调查点"]
    sheets[`${name}·场景参数`] = a["场景参数"]
  }
  return sheets
}

// ---------- 战斗关卡（data/battles/*.json）：关卡参数 / 敌方 / 机关点位 ----------
// 卡池(cards)由 battle xlsx 簿经导出管线维护，此处不回写（保留当前文件值）。
function battleBook(): Book {
  const dirRel = "data/battles"
  const dir = () => path.resolve(__dirname, "..", "..", dirRel)
  // _extra.json 是无 id 的卡库补充文件（由 battle xlsx 簿维护），不属于战斗关卡
  const files = () => jsonFiles(dir()).filter((f) => read(f).id !== undefined)
  const read = (f: string) => readJson(f) as Record<string, unknown>
  const battleId = (f: string) => String(read(f).id ?? path.basename(f, ".json"))

  /** 非列表叶子拍平（对象递归点路径；数组与空对象 → JSON 列） */
  const leafCols = (obj: Record<string, unknown>, prefix: string, cols: string[]) => {
    for (const [k, v] of Object.entries(obj)) {
      const key = prefix ? `${prefix}.${k}` : k
      if (Array.isArray(v) || (v !== null && typeof v === "object" && Object.keys(v).length === 0)) {
        if (!cols.includes(key)) cols.push(key)
      } else if (v !== null && typeof v === "object") {
        leafCols(v as Record<string, unknown>, key, cols)
      } else if (!cols.includes(key)) cols.push(key)
    }
  }
  const leafGet = (obj: unknown, dotted: string): unknown => getPath(obj, dotted)

  const mergedList = (listKey: string): SheetAdapter => ({
    flatten: () => {
      const grouped = files().flatMap((f) => {
        const d = read(f)
        return ((d[listKey] as Record<string, unknown>[]) ?? []).map((it) => ({ 战斗: battleId(f), ...it }))
      })
      const sheet = flattenItems(grouped)
      sheet.headers = ["战斗", ...sheet.headers.filter((h) => h !== "战斗")]
      return sheet
    },
    build: (rows, errors) => {
      const out: Record<string, unknown> = {}
      // 表头顺序必须与 flatten() 全局一致（行数据按该顺序），逐文件仅作类型提示
      const sheet = mergedList(listKey).flatten()
      for (const f of files()) {
        const d = read(f)
        const cur = ((d[listKey] as Record<string, unknown>[]) ?? []).map((it) => ({ 战斗: battleId(f), ...it }))
        const rebuilt = buildItems(sheet, rows, errors, cur, false)
        const mine = rebuilt.filter((o) => String(o.战斗) === battleId(f))
        out[path.relative(path.resolve(__dirname, "..", ".."), f).split(path.sep).join("/")] = {
          ...d,
          [listKey]: mine.map((o) => {
            const rest = { ...o }
            delete rest.战斗
            return rest
          }),
        }
      }
      return out
    },
  })

  const params: SheetAdapter = {
    flatten: () => {
      const cols: string[] = []
      const objs = files().map((f) => read(f))
      for (const o of objs) {
        const rest = { ...o }
        delete rest.enemies; delete rest.slots; delete rest.cards
        leafCols(rest, "", cols)
      }
      const headers = ["战斗", ...cols.map((c) => {
        const isJson = objs.some((o) => Array.isArray(leafGet(o, c)) || (leafGet(o, c) !== null && typeof leafGet(o, c) === "object" && Object.keys(leafGet(o, c) as object).length === 0))
        return isJson ? c + JSON_MARK : c
      })]
      const rows = files().map((f) => {
        const o = read(f)
        const rest = { ...o }
        delete rest.enemies; delete rest.slots; delete rest.cards
        return [battleId(f), ...cols.map((c): JCell => {
          const v = leafGet(rest, c)
          if (v === undefined || v === null) return null
          if (Array.isArray(v) || (typeof v === "object" && Object.keys(v).length === 0)) return JSON.stringify(v)
          return v as JCell
        })]
      })
      return { headers, rows }
    },
    build: (rows, errors) => {
      const out: Record<string, unknown> = {}
      for (const f of files()) {
        const d = read(f)
        const bid = battleId(f)
        const r = rows.find((row) => String(row[0]) === bid)
        if (!r) continue
        const sheet = params.flatten()
        for (let i = 1; i < sheet.headers.length; i++) {
          const h = sheet.headers[i]
          const raw = r[i]
          if (raw === null) continue
          const key = h.endsWith(JSON_MARK) ? h.slice(0, -JSON_MARK.length) : h
          if (h.endsWith(JSON_MARK)) {
            if (raw === "") continue
            try { setPath(d, key, JSON.parse(String(raw))) } catch { errors.push(`关卡「${bid}」${key} JSON 解析失败`) }
          } else {
            setPath(d, key, typeof leafGet(d, key) === "number" ? Number(raw) : String(raw))
          }
        }
        out[path.relative(path.resolve(__dirname, "..", ".."), f).split(path.sep).join("/")] = d
      }
      return out
    },
  }

  return {
    desc: "卡牌战斗关卡：data/battles/*.json 的关卡参数/敌方波次/机关点位，保存即生效（卡池由 battle xlsx 簿维护）",
    sheets: { 关卡参数: params, 敌方: mergedList("enemies"), 机关点位: mergedList("slots") },
  }
}

// ---------- 案件对话节点（data/cases/*.json 的 nodes 字典）：一行一个节点 ----------
function casesAdapter(dirRel: string): SheetAdapter {
  const dir = () => path.resolve(__dirname, "..", "..", dirRel)
  const files = () => jsonFiles(dir())
  const read = (f: string) => readJson(f) as Record<string, unknown>
  const caseId = (f: string) => String(read(f).id ?? path.basename(f, ".json"))
  const flat = () =>
    files().flatMap((f) => {
      const nodes = (read(f).nodes ?? {}) as Record<string, unknown>
      return Object.entries(nodes).map(([nid, n]) => ({ 案件: caseId(f), 节点: nid, ...(n as Record<string, unknown>) }))
    })
  const sheetOf = () => {
    const sheet = flattenItems(flat())
    sheet.headers = ["案件", "节点", ...sheet.headers.filter((h) => h !== "案件" && h !== "节点")]
    return sheet
  }
  return {
    flatten: sheetOf,
    build: (rows, errors) => {
      const out: Record<string, unknown> = {}
      // 表头顺序与 flatten() 全局一致
      const sheet = sheetOf()
      for (const f of files()) {
        const d = read(f)
        const cur = flat().filter((o) => o.案件 === caseId(f))
        const rebuilt = buildItems(sheet, rows, errors, cur, false)
        const mine = rebuilt.filter((o) => String(o.案件) === caseId(f))
        const nodes: Record<string, unknown> = {}
        for (const o of mine) {
          const nid = String(o.节点 ?? "").trim()
          if (!nid) { errors.push(`案件「${caseId(f)}」存在空节点 id`); continue }
          if (nid in nodes) errors.push(`案件「${caseId(f)}」节点 "${nid}" 重复`)
          const rest = { ...o }
          delete rest.案件; delete rest.节点
          nodes[nid] = rest
        }
        out[path.relative(path.resolve(__dirname, "..", ".."), f).split(path.sep).join("/")] = { ...d, nodes }
      }
      return out
    },
  }
}

// ---------- 簿注册表 ----------
export const JSON_BOOKS: Record<string, Book> = (() => {
  const rpg = (rel: string): SheetAdapter => listAdapter(rel, "definitions")
  return {
    rpg: {
      desc: "回合制 RPG 模式数值：data/rpg/*.json（游戏运行时源），保存即生效，自动 .bak 备份",
      sheets: {
        职业: rpg("data/rpg/classes.json"),
        技能: rpg("data/rpg/skills.json"),
        敌人: rpg("data/rpg/enemies.json"),
        装备: rpg("data/rpg/equipment.json"),
        道具: rpg("data/rpg/items.json"),
        状态: rpg("data/rpg/statuses.json"),
        遭遇: rpg("data/rpg/encounters.json"),
        演出布局: keyValueAdapter("data/rpg/presentation.json"),
      },
    },
    roster: {
      desc: "卡牌线角色数值与法器：data/units.json + data/artifacts.json，保存即生效",
      sheets: {
        角色数值: listAdapter("data/units.json", "units"),
        法器: listAdapter("data/artifacts.json"),
      },
    },
    coords: {
      desc: "3D 探索场景配置：data/exploration_3d/<场景>.json（锚点/调查点/边界/行走多边形，单位=米）+ 异象线索文本（data/clues/*.json），保存即生效",
      sheets: {
        ...scene3dSheets(),
        异象线索: mergedAdapter("data/clues", "clues", "stage", ["comment"]),
      },
    },
    content: {
      desc: "委托/案件/仪式内容：data/commissions.json + data/cases/*.json + data/rituals/*.json，保存即生效",
      sheets: {
        委托: listAdapter("data/commissions.json", "commissions"),
        案件节点: casesAdapter("data/cases"),
        仪式参数: ritualParamsAdapter(),
        仪式卡牌: listKeyOf("data/rituals/ritual_lamp.json", "cards"),
        仪式道具: listKeyOf("data/rituals/ritual_lamp.json", "items"),
      },
    },
    battles: battleBook(),
    theme: {
      desc: "UI 主题数值：data/ui_theme.json 键值对（颜色/字号/尺寸），保存即生效",
      sheets: { 主题键值: keyValueAdapter("data/ui_theme.json") },
    },
    weather: {
      desc: "第一幕天气调度：data/campaign/weather.json（profiles=可复用天气档案，nights=夜晚→档案名），保存即生效",
      sheets: { 天气调度: keyValueAdapter("data/campaign/weather.json") },
    },
  }
})()

/** 单文件内某个列表键（同文件多表共用，siblings 保留） */
function listKeyOf(rel: string, listKey: string): SheetAdapter {
  const file = () => path.resolve(__dirname, "..", "..", rel)
  const items = () => ((readJson(file()) as Record<string, unknown>)[listKey] as Record<string, unknown>[]) ?? []
  return {
    flatten: () => flattenItems(items()),
    build: (rows, errors) => {
      const d = readJson(file()) as Record<string, unknown>
      const sheet = flattenItems(items())
      return { [rel]: { ...d, [listKey]: buildItems(sheet, rows, errors, items()) } }
    },
  }
}

function ritualParamsAdapter(): SheetAdapter {
  const rel = "data/rituals/ritual_lamp.json"
  const file = () => path.resolve(__dirname, "..", "..", rel)
  const data = () => readJson(file()) as Record<string, unknown>
  const SCALARS = ["id", "name", "comment", "bg", "ap_per_turn", "max_turns"]
  const JSONKEYS = ["player", "deck", "lamp", "add_fuel"]
  return {
    flatten: () => ({
      headers: [...SCALARS, ...JSONKEYS.map((k) => `${k} (json)`)],
      rows: [[...SCALARS.map((k) => (data()[k] as JCell) ?? null), ...JSONKEYS.map((k) => JSON.stringify(data()[k] ?? null))]],
    }),
    build: (rows, errors) => {
      const d = data()
      const r = rows[0] ?? []
      const out = { ...d }
      SCALARS.forEach((k, i) => {
        if (r[i] !== null && r[i] !== "") out[k] = typeof d[k] === "number" ? Number(r[i]) : String(r[i])
      })
      JSONKEYS.forEach((k, i) => {
        const v = r[SCALARS.length + i]
        if (v === null || v === "") return
        try { out[k] = JSON.parse(String(v)) } catch { errors.push(`仪式参数「${k}」JSON 解析失败`) }
      })
      return { [rel]: out }
    },
  }
}

export function loadJsonBook(key: string): Record<string, SheetData> {
  const book = JSON_BOOKS[key]
  if (!book) throw new Error(`未知配置域: ${key}`)
  return Object.fromEntries(Object.entries(book.sheets).map(([name, a]) => [name, a.flatten()]))
}

export function saveJsonBook(key: string, sheets: Record<string, SheetData>): { ok: boolean; log: string } {
  const book = JSON_BOOKS[key]
  if (!book) throw new Error(`未知配置域: ${key}`)
  const errors: string[] = []
  const writes: Record<string, unknown> = {}
  for (const [name, sheet] of Object.entries(sheets)) {
    const adapter = book.sheets[name]
    if (!adapter) { errors.push(`未知表: ${name}`); continue }
    Object.assign(writes, adapter.build(sheet.rows, errors))
  }
  if (errors.length) return { ok: false, log: `校验未通过，未写入任何文件：\n${errors.join("\n")}` }
  const root = path.resolve(__dirname, "..", "..")
  for (const [rel, json] of Object.entries(writes)) {
    const abs = path.join(root, rel)
    if (fs.existsSync(abs)) fs.copyFileSync(abs, abs + ".bak")
    // 与原文件风格一致：2 空格缩进 + CRLF + 末尾换行（避免无意义 diff）
    const text = JSON.stringify(json, null, 2).replace(/\n/g, "\r\n") + "\r\n"
    fs.writeFileSync(abs, text, "utf-8")
  }
  const lines = Object.entries(writes).map(([rel, j]) => {
    const count = Array.isArray(j) ? j.length : Array.isArray((j as Record<string, unknown>).definitions)
      ? ((j as Record<string, unknown>).definitions as unknown[]).length
      : Array.isArray((j as Record<string, unknown>).units)
        ? ((j as Record<string, unknown>).units as unknown[]).length
        : Array.isArray((j as Record<string, unknown>).commissions)
          ? ((j as Record<string, unknown>).commissions as unknown[]).length
          : "✓"
    return `OK ${rel}（${count} 条）`
  })
  return { ok: true, log: `校验通过，已写入 ${Object.keys(writes).length} 个文件（.bak 备份已留）：\n${lines.join("\n")}` }
}
