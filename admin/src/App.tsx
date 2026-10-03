import { useCallback, useEffect, useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Plus, Trash2, RefreshCw, Save, CircleCheck, CircleX } from "lucide-react"
import MaskEditor from "@/sections/MaskEditor"

// ---------- 配置域元数据（与 tools/export_*_xlsx.py 的表结构对应） ----------
type Cell = string | number | boolean | null

interface SheetData {
  headers: string[]
  rows: Cell[][]
}

interface BookMeta {
  key: string
  title: string
  desc: string
  sheetTitles: Record<string, string>
  /** xlsx = 走导出管线；json = 直接读写 data/*.json（保存即生效） */
  kind?: "xlsx" | "json"
}

const BOOKS: BookMeta[] = [
  {
    key: "dialogue",
    title: "台词剧情",
    desc: "config/dialogue.xlsx → data/dialogues.json：进场景 enter / 走到位置 hotspot 触发，choices 表挂分支",
    sheetTitles: { nodes: "对话节点", choices: "分支选项" },
  },
  {
    key: "battle",
    title: "战斗配置",
    desc: "config/battle_config.xlsx → data/battles/*.json：场次 / 敌方波次 / 场景槽位 / 技能卡牌",
    sheetTitles: { battle: "场次", enemy: "敌方波次", slot: "场景槽位", card: "技能卡牌" },
  },
  {
    key: "stage",
    title: "舞台线索",
    desc: "config/stage_config.xlsx → data/stages/*.json + data/clues/*.json：探索舞台 / 画面线索",
    sheetTitles: { stage: "探索舞台", clue: "画面线索" },
  },
  {
    key: "mask",
    title: "行走遮罩",
    desc: "手动涂绘各舞台的可行走区域（白 = 可行走）：左侧选舞台，右侧在背景上涂抹，绿线为逐列落脚线预览，保存即写入 assets/bg/walkmasks/<舞台>.png，游戏内立即生效",
    sheetTitles: {},
  },
  {
    key: "rpg",
    title: "RPG 数值",
    kind: "json",
    desc: "回合制 RPG：职业 / 技能 / 敌人 / 装备 / 道具 / 状态 / 遭遇 / 战斗演出布局（data/rpg/*.json），保存即生效",
    sheetTitles: { 职业: "职业", 技能: "技能", 敌人: "敌人", 装备: "装备", 道具: "道具", 状态: "状态", 遭遇: "遭遇", 演出布局: "战斗演出布局" },
  },
  {
    key: "roster",
    title: "角色法器",
    kind: "json",
    desc: "卡牌线角色数值（stats/牌组/道具）与法器（data/units.json + data/artifacts.json），保存即生效",
    sheetTitles: { 角色数值: "角色数值", 法器: "法器" },
  },
  {
    key: "coords",
    title: "坐标",
    kind: "json",
    desc: "异象坐标 / 遮挡体坐标（2D 舞台，单位=场景像素）+ 参道 3D 锚点与调查点（单位=米），保存即生效",
    sheetTitles: { 异象坐标: "异象坐标", 遮挡坐标: "遮挡坐标", 锚点: "参道3D锚点", 调查点: "参道3D调查点", 场景参数: "参道3D场景参数" },
  },
  {
    key: "content",
    title: "委托仪式",
    kind: "json",
    desc: "委托列表 / 案件对话节点 / 仪式参数 / 仪式卡牌与道具（data/commissions.json + data/cases/*.json + data/rituals/*.json），保存即生效",
    sheetTitles: { 委托: "委托", 案件节点: "案件对话节点", 仪式参数: "仪式参数", 仪式卡牌: "仪式卡牌", 仪式道具: "仪式道具" },
  },
  {
    key: "battles",
    title: "战斗关卡",
    kind: "json",
    desc: "卡牌战斗关卡：关卡参数（灵气/封印/玩家/牌组）/ 敌方波次 / 机关点位（data/battles/*.json），保存即生效；卡池由 battle xlsx 簿维护",
    sheetTitles: { 关卡参数: "关卡参数", 敌方: "敌方波次", 机关点位: "机关点位" },
  },
  {
    key: "theme",
    title: "UI 主题",
    kind: "json",
    desc: "UI 主题键值：颜色 / 语义色 / 字号 / 尺寸 / 动效（data/ui_theme.json），路径点分隔，保存即生效",
    sheetTitles: { 主题键值: "主题键值" },
  },
]

