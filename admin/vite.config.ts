import path from "path"
import react from "@vitejs/plugin-react"
import { defineConfig, type Plugin } from "vite"
import { inspectAttr } from 'kimi-plugin-inspect-react'
import XLSX from "xlsx"
import { execFile } from "child_process"
import fs from "fs"

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
  stage: {
    xlsx: path.join(PROJECT_ROOT, "config", "stage_config.xlsx"),
    exporter: path.join(PROJECT_ROOT, "tools", "export_stage_config_xlsx.py"),
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

// ---------- 行走遮罩涂绘 API ----------
// 遮罩 = assets/bg/walkmasks/<stage>.png（白=可行走，顶缘=落脚高度）。
// GET /api/stages 列舞台；GET /api/walkmask?stage=x 取遮罩（缺失时从地面剖面光栅化）；
// POST /api/walkmask 保存前端涂绘结果；/game-assets/* 静态供编辑器取背景图。

import zlib from "zlib"

/** 最小 PNG 编码器（灰度 L8 → RGBA 再编码，配合内置 zlib） */
function crc32(buf: Buffer): number {
  let table = (crc32 as unknown as { t?: number[] }).t
  if (!table) {
    table = []
    for (let n = 0; n < 256; n++) {
      let c = n
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
      table[n] = c >>> 0
    }
    ;(crc32 as unknown as { t?: number[] }).t = table
  }
  let c = 0xffffffff
  for (const b of buf) c = table[(c ^ b) & 0xff] ^ (c >>> 8)
  return (c ^ 0xffffffff) >>> 0
}

function pngChunk(type: string, data: Buffer): Buffer {
  const len = Buffer.alloc(4)
  len.writeUInt32BE(data.length)
  const body = Buffer.concat([Buffer.from(type, "ascii"), data])
  const crc = Buffer.alloc(4)
  crc.writeUInt32BE(crc32(body))
  return Buffer.concat([len, body, crc])
}

/** gray: 0-255 的 Uint8Array（w*h）→ PNG Buffer */
function encodePngGray(w: number, h: number, gray: Uint8Array): Buffer {
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(w, 0)
  ihdr.writeUInt32BE(h, 4)
  ihdr[8] = 8 // bit depth
  ihdr[9] = 0 // grayscale
  const raw = Buffer.alloc((w + 1) * h)
  for (let y = 0; y < h; y++) {
    raw[y * (w + 1)] = 0 // filter: none
    Buffer.from(gray.buffer, y * w, w).copy(raw, y * (w + 1) + 1)
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", zlib.deflateSync(raw)),
    pngChunk("IEND", Buffer.alloc(0)),
  ])
}

/** RGBA PNG Buffer → gray Uint8Array（仅处理本工具自产/编辑器回存的 8bit 灰度或 RGBA PNG，
 *  其他位深直接抛错让前端重涂） */
function decodePngGray(buf: Buffer): { w: number; h: number; gray: Uint8Array } {
  // 借助 xlsx 自带的 jszip 太重；用最小解码：仅支持 color type 0/6、bit depth 8
  let pos = 8
  let w = 0, h = 0, bitDepth = 0, colorType = 0
  const idat: Buffer[] = []
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos)
    const type = buf.toString("ascii", pos + 4, pos + 8)
    const data = buf.subarray(pos + 8, pos + 8 + len)
    if (type === "IHDR") {
      w = data.readUInt32BE(0); h = data.readUInt32BE(4)
      bitDepth = data[8]; colorType = data[9]
    } else if (type === "IDAT") idat.push(data)
    else if (type === "IEND") break
    pos += 12 + len
  }
  if (bitDepth !== 8 || (colorType !== 0 && colorType !== 6))
    throw new Error(`不支持的 PNG 格式（depth=${bitDepth} type=${colorType}），请保存 8bit 灰度/RGBA`)
  const channels = colorType === 0 ? 1 : 4
  const raw = zlib.inflateSync(Buffer.concat(idat))
  const stride = w * channels
  const gray = new Uint8Array(w * h)
  let prev = Buffer.alloc(stride)
  let p = 0
  for (let y = 0; y < h; y++) {
    const filter = raw[p++]
    const line = Buffer.from(raw.subarray(p, p + stride))
    p += stride
    for (let x = 0; x < stride; x++) {
      const a = x >= channels ? line[x - channels] : 0
      const b = prev[x]
      const c = x >= channels ? prev[x - channels] : 0
      if (filter === 1) line[x] = (line[x] + a) & 0xff
      else if (filter === 2) line[x] = (line[x] + b) & 0xff
      else if (filter === 3) line[x] = (line[x] + ((a + b) >> 1)) & 0xff
      else if (filter === 4) {
        const pa = Math.abs(b - c), pb = Math.abs(a - c), pc = Math.abs(a + b - 2 * c)
        const pr = pa <= pb && pa <= pc ? a : pb <= pc ? b : c
        line[x] = (line[x] + pr) & 0xff
      }
    }
    for (let x = 0; x < w; x++)
      gray[y * w + x] = channels === 1 ? line[x] : line[x * channels]
    prev = line
  }
  return { w, h, gray }
}

