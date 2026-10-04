import path from "path"
import react from "@vitejs/plugin-react"
import { defineConfig, type Plugin } from "vite"
import { inspectAttr } from 'kimi-plugin-inspect-react'
import XLSX from "xlsx"
import { execFile } from "child_process"
import fs from "fs"
import { loadJsonBook, saveJsonBook } from "./server/json_tables"

// ---------- 游戏配置后台 API（Vite 开发服务器中间件，仅本地使用） ----------
// 单一事实源 = config/*.xlsx；保存时写回 xlsx 并调用 Python 导出管线
// （tools/export_*_xlsx.py 自带校验），校验结果原样回给前端展示。

const PROJECT_ROOT = path.resolve(__dirname, "..")

const BOOKS: Record<string, { xlsx: string; exporter: string }> = {
  dialogue: {
    xlsx: path.join(PROJECT_ROOT, "config", "dialogue.xlsx"),
    exporter: path.join(PROJECT_ROOT, "tools", "export_dialogue_xlsx.py"),
  },
  battle: {
    xlsx: path.join(PROJECT_ROOT, "config", "battle_config.xlsx"),
    exporter: path.join(PROJECT_ROOT, "tools", "export_battle_config_xlsx.py"),
  },
}

interface SheetData {
  headers: string[]
  rows: (string | number | boolean | null)[][]
}

function readBody(req: import("http").IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let data = ""
    req.on("data", (c) => (data += c))
    req.on("end", () => resolve(data))
    req.on("error", reject)
  })
}

function send(res: import("http").ServerResponse, code: number, obj: unknown) {
  res.statusCode = code
  res.setHeader("Content-Type", "application/json; charset=utf-8")
  res.end(JSON.stringify(obj))
}

/** xlsx → 表格（所有单元格转字符串/原始值，前端负责编辑） */
function loadBook(file: string): Record<string, SheetData> {
  const wb = XLSX.readFile(file)
  const out: Record<string, SheetData> = {}
  for (const name of wb.SheetNames) {
    const ws = wb.Sheets[name]
    const aoa: unknown[][] = XLSX.utils.sheet_to_json(ws, { header: 1, defval: null })
    const headers = (aoa[0] ?? []).map((h) => String(h ?? ""))
    const rows = aoa.slice(1).map((r) =>
      headers.map((_, i) => {
        const v = r[i]
        if (v === null || v === undefined) return null
        return v as string | number | boolean
      })
    )
    out[name] = { headers, rows }
  }
  return out
}

/** 表格 → xlsx 写盘（保留表头行；单元格以原始类型写入，JSON 串按文本） */
function saveBook(file: string, sheets: Record<string, SheetData>) {
  const wb = XLSX.utils.book_new()
  for (const [name, sheet] of Object.entries(sheets)) {
    const aoa: unknown[][] = [sheet.headers, ...sheet.rows]
    const ws = XLSX.utils.aoa_to_sheet(aoa)
    ws["!cols"] = sheet.headers.map((h) => ({ wch: Math.max(12, Math.min(46, h.length + 6)) }))
    XLSX.utils.book_append_sheet(wb, ws, name)
  }
  XLSX.writeFile(wb, file)
}

function runExporter(script: string): Promise<{ code: number; log: string }> {
  return new Promise((resolve) => {
    execFile("python", [script], {
      cwd: PROJECT_ROOT,
      timeout: 120000,
      env: { ...process.env, PYTHONIOENCODING: "utf-8" },
    }, (err, stdout, stderr) => {
      resolve({ code: err ? (typeof err.code === "number" ? err.code : 1) : 0, log: stdout + stderr })
    })
  })
}

// ---------- 行走遮罩涂绘 API（已下线）----------
// 2D 背景探索线已由 3D 场景（data/exploration_3d/*.json，配置见 JSON 簿「3D 场景」）取代，
// 行走区域 = walk_polygon 多边形（单位=米），不再使用像素遮罩。

function configApi(): Plugin {
  return {
    name: "game-config-admin-api",
    configureServer(server) {
      server.middlewares.use("/api/load", async (req, res) => {
        try {
          const key = String((req as unknown as { url?: string }).url?.replace(/^\//, "") || "")
          const book = BOOKS[key]
          if (!book) return send(res, 404, { error: `未知配置域: ${key}` })
          if (!fs.existsSync(book.xlsx)) return send(res, 404, { error: `找不到 ${book.xlsx}` })
          send(res, 200, { sheets: loadBook(book.xlsx) })
        } catch (e) {
          send(res, 500, { error: String(e) })
        }
      })
      server.middlewares.use("/api/save", async (req, res) => {
        try {
          const body = JSON.parse(await readBody(req)) as {
            book?: string
            sheets?: Record<string, SheetData>
          }
          const book = BOOKS[body.book ?? ""]
          if (!book) return send(res, 404, { error: `未知配置域: ${body.book}` })
          if (!body.sheets) return send(res, 400, { error: "缺少 sheets" })
          // 备份后写盘
          if (fs.existsSync(book.xlsx)) {
            fs.copyFileSync(book.xlsx, book.xlsx + ".bak")
          }
          saveBook(book.xlsx, body.sheets)
          const result = await runExporter(book.exporter)
          send(res, 200, { ok: result.code === 0, code: result.code, log: result.log })
        } catch (e) {
          send(res, 500, { error: String(e) })
        }
      })

      // ---- JSON 填表簿（RPG 数值/装备/坐标/台词内容/UI 主题）----
      server.middlewares.use("/api/load-json", async (req, res) => {
        try {
          const key = String((req as unknown as { url?: string }).url?.replace(/^\//, "") || "")
          send(res, 200, { sheets: loadJsonBook(key) })
        } catch (e) {
          send(res, 500, { error: String(e) })
        }
      })
      server.middlewares.use("/api/save-json", async (req, res) => {
        try {
          const body = JSON.parse(await readBody(req)) as {
            book?: string
            sheets?: Record<string, SheetData>
          }
          if (!body.book || !body.sheets) return send(res, 400, { error: "缺少 book/sheets" })
          send(res, 200, saveJsonBook(body.book, body.sheets))
        } catch (e) {
          send(res, 500, { error: String(e) })
        }
      })
    },
  }
}

// https://vite.dev/config/
export default defineConfig({
  base: './',
  plugins: [inspectAttr(), react(), configApi()],
  server: {
    port: 7100,
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
});