/** 枚举列：表头包含 key 时用下拉框（值来自导出校验的合法枚举） */
const ENUM_COLS: { match: string; options: string[] }[] = [
  { match: "type(attack/slot/seal/skill)", options: ["attack", "slot", "seal", "skill"] },
  { match: "owner(所属角色)", options: ["", "rinne", "mint", "hakka", "qingming", "generic"] },
  { match: "target(目标)", options: ["", "enemy"] },
  { match: "slot_state", options: ["", "burning", "ringing", "spilled", "sealed"] },
  { match: "trigger", options: ["", "enter", "hotspot"] },
  { match: "side", options: ["left", "right"] },
  { match: "state(初始状态)", options: ["idle", "burning", "ringing", "spilled", "sealed"] },
  // RPG 域
  { match: "element", options: ["neutral", "fire", "water", "wood", "light", "dark"] },
  { match: "damage_type", options: ["physical", "magical", "none"] },
  { match: "target_rule", options: ["", "self", "single_ally", "other_ally", "all_allies", "single_enemy", "all_enemies", "dead_ally"] },
  { match: "default_attack", options: ["physical", "magical"] },
  { match: "slot(装备部位)", options: ["", "weapon", "armor", "accessory"] },
  { match: "clock", options: ["", "next_owner_slot", "turn_start", "turn_end"] },
]

function isJsonCol(header: string): boolean {
  return header.toLowerCase().includes("json")
}

function enumOptions(header: string): string[] | null {
  const hit = ENUM_COLS.find((e) => header.includes(e.match))
  return hit ? hit.options : null
}

function cellText(v: Cell): string {
  return v === null ? "" : String(v)
}

