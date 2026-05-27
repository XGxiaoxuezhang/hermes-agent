import { formatBytes, performHeapDump } from '../../../lib/memory.js'
import type { SlashCommand } from '../types.js'

export const debugCommands: SlashCommand[] = [
  {
    help: '写入 V8 heap snapshot 和内存诊断（见 HERMES_HEAPDUMP_DIR）',
    name: 'heapdump',
    run: (_arg, ctx) => {
      const { heapUsed, rss } = process.memoryUsage()

      ctx.transcript.sys(`writing heap dump (heap ${formatBytes(heapUsed)} · rss ${formatBytes(rss)})…`)

      void performHeapDump('manual').then(r => {
        if (ctx.stale()) {
          return
        }

        if (!r.success) {
          return ctx.transcript.sys(`heapdump failed: ${r.error ?? 'unknown error'}`)
        }

        ctx.transcript.sys(`heapdump: ${r.heapPath}`)
        ctx.transcript.sys(`diagnostics: ${r.diagPath}`)
      })
    }
  },

  {
    help: '打印实时 V8 heap 和 rss 数值',
    name: 'mem',
    run: (_arg, ctx) => {
      const { arrayBuffers, external, heapTotal, heapUsed, rss } = process.memoryUsage()

      ctx.transcript.panel('Memory', [
        {
          rows: [
            ['heap used', formatBytes(heapUsed)],
            ['heap total', formatBytes(heapTotal)],
            ['external', formatBytes(external)],
            ['array buffers', formatBytes(arrayBuffers)],
            ['rss', formatBytes(rss)],
            ['uptime', `${process.uptime().toFixed(0)}s`]
          ]
        }
      ])
    }
  }
]
