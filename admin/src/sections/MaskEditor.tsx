import { useCallback, useEffect, useRef, useState } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Slider } from "@/components/ui/slider"
import { Save, RefreshCw, Eraser, Paintbrush, CircleCheck, CircleX } from "lucide-react"

interface StageInfo {
  id: string
  name: string
  bg: string
}

/**
 * 行走遮罩涂绘器：白=可行走面（顶缘=人物落脚高度）。
 * 左键涂抹可行走 / 右键或选擦除模式清除；绿线=每列落脚线预览。
 * 保存直接写 assets/bg/walkmasks/<舞台>.png，游戏内立即生效。
 */
export default function MaskEditor() {
  const [stages, setStages] = useState<StageInfo[]>([])
  const [stageId, setStageId] = useState("")
  const [brush, setBrush] = useState(36)
  const [erase, setErase] = useState(false)
  const [opacity, setOpacity] = useState(0.45)
  const [status, setStatus] = useState<{ ok: boolean | null; text: string }>({ ok: null, text: "" })
  const [busy, setBusy] = useState(false)

  const viewRef = useRef<HTMLCanvasElement>(null)
  const maskCanvasRef = useRef<HTMLCanvasElement | null>(null)
  const bgImgRef = useRef<HTMLImageElement | null>(null)
  const metaRef = useRef<{ w: number; h: number }>({ w: 2048, h: 1152 })
  const paintingRef = useRef(false)
  const lastPtRef = useRef<{ x: number; y: number } | null>(null)
  const dirtyRef = useRef(false)

  const stage = stages.find((s) => s.id === stageId)

  useEffect(() => {
    fetch("/api/stages")
      .then((r) => r.json())
      .then((d) => {
        const list: StageInfo[] = d.stages ?? []
        setStages(list)
        // 默认选中第一个舞台，避免空页面（「黑屏」观感）
        if (!stageId && list.length) setStageId(list[0].id)
      })
      .catch((e) => setStatus({ ok: false, text: String(e) }))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const render = useCallback(() => {
    const view = viewRef.current
    const mask = maskCanvasRef.current
    if (!view || !mask) return
    const ctx = view.getContext("2d")!
    const { clientWidth: cw, clientHeight: ch } = view
    // 同步画布后备缓冲区到 CSS 尺寸（否则始终是默认 300×150，画面被裁成左上角一条）
    const dpr = window.devicePixelRatio || 1
    const bw = Math.max(1, Math.round(cw * dpr))
    const bh = Math.max(1, Math.round(ch * dpr))
    if (view.width !== bw || view.height !== bh) {
      view.width = bw
      view.height = bh
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    ctx.clearRect(0, 0, cw, ch)
    const s = Math.min(cw / metaRef.current.w, ch / metaRef.current.h)
    const dw = metaRef.current.w * s
    const dh = metaRef.current.h * s
    const ox = (cw - dw) / 2
    const oy = (ch - dh) / 2
    const bg = bgImgRef.current
    if (bg) ctx.drawImage(bg, ox, oy, dw, dh)
    else {
      ctx.fillStyle = "#222"
      ctx.fillRect(ox, oy, dw, dh)
    }
    // 遮罩着色：先按 alpha 叠白，再画绿色落脚线
    ctx.save()
    ctx.globalAlpha = opacity
    ctx.drawImage(mask, ox, oy, dw, dh)
    ctx.restore()
    // 落脚线
    const mctx = mask.getContext("2d")!
    const img = mctx.getImageData(0, 0, mask.width, mask.height)
    const d = img.data
    ctx.strokeStyle = "#22c55e"
    ctx.lineWidth = 1.5
    ctx.beginPath()
    for (let x = 0; x < mask.width; x += 4) {
      let gy = -1
      for (let y = 0; y < mask.height; y++) {
        if (d[(y * mask.width + x) * 4] > 127) {
          gy = y
          break
        }
      }
      if (gy >= 0) {
        const vx = ox + x * s
        const vy = oy + gy * s
        if (x === 0) ctx.moveTo(vx, vy)
        else ctx.lineTo(vx, vy)
      }
    }
    ctx.stroke()
  }, [opacity])

  useEffect(() => {
    render()
  }, [render, stageId, stages])

  const loadMask = useCallback(
    async (id: string, fromProfile: boolean) => {
      setBusy(true)
      setStatus({ ok: null, text: "" })
      try {
        const r = await fetch(`/api/walkmask?stage=${id}${fromProfile ? "&from=profile" : ""}`)
        const data = await r.json()
        if (!r.ok) throw new Error(data.error || `HTTP ${r.status}`)
        metaRef.current = { w: data.w, h: data.h }
        const img = new Image()
        img.onload = () => {
          if (!maskCanvasRef.current) {
            maskCanvasRef.current = document.createElement("canvas")
          }
          const mc = maskCanvasRef.current
          mc.width = data.w
          mc.height = data.h
          const mctx = mc.getContext("2d")!
          mctx.clearRect(0, 0, mc.width, mc.height)
          mctx.drawImage(img, 0, 0)
          dirtyRef.current = false
          // 背景图
          const st = stages.find((s) => s.id === id)
          const bgUrl = st?.bg?.replace("res://", "/game-assets/")
          if (bgUrl) {
            const bg = new Image()
            bg.onload = () => {
              bgImgRef.current = bg
              render()
            }
            bg.src = bgUrl
          }
          render()
          setStatus({
            ok: true,
            text: fromProfile
              ? `已从地面剖面重建遮罩（${data.w}×${data.h}），涂改后请保存`
              : data.hasMask
                ? `已载入现有遮罩（${data.w}×${data.h}）`
                : `该舞台尚无遮罩，已从地面剖面初始化（${data.w}×${data.h}），涂改后请保存`,
          })
          setBusy(false)
        }
        img.src = data.png
      } catch (e) {
        setStatus({ ok: false, text: String(e) })
        setBusy(false)
      }
    },
    [stages, render]
  )

  useEffect(() => {
    if (stageId) loadMask(stageId, false)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stageId])

  const paintAt = useCallback(
    (px: number, py: number) => {
      const mask = maskCanvasRef.current
      if (!mask) return
      const mctx = mask.getContext("2d")!
      mctx.fillStyle = erase ? "#000" : "#fff"
      mctx.beginPath()
      mctx.arc(px, py, brush, 0, Math.PI * 2)
      mctx.fill()
      dirtyRef.current = true
    },
    [brush, erase]
  )

  const toMaskCoords = (e: React.PointerEvent) => {
    const view = viewRef.current!
    const rect = view.getBoundingClientRect()
    const s = Math.min(
      rect.width / metaRef.current.w,
      rect.height / metaRef.current.h
    )
    const dw = metaRef.current.w * s
    const dh = metaRef.current.h * s
    const ox = (rect.width - dw) / 2
    const oy = (rect.height - dh) / 2
    return {
      x: (e.clientX - rect.left - ox) / s,
      y: (e.clientY - rect.top - oy) / s,
    }
  }

  const onPointerDown = (e: React.PointerEvent) => {
    if (e.button === 2) setErase(true)
    paintingRef.current = true
    const p = toMaskCoords(e)
    lastPtRef.current = p
    paintAt(p.x, p.y)
    render()
  }
  const onPointerMove = (e: React.PointerEvent) => {
    if (!paintingRef.current) return
    const p = toMaskCoords(e)
    const last = lastPtRef.current
    if (last) {
      const dist = Math.hypot(p.x - last.x, p.y - last.y)
      const steps = Math.max(1, Math.floor(dist / Math.max(2, brush * 0.4)))
      for (let i = 1; i <= steps; i++) {
        paintAt(
          last.x + ((p.x - last.x) * i) / steps,
          last.y + ((p.y - last.y) * i) / steps
        )
      }
    }
    lastPtRef.current = p
    render()
  }
  const onPointerUp = (e: React.PointerEvent) => {
    paintingRef.current = false
    lastPtRef.current = null
    if (e.button === 2) setErase(false)
    render()
  }

  const save = async () => {
    const mask = maskCanvasRef.current
    if (!mask || !stageId) return
    setBusy(true)
    try {
      const png = mask.toDataURL("image/png")
      const r = await fetch("/api/walkmask", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ stage: stageId, png }),
      })
      const data = await r.json()
      if (!r.ok) throw new Error(data.error || `HTTP ${r.status}`)
      dirtyRef.current = false
      setStatus({ ok: true, text: `已保存遮罩 ${stageId}.png（${data.w}×${data.h}），游戏内立即生效` })
    } catch (e) {
      setStatus({ ok: false, text: String(e) })
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="flex gap-4">
      <Card className="w-72 shrink-0">
        <CardContent className="pt-4 space-y-4 text-sm">
          <div>
            <div className="mb-1 font-medium">探索舞台</div>
            <Select value={stageId} onValueChange={setStageId}>
              <SelectTrigger>
                <SelectValue placeholder="选择舞台…" />
              </SelectTrigger>
              <SelectContent>
                {stages.map((s) => (
                  <SelectItem key={s.id} value={s.id}>
                    {s.name}（{s.id}）
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="mt-1 text-xs text-stone-500">
              背景：{stage?.bg ? stage.bg.replace("res://", "") : "—"}
            </p>
          </div>
          <div>
            <div className="mb-1 font-medium flex items-center gap-2">
              {erase ? <Eraser className="h-4 w-4" /> : <Paintbrush className="h-4 w-4" />}
              {erase ? "擦除（清除可行走）" : "涂抹（增加可行走）"}
            </div>
            <div className="flex gap-2">
              <Button size="sm" variant={erase ? "outline" : "default"} onClick={() => setErase(false)}>
                涂抹
              </Button>
              <Button size="sm" variant={erase ? "default" : "outline"} onClick={() => setErase(true)}>
                擦除
              </Button>
            </div>
            <p className="mt-1 text-xs text-stone-500">画布上右键临时擦除</p>
          </div>
          <div>
            <div className="mb-1 font-medium">笔刷大小：{brush}px</div>
            <Slider value={[brush]} min={4} max={160} step={2} onValueChange={(v) => setBrush(v[0])} />
          </div>
          <div>
            <div className="mb-1 font-medium">遮罩不透明度：{Math.round(opacity * 100)}%</div>
            <Slider value={[opacity]} min={0.1} max={0.9} step={0.05} onValueChange={(v) => setOpacity(v[0])} />
          </div>
          <div className="flex flex-col gap-2 pt-2 border-t">
            <Button size="sm" onClick={save} disabled={busy || !stageId}>
              <Save className="mr-1 h-4 w-4" /> 保存遮罩
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={busy || !stageId}
              onClick={() => stageId && loadMask(stageId, true)}
            >
              <RefreshCw className="mr-1 h-4 w-4" /> 从地面剖面重建
            </Button>
            <Button size="sm" variant="outline" disabled={busy || !stageId} onClick={() => stageId && loadMask(stageId, false)}>
              重新载入
            </Button>
          </div>
          <div className="text-xs text-stone-500 leading-relaxed border-t pt-2">
            白=可行走面，绿线=人物落脚线（逐列顶缘）。保存即写
            assets/bg/walkmasks/&lt;舞台&gt;.png，游戏端 stage_scene 立即按新遮罩落地。
          </div>
        </CardContent>
      </Card>
      <div className="flex-1">
        <div className="mb-2 flex items-center gap-3">
          <Badge variant="secondary">2048×1152 工作区</Badge>
          {dirtyRef.current && <Badge>有未保存涂改</Badge>}
        </div>
        <canvas
          ref={viewRef}
          className="w-full rounded border bg-stone-900 touch-none"
          style={{ height: "calc(100vh - 220px)", cursor: "crosshair" }}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerLeave={onPointerUp}
          onContextMenu={(e) => e.preventDefault()}
        />
        {status.ok !== null && (
          <div
            className={`mt-2 flex items-start gap-2 text-xs rounded p-2 ${
              status.ok ? "bg-green-50 text-green-800" : "bg-red-50 text-red-700"
            }`}
          >
            {status.ok ? <CircleCheck className="h-4 w-4 mt-0.5" /> : <CircleX className="h-4 w-4 mt-0.5" />}
            <span>{status.text}</span>
          </div>
        )}
      </div>
    </div>
  )
}