export default function App() {
  const [bookIdx, setBookIdx] = useState(0)
  const [sheets, setSheets] = useState<Record<string, SheetData>>({})
  const [baseline, setBaseline] = useState<Record<string, SheetData>>({})
  const [sheetIdx, setSheetIdx] = useState(0)
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [log, setLog] = useState<{ ok: boolean | null; text: string }>({ ok: null, text: "" })
  const [error, setError] = useState("")

  const book = BOOKS[bookIdx]

  const load = useCallback(async (key: string) => {
    setLoading(true)
    setError("")
    try {
      if (key === "mask") {
        // 遮罩页自管数据（走 /api/stages、/api/walkmask），无需加载表格
        setSheets({})
        setBaseline({})
        setSheetIdx(0)
        setLog({ ok: null, text: "" })
        return
      }
      const r = await fetch(book.kind === "json" ? `/api/load-json/${key}` : `/api/load/${key}`)
      const data = await r.json()
      if (!r.ok) throw new Error(data.error || `HTTP ${r.status}`)
      setSheets(data.sheets)
      setBaseline(JSON.parse(JSON.stringify(data.sheets)))
      setSheetIdx(0)
      setLog({ ok: null, text: "" })
    } catch (e) {
      setError(String(e))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load(book.key)
  }, [book.key, load])

  const sheetNames = Object.keys(sheets)
  const sheetName = sheetNames[sheetIdx] ?? ""
  const sheet: SheetData | undefined = sheets[sheetName]

  const dirty = useMemo(
    () => JSON.stringify(sheets) !== JSON.stringify(baseline),
    [sheets, baseline]
  )

  /** 客户端 JSON 列预检（服务端导出器还有完整校验） */
  const jsonErrors = useMemo(() => {
    const errs: string[] = []
    for (const [name, sh] of Object.entries(sheets)) {
      sh.headers.forEach((h, ci) => {
        if (!isJsonCol(h)) return
        sh.rows.forEach((row, ri) => {
          const v = cellText(row[ci]).trim()
          if (!v) return
          try {
            JSON.parse(v)
          } catch {
            errs.push(`${name} 第${ri + 2}行「${h}」JSON 解析失败`)
          }
        })
      })
    }
    return errs
  }, [sheets])

  const setCell = (ri: number, ci: number, v: string) => {
    if (!sheet) return
    const rows = sheet.rows.map((r, i) =>
      i === ri ? r.map((c, j) => (j === ci ? (v === "" ? null : v) : c)) : r
    )
    setSheets({ ...sheets, [sheetName]: { ...sheet, rows } })
  }

  const addRow = () => {
    if (!sheet) return
    const row: Cell[] = sheet.headers.map(() => null)
    setSheets({ ...sheets, [sheetName]: { ...sheet, rows: [...sheet.rows, row] } })
  }

  const delRow = (ri: number) => {
    if (!sheet) return
    setSheets({
      ...sheets,
      [sheetName]: { ...sheet, rows: sheet.rows.filter((_, i) => i !== ri) },
    })
  }

  const save = async () => {
    if (jsonErrors.length) {
      setLog({ ok: false, text: `客户端预检未通过：\n${jsonErrors.join("\n")}` })
      return
    }
    setSaving(true)
    try {
      const r = await fetch(book.kind === "json" ? "/api/save-json" : "/api/save", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ book: book.key, sheets }),
      })
      const data = await r.json()
      if (!r.ok) throw new Error(data.error || `HTTP ${r.status}`)
      setLog({ ok: data.ok, text: data.log || "(导出器无输出)" })
      if (data.ok) setBaseline(JSON.parse(JSON.stringify(sheets)))
    } catch (e) {
      setLog({ ok: false, text: String(e) })
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="min-h-screen bg-stone-100 text-stone-900">
      <header className="border-b bg-white sticky top-0 z-20">
        <div className="mx-auto max-w-[1600px] px-6 py-3 flex items-center gap-4 flex-wrap">
          <h1 className="text-lg font-bold tracking-wide">封灵配置后台</h1>
          <Tabs
            value={String(bookIdx)}
            onValueChange={(v) => setBookIdx(Number(v))}
          >
            <TabsList>
              {BOOKS.map((b, i) => (
                <TabsTrigger key={b.key} value={String(i)}>
                  {b.title}
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
          <div className="flex-1" />
          <Badge variant={dirty ? "default" : "secondary"}>
            {dirty ? "有未保存修改" : "已同步"}
          </Badge>
          {book.key !== "mask" && (
            <>
              <Button variant="outline" size="sm" onClick={() => load(book.key)} disabled={loading}>
                <RefreshCw className={`mr-1 h-4 w-4 ${loading ? "animate-spin" : ""}`} />
                重新加载
              </Button>
              <Button size="sm" onClick={save} disabled={saving || loading || !dirty}>
                <Save className="mr-1 h-4 w-4" />
                {saving ? "校验写入中…" : book.kind === "json" ? "保存" : "保存并导出"}
              </Button>
            </>
          )}
        </div>
        <p className="mx-auto max-w-[1600px] px-6 pb-2 text-xs text-stone-500">{book.desc}</p>
      </header>

      <main className="mx-auto max-w-[1600px] px-6 py-4">
        {book.key === "mask" ? (
          <MaskEditor />
        ) : (
          <>
        {error && (
          <Alert variant="destructive" className="mb-4">
            <AlertTitle>加载失败</AlertTitle>
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}

        {sheetNames.length > 0 && (
          <Tabs value={String(sheetIdx)} onValueChange={(v) => setSheetIdx(Number(v))}>
            <TabsList className="mb-4">
              {sheetNames.map((n, i) => (
                <TabsTrigger key={n} value={String(i)}>
                  {book.sheetTitles[n] ?? n}
                  <Badge variant="outline" className="ml-2">
                    {sheets[n].rows.length}
                  </Badge>
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
        )}

        {sheet && (
          <Card>
            <CardHeader className="py-3 flex-row items-center justify-between space-y-0">
              <CardTitle className="text-base">
                {book.sheetTitles[sheetName] ?? sheetName}
                <span className="ml-2 text-xs font-normal text-stone-400">
                  {sheet.rows.length} 行 × {sheet.headers.length} 列 ·
                  空白单元格 = 该字段缺省
                </span>
              </CardTitle>
              <Button variant="outline" size="sm" onClick={addRow}>
                <Plus className="mr-1 h-4 w-4" /> 新增行
              </Button>
            </CardHeader>
            <CardContent className="overflow-x-auto p-0">
              <table className="w-full text-sm border-collapse">
                <thead>
                  <tr className="bg-stone-50 text-left">
                    <th className="border-b px-2 py-2 w-10 text-stone-400 font-normal">#</th>
                    {sheet.headers.map((h) => (
                      <th key={h} className="border-b px-2 py-2 whitespace-nowrap font-medium">
                        {h}
                        {isJsonCol(h) && (
                          <Badge variant="secondary" className="ml-1 text-[10px]">
                            JSON
                          </Badge>
                        )}
                      </th>
                    ))}
                    <th className="border-b w-10" />
                  </tr>
                </thead>
                <tbody>
                  {sheet.rows.map((row, ri) => (
                    <tr key={ri} className="align-top hover:bg-stone-50/60">
                      <td className="border-b px-2 py-1 text-stone-400 text-xs">{ri + 2}</td>
                      {sheet.headers.map((h, ci) => {
                        const v = cellText(row[ci])
                        const opts = enumOptions(h)
                        const json = isJsonCol(h)
                        return (
                          <td key={h} className="border-b px-1 py-1 min-w-[110px]">
                            {opts ? (
                              <Select
                                value={v}
                                onValueChange={(nv) =>
                                  setCell(ri, ci, nv === "__empty__" ? "" : nv)
                                }
                              >
                                <SelectTrigger className="h-8 text-xs border-transparent hover:border-input">
                                  <SelectValue placeholder="—" />
                                </SelectTrigger>
                                <SelectContent>
                                  {opts.includes("") && (
                                    <SelectItem value="__empty__">（空）</SelectItem>
                                  )}
                                  {opts
                                    .filter((o) => o !== "")
                                    .map((o) => (
                                      <SelectItem key={o} value={o}>
                                        {o}
                                      </SelectItem>
                                    ))}
                                </SelectContent>
                              </Select>
                            ) : json || v.length > 40 ? (
                              <Textarea
                                value={v}
                                onChange={(e) => setCell(ri, ci, e.target.value)}
                                className={`min-h-[30px] text-xs resize-y w-full ${
                                  json && v.trim() && jsonErrors.some((e) =>
                                    e.includes(`第${ri + 2}行`) && e.includes(`「${h}」`)
                                  )
                                    ? "border-red-400 focus-visible:ring-red-300"
                                    : "border-transparent hover:border-input"
                                }`}
                                rows={json ? 2 : 1}
                              />
                            ) : (
                              <Input
                                value={v}
                                onChange={(e) => setCell(ri, ci, e.target.value)}
                                className="h-8 text-xs border-transparent hover:border-input"
                              />
                            )}
                          </td>
                        )
                      })}
                      <td className="border-b px-1 py-1">
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-stone-400 hover:text-red-500"
                          onClick={() => delRow(ri)}
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </CardContent>
          </Card>
        )}

        {log.ok !== null && (
          <Alert variant={log.ok ? "default" : "destructive"} className="mt-4">
            {log.ok ? (
              <CircleCheck className="h-4 w-4" />
            ) : (
              <CircleX className="h-4 w-4" />
            )}
            <AlertTitle>{log.ok ? "已保存并通过校验，游戏 JSON 已重新导出" : "保存失败或未通过校验"}</AlertTitle>
            <AlertDescription>
              <pre className="mt-2 whitespace-pre-wrap text-xs bg-black/5 rounded p-3 max-h-72 overflow-auto">
                {log.text}
              </pre>
            </AlertDescription>
          </Alert>
        )}

        {book.kind === "json" ? (
        <p className="mt-6 text-xs text-stone-400 leading-relaxed">
          工作流（JSON 簿）：改表 →「保存」→ 服务端 JSON 列解析校验 + id 唯一性校验 → 每文件自动 .bak
          备份后写回 data/*.json（游戏运行时源），游戏内立即生效，无导出环节。嵌套对象已展开成点路径列；
          标 (json) 的列为数组/对象（JSON 文本）。空白单元格 = 该字段缺省不写回。
        </p>
        ) : (
        <p className="mt-6 text-xs text-stone-400 leading-relaxed">
          工作流：改表 → 「保存并导出」→ 服务端写回 xlsx（自动留 .bak 备份）→ 运行 Python
          导出管线（14 项校验）→ 校验通过则 data/ 下游戏 JSON 更新，游戏内立即生效。
          校验失败时 xlsx 已写入但游戏 JSON 保持旧值，按上方报告修表后重新保存即可；
          如需回滚 xlsx，取 config/*.xlsx.bak。
        </p>
        )}
          </>
        )}
      </main>
    </div>
  )
}