/** ground_profile 折线 → 遮罩灰度（线以下白=可行走） */
function maskFromProfile(w: number, h: number, profile: [number, number][]): Uint8Array {
  const gray = new Uint8Array(w * h)
  const xs = profile.map((p) => p[0])
  const ys = profile.map((p) => p[1])
  for (let x = 0; x < w; x++) {
    const fx = (x / w) * 2048
    let y: number
    if (fx <= xs[0]) y = ys[0]
    else if (fx >= xs[xs.length - 1]) y = ys[ys.length - 1]
    else {
      let i = 0
      while (i < xs.length - 2 && xs[i + 1] < fx) i++
      const t = (fx - xs[i]) / Math.max(1, xs[i + 1] - xs[i])
      y = ys[i] + (ys[i + 1] - ys[i]) * t
    }
    const gy = Math.min(h - 1, Math.max(0, Math.round((y / 1152) * h)))
    for (let yy = gy; yy < h; yy++) gray[yy * w + x] = 255
  }
  return gray
}

const MASK_DIR = path.join(PROJECT_ROOT, "assets", "bg", "walkmasks")
const ASSETS_DIR = path.join(PROJECT_ROOT, "assets")

function listStages(): { id: string; name: string; bg: string }[] {
  const wb = XLSX.readFile(BOOKS.stage.xlsx)
  const ws = wb.Sheets["stage"]
  const aoa: unknown[][] = XLSX.utils.sheet_to_json(ws, { header: 1, defval: null })
  const headers = (aoa[0] ?? []).map((x) => String(x ?? ""))
  const ciFile = headers.findIndex((h) => h === "file(输出文件名)")
  const ciName = headers.findIndex((h) => h === "name(场景名)")
  const ciBg = headers.findIndex((h) => h === "bg(背景图)")
  return aoa.slice(1)
    .filter((r) => r[ciFile])
    .map((r) => ({
      id: String(r[ciFile]),
      name: String(r[ciName] ?? r[ciFile]),
      bg: String(r[ciBg] ?? ""),
    }))
}

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

      // ---- 行走遮罩涂绘 ----
      server.middlewares.use("/api/stages", async (_req, res) => {
        try {
          send(res, 200, { stages: listStages() })
        } catch (e) {
          send(res, 500, { error: String(e) })
        }
      })
      server.middlewares.use("/api/walkmask", async (req, res) => {
        try {
          const url = new URL((req as unknown as { url?: string }).url ?? "", "http://x")
          let stage = url.searchParams.get("stage") ?? ""
          if (req.method === "POST") {
            const body = JSON.parse(await readBody(req)) as { png?: string; stage?: string }
            if (!stage) stage = body.stage ?? ""
            if (!/^[A-Za-z0-9_-]+$/.test(stage))
              return send(res, 400, { error: "stage 非法" })
            const maskPath = path.join(MASK_DIR, stage + ".png")
            const b64 = (body.png ?? "").replace(/^data:image\/png;base64,/, "")
            const buf = Buffer.from(b64, "base64")
            const { w, h, gray } = decodePngGray(buf) // 解码再重编码：统一 8bit 灰度
            if (w < 64 || h < 64) return send(res, 400, { error: "遮罩尺寸过小" })
            fs.mkdirSync(MASK_DIR, { recursive: true })
            fs.writeFileSync(maskPath, encodePngGray(w, h, gray))
            return send(res, 200, { ok: true, w, h })
          }
          if (!/^[A-Za-z0-9_-]+$/.test(stage))
            return send(res, 400, { error: "stage 非法" })
          const maskPath = path.join(MASK_DIR, stage + ".png")
          const fromProfile = url.searchParams.get("from") === "profile"
          if (!fromProfile && fs.existsSync(maskPath)) {
            const { w, h, gray } = decodePngGray(fs.readFileSync(maskPath))
            return send(res, 200, {
              stage, w, h, hasMask: true,
              png: "data:image/png;base64," + Buffer.from(encodePngGray(w, h, gray)).toString("base64"),
            })
          }
          // 缺失或要求从剖面重建：读 stage JSON 的 ground_profile 光栅化
          const sj = path.join(PROJECT_ROOT, "data", "stages", stage + ".json")
          if (!fs.existsSync(sj)) return send(res, 404, { error: `找不到舞台数据 ${stage}` })
          const cfg = JSON.parse(fs.readFileSync(sj, "utf-8"))
          const profile = (cfg.ground_profile ?? [[0, 900], [2048, 900]]) as [number, number][]
          const gray = maskFromProfile(2048, 1152, profile)
          send(res, 200, {
            stage, w: 2048, h: 1152, hasMask: fs.existsSync(maskPath),
            png: "data:image/png;base64," + Buffer.from(encodePngGray(2048, 1152, gray)).toString("base64"),
          })
        } catch (e) {
          send(res, 500, { error: String(e) })
        }
      })
      // 编辑器取游戏素材（仅 assets 内图片，防目录穿越）
      server.middlewares.use("/game-assets/", (req, res) => {
        const rel = decodeURIComponent((req as unknown as { url?: string }).url ?? "").replace(/^\//, "")
          .replace(/^assets\//, "") // 前端会把 res://assets/... 原样拼进 URL，去掉重复前缀
        const full = path.normalize(path.join(ASSETS_DIR, rel))
        if (!full.startsWith(ASSETS_DIR) || !/\.(png|jpg|jpeg|webp)$/i.test(full)) {
          res.statusCode = 403
          return res.end("forbidden")
        }
        if (!fs.existsSync(full)) {
          res.statusCode = 404
          return res.end("not found")
        }
        res.setHeader("Content-Type", full.endsWith(".png") ? "image/png" : "image/jpeg")
        res.end(fs.readFileSync(full))
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
