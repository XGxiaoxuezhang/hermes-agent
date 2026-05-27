import { forceRedraw, type MouseTrackingMode } from '@hermes/ink'

import { NO_CONFIRM_DESTRUCTIVE } from '../../../config/env.js'
import { dailyFortune, randomFortune } from '../../../content/fortunes.js'
import { HOTKEYS } from '../../../content/hotkeys.js'
import { isSectionName, nextDetailsMode, parseDetailsMode, SECTION_NAMES } from '../../../domain/details.js'
import type {
  ConfigGetValueResponse,
  ConfigSetResponse,
  SessionSaveResponse,
  SessionStatusResponse,
  SessionSteerResponse,
  SessionTitleResponse,
  SessionUndoResponse
} from '../../../gatewayTypes.js'
import { writeClipboardText } from '../../../lib/clipboard.js'
import { writeOsc52Clipboard } from '../../../lib/osc52.js'
import { configureDetectedTerminalKeybindings, configureTerminalKeybindings } from '../../../lib/terminalSetup.js'
import type { Msg, PanelSection } from '../../../types.js'
import type { StatusBarMode } from '../../interfaces.js'
import { patchOverlayState } from '../../overlayStore.js'
import { patchUiState } from '../../uiStore.js'
import type { SlashCommand } from '../types.js'

const flagFromArg = (arg: string, current: boolean): boolean | null => {
  if (!arg) {
    return !current
  }

  const mode = arg.trim().toLowerCase()

  if (mode === 'on') {
    return true
  }

  if (mode === 'off') {
    return false
  }

  if (mode === 'toggle') {
    return !current
  }

  return null
}

// `/mouse` toggles between full tracking and off when called bare so the
// old binary muscle-memory still works. Explicit presets (wheel / buttons /
// all) target the tmux-friendly hover-free subsets.
const MOUSE_MODE_ALIASES: Record<string, MouseTrackingMode> = {
  all: 'all',
  any: 'all',
  button: 'buttons',
  buttons: 'buttons',
  click: 'buttons',
  full: 'all',
  off: 'off',
  on: 'all',
  scroll: 'wheel',
  wheel: 'wheel'
}

const mouseModeFromArg = (arg: string, current: MouseTrackingMode): MouseTrackingMode | null => {
  if (!arg || arg.trim().toLowerCase() === 'toggle') {
    return current === 'off' ? 'all' : 'off'
  }

  return MOUSE_MODE_ALIASES[arg.trim().toLowerCase()] ?? null
}

const RESET_WORDS = new Set(['reset', 'clear', 'default'])
const CYCLE_WORDS = new Set(['cycle', 'toggle'])

const DETAILS_USAGE =
  'usage: /details [hidden|collapsed|expanded|cycle]  or  /details <section> [hidden|collapsed|expanded|reset]'

const DETAILS_SECTION_USAGE = 'usage: /details <section> [hidden|collapsed|expanded|reset]'

export const coreCommands: SlashCommand[] = [
  {
    help: '查看命令和快捷键',
    name: 'help',
    run: (_arg, ctx) => {
      const sections: PanelSection[] = (ctx.local.catalog?.categories ?? []).map(cat => ({
        rows: cat.pairs,
        title: cat.name
      }))

      if (ctx.local.catalog?.skillCount) {
        sections.push({ text: `${ctx.local.catalog.skillCount} skill commands available — /skills to browse` })
      }

      sections.push(
        {
          rows: [
            ['/details [hidden|collapsed|expanded|cycle]', '设置全局 Agent 详情显示模式'],
            [
              '/details <section> [hidden|collapsed|expanded|reset]',
              '覆盖单个区块（thinking/tools/subagents/activity）'
            ],
            ['/fortune [random|daily]', '显示随机或每日本地 fortune']
          ],
          title: 'TUI'
        },
        { rows: HOTKEYS, title: '快捷键' }
      )

      ctx.transcript.panel(ctx.ui.theme.brand.helpHeader, sections)
    }
  },

  {
    aliases: ['exit'],
    help: '退出 Hermes',
    name: 'quit',
    run: (_arg, ctx) => ctx.session.die()
  },

  {
    help: '更新 Hermes Agent 到最新版（会退出 TUI）',
    name: 'update',
    run: (_arg, ctx) => {
      ctx.transcript.sys('exiting TUI to run update...')
      // Exit code 42 signals the Python wrapper to exec `hermes update`.
      // Use dieWithCode for proper cleanup (gateway kill + Ink unmount).
      setTimeout(() => ctx.session.dieWithCode(42), 100)
    }
  },

  {
    aliases: ['scroll'],
    help: '设置鼠标跟踪模式 [on|off|toggle|wheel|buttons|all]',
    name: 'mouse',
    run: (arg, ctx) => {
      const current = ctx.ui.mouseTracking
      const next = mouseModeFromArg(arg, current)

      if (next === null) {
        return ctx.transcript.sys('usage: /mouse [on|off|toggle|wheel|buttons|all]')
      }

      patchUiState({ mouseTracking: next })
      ctx.gateway.rpc<ConfigSetResponse>('config.set', { key: 'mouse', value: next }).catch(() => {})

      queueMicrotask(() => ctx.transcript.sys(`mouse tracking ${next}`))
    }
  },

  {
    aliases: ['copy-mode', 'native-copy'],
    help: '切换终端原生框选复制模式 [on|off|toggle]',
    name: 'copymode',
    run: (arg, ctx) => {
      const mode = arg.trim().toLowerCase()

      if (mode && mode !== 'on' && mode !== 'off' && mode !== 'toggle') {
        return ctx.transcript.sys('usage: /copy-mode [on|off|toggle]')
      }

      const current = ctx.ui.nativeCopyMouseTracking !== null
      const next = mode === 'on' ? true : mode === 'off' ? false : !current

      if (next) {
        if (current) {
          return ctx.transcript.sys('native copy mode already on — mouse tracking off')
        }

        patchUiState({
          mouseTracking: 'off',
          nativeCopyMouseTracking: ctx.ui.mouseTracking
        })
        return ctx.transcript.sys('native copy mode on — use the terminal selection/copy; /copy-mode off restores TUI mouse')
      }

      const restore = ctx.ui.nativeCopyMouseTracking ?? 'all'

      patchUiState({
        mouseTracking: restore,
        nativeCopyMouseTracking: null
      })
      ctx.transcript.sys(`native copy mode off — mouse tracking ${restore}`)
    }
  },

  {
    aliases: ['new'],
    help: '开始新会话',
    name: 'clear',
    run: (arg, ctx, cmd) => {
      if (ctx.session.guardBusySessionSwitch('switch sessions')) {
        return
      }

      const isNew = cmd.startsWith('/new')
      const requestedTitle = isNew ? arg.trim() : ''

      const commit = () => {
        patchUiState({ status: '正在创建会话…' })
        ctx.session.newSession(isNew ? 'new session started' : undefined, requestedTitle || undefined)
      }

      if (NO_CONFIRM_DESTRUCTIVE) {
        return commit()
      }

      patchOverlayState({
        confirm: {
          cancelLabel: 'No, keep going',
          confirmLabel: isNew ? 'Yes, start a new session' : 'Yes, clear the session',
          danger: true,
          detail: 'This ends the current conversation and clears the transcript.',
          onConfirm: commit,
          title: isNew ? 'Start a new session?' : 'Clear the current session?'
        }
      })
    }
  },

  {
    help: '强制重绘界面',
    name: 'redraw',
    run: (_arg, ctx) => {
      forceRedraw(process.stdout)
      ctx.transcript.sys('ui redrawn')
    }
  },

  {
    help: '查看当前会话状态',
    name: 'status',
    run: (_arg, ctx) => {
      if (!ctx.sid) {
        return ctx.transcript.sys('no active session')
      }

      ctx.gateway
        .rpc<SessionStatusResponse>('session.status', { session_id: ctx.sid })
        .then(ctx.guarded<SessionStatusResponse>(r => ctx.transcript.page(r.output || '(no status)', 'Status')))
        .catch(ctx.guardedErr)
    }
  },

  {
    help: '恢复历史会话',
    name: 'resume',
    run: (arg, ctx) => {
      if (ctx.session.guardBusySessionSwitch('switch sessions')) {
        return
      }

      arg ? ctx.session.resumeById(arg) : patchOverlayState({ picker: true })
    }
  },

  {
    help: '设置或查看当前会话标题',
    name: 'title',
    run: (arg, ctx) => {
      if (!ctx.sid) {
        return ctx.transcript.sys('no active session')
      }

      const title = arg.trim()

      if (!arg) {
        ctx.gateway
          .rpc<SessionTitleResponse>('session.title', { session_id: ctx.sid })
          .then(
            ctx.guarded<SessionTitleResponse>(r => {
              const current = (r?.title ?? '').trim()
              ctx.transcript.sys(current ? `title: ${current}` : 'no title set')
            })
          )
          .catch(ctx.guardedErr)

        return
      }

      if (!title) {
        return ctx.transcript.sys('usage: /title <your session title>')
      }

      ctx.gateway
        .rpc<SessionTitleResponse>('session.title', { session_id: ctx.sid, title })
        .then(
          ctx.guarded<SessionTitleResponse>(r => {
            const next = (r?.title ?? title).trim()
            const suffix = r?.pending ? ' (queued while session initializes)' : ''
            ctx.transcript.sys(`session title set: ${next}${suffix}`)
          })
        )
        .catch(ctx.guardedErr)
    }
  },

  {
    help: '切换紧凑对话显示',
    name: 'compact',
    run: (arg, ctx) => {
      const next = flagFromArg(arg, ctx.ui.compact)

      if (next === null) {
        return ctx.transcript.sys('usage: /compact [on|off|toggle]')
      }

      patchUiState({ compact: next })
      ctx.gateway.rpc<ConfigSetResponse>('config.set', { key: 'compact', value: next ? 'on' : 'off' }).catch(() => {})

      queueMicrotask(() => ctx.transcript.sys(`compact ${next ? 'on' : 'off'}`))
    }
  },

  {
    aliases: ['detail'],
    help: '控制 Agent 详情显示（全局或按区块）',
    name: 'details',
    run: (arg, ctx) => {
      const { gateway, transcript, ui } = ctx

      if (!arg) {
        gateway
          .rpc<ConfigGetValueResponse>('config.get', { key: 'details_mode' })
          .then(r => {
            if (ctx.stale()) {
              return
            }

            const mode = parseDetailsMode(r?.value) ?? ui.detailsMode
            patchUiState({ detailsMode: mode, detailsModeCommandOverride: false })

            const overrides = SECTION_NAMES.filter(s => ui.sections[s])
              .map(s => `${s}=${ui.sections[s]}`)
              .join(' ')

            transcript.sys(`details: ${mode}${overrides ? `  (${overrides})` : ''}`)
          })
          .catch(() => !ctx.stale() && transcript.sys(`details: ${ui.detailsMode}`))

        return
      }

      const [first, second] = arg.trim().toLowerCase().split(/\s+/)

      if (second && isSectionName(first)) {
        const reset = RESET_WORDS.has(second)
        const mode = reset ? null : parseDetailsMode(second)

        if (!reset && !mode) {
          return transcript.sys(DETAILS_SECTION_USAGE)
        }

        const { [first]: _drop, ...rest } = ui.sections

        patchUiState({ sections: mode ? { ...rest, [first]: mode } : rest })
        gateway
          .rpc<ConfigSetResponse>('config.set', { key: `details_mode.${first}`, value: mode ?? '' })
          .catch(() => {})
        transcript.sys(`details ${first}: ${mode ?? 'reset'}`)

        return
      }

      const next = CYCLE_WORDS.has(first ?? '') ? nextDetailsMode(ui.detailsMode) : parseDetailsMode(first)

      if (!next) {
        return transcript.sys(DETAILS_USAGE)
      }

      const sections = Object.fromEntries(SECTION_NAMES.map(section => [section, next]))

      patchUiState({ detailsMode: next, detailsModeCommandOverride: true, sections })
      gateway.rpc<ConfigSetResponse>('config.set', { key: 'details_mode', value: next }).catch(() => {})
      transcript.sys(`details: ${next}`)
    }
  },

  {
    help: '显示本地 fortune',
    name: 'fortune',
    run: (arg, ctx) => {
      const key = arg.trim().toLowerCase()

      if (!arg || key === 'random') {
        return ctx.transcript.sys(randomFortune())
      }

      if (['daily', 'stable', 'today'].includes(key)) {
        return ctx.transcript.sys(dailyFortune(ctx.sid))
      }

      ctx.transcript.sys('usage: /fortune [random|daily]')
    }
  },

  {
    help: '复制选区或助手消息',
    name: 'copy',
    run: async (arg, ctx) => {
      const { sys } = ctx.transcript

      if (!arg && ctx.composer.hasSelection) {
        const text = await ctx.composer.selection.copySelection()

        if (text) {
          return sys(`copied ${text.length} characters`)
        } else {
          return sys(
            'clipboard copy failed — try HERMES_TUI_FORCE_OSC52=1 to force the escape sequence'
          )
        }
      }

      if (arg && Number.isNaN(parseInt(arg, 10))) {
        return sys('usage: /copy [number]')
      }

      const all = ctx.local.getHistoryItems().filter(m => m.role === 'assistant')
      const target = all[arg ? Math.min(parseInt(arg, 10), all.length) - 1 : all.length - 1]

      if (!target) {
        return sys('nothing to copy — start a conversation first')
      }

      void writeClipboardText(target.text)
        .then(nativeOk => {
          if (ctx.stale()) {
            return
          }

          if (nativeOk) {
            sys('copied to clipboard')
          } else {
            writeOsc52Clipboard(target.text)
            sys('sent OSC52 copy sequence (terminal support required)')
          }
        })
        .catch(error => {
          if (!ctx.stale()) {
            sys(`copy failed: ${String(error)}`)
          }
        })
    }
  },

  {
    help: '附加剪贴板图片',
    name: 'paste',
    run: (arg, ctx) => (arg ? ctx.transcript.sys('usage: /paste') : ctx.composer.paste())
  },

  {
    help: '配置 IDE 终端快捷键（多行、撤销、重做）',
    name: 'terminal-setup',
    run: (arg, ctx) => {
      const target = arg.trim().toLowerCase()

      if (target && !['auto', 'cursor', 'vscode', 'windsurf'].includes(target)) {
        return ctx.transcript.sys('usage: /terminal-setup [auto|vscode|cursor|windsurf]')
      }

      const runner =
        !target || target === 'auto'
          ? configureDetectedTerminalKeybindings()
          : configureTerminalKeybindings(target as 'cursor' | 'vscode' | 'windsurf')

      void runner
        .then(result => {
          if (ctx.stale()) {
            return
          }

          ctx.transcript.sys(result.message)

          if (result.success && result.requiresRestart) {
            ctx.transcript.sys('restart the IDE terminal for the new keybindings to take effect')
          }
        })
        .catch(error => {
          if (!ctx.stale()) {
            ctx.transcript.sys(`terminal setup failed: ${String(error)}`)
          }
        })
    }
  },

  {
    help: '查看 gateway 日志',
    name: 'logs',
    run: (arg, ctx) => {
      const text = ctx.gateway.gw.getLogTail(Math.min(80, Math.max(1, parseInt(arg, 10) || 20)))

      text ? ctx.transcript.page(text, 'Logs') : ctx.transcript.sys('no gateway logs')
    }
  },

  {
    help: '查看当前对话记录（用户和助手消息）',
    name: 'history',
    run: (arg, ctx) => {
      // The CLI-side `/history` runs in a detached slash-worker subprocess
      // that never sees the TUI's turns — it only surfaces whatever was
      // persisted before this process started.  Render the TUI's own
      // transcript so `/history` actually reflects what the user just did.
      const items = ctx.local.getHistoryItems().filter(m => m.role === 'user' || m.role === 'assistant')

      if (!items.length) {
        return ctx.transcript.sys('no conversation yet')
      }

      const preview = Math.max(80, parseInt(arg, 10) || 400)

      const lines = items.map((m, i) => {
        const tag = m.role === 'user' ? `You #${i + 1}` : `Hermes #${i + 1}`
        const body = m.text.trim() || (m.tools?.length ? `(${m.tools.length} tool calls)` : '(empty)')
        const clipped = body.length > preview ? `${body.slice(0, preview).trimEnd()}…` : body

        return `[${tag}]\n${clipped}`
      })

      ctx.transcript.page(lines.join('\n\n'), 'History')
    }
  },

  {
    help: '将当前对话保存为 JSON',
    name: 'save',
    run: (_arg, ctx) => {
      const hasConversation = ctx.local
        .getHistoryItems()
        .some(m => m.role === 'user' || m.role === 'assistant' || m.role === 'tool')

      if (!hasConversation) {
        return ctx.transcript.sys('no conversation yet')
      }

      if (!ctx.sid) {
        return ctx.transcript.sys('no active session — nothing to save')
      }

      ctx.gateway
        .rpc<SessionSaveResponse>('session.save', { session_id: ctx.sid })
        .then(
          ctx.guarded<SessionSaveResponse>(r => {
            const file = r?.file

            if (file) {
              ctx.transcript.sys(`conversation saved to: ${file}`)
            } else {
              ctx.transcript.sys('failed to save')
            }
          })
        )
        .catch(ctx.guardedErr)
    }
  },

  {
    aliases: ['sb'],
    help: '设置状态栏位置 (on|off|top|bottom)',
    name: 'statusbar',
    run: (arg, ctx) => {
      const mode = arg.trim().toLowerCase()
      const toggle: StatusBarMode = ctx.ui.statusBar === 'off' ? 'top' : 'off'

      const next: null | StatusBarMode =
        !mode || mode === 'toggle'
          ? toggle
          : mode === 'on' || mode === 'top'
            ? 'top'
            : mode === 'off' || mode === 'bottom'
              ? mode
              : null

      if (!next) {
        return ctx.transcript.sys('usage: /statusbar [on|off|top|bottom|toggle]')
      }

      patchUiState({ statusBar: next })
      ctx.gateway.rpc<ConfigSetResponse>('config.set', { key: 'statusbar', value: next }).catch(() => {})

      queueMicrotask(() => ctx.transcript.sys(`status bar ${next}`))
    }
  },

  {
    aliases: ['q'],
    help: '查看队列或加入一条消息',
    name: 'queue',
    run: (arg, ctx) => {
      if (!arg) {
        return ctx.transcript.sys(`${ctx.composer.queueRef.current.length} queued message(s)`)
      }

      ctx.composer.enqueue(arg)
      ctx.transcript.sys(`queued: "${arg.slice(0, 50)}${arg.length > 50 ? '…' : ''}"`)
    }
  },

  {
    help: '在下一次工具调用后插入消息（不中断）',
    name: 'steer',
    run: (arg, ctx) => {
      const payload = arg?.trim() ?? ''

      if (!payload) {
        return ctx.transcript.sys('usage: /steer <prompt>')
      }

      // If the agent isn't running, fall back to the queue so the user's
      // message isn't lost — identical semantics to the gateway handler.
      if (!ctx.ui.busy || !ctx.sid) {
        ctx.composer.enqueue(payload)
        ctx.transcript.sys(
          `no active turn — queued for next: "${payload.slice(0, 50)}${payload.length > 50 ? '…' : ''}"`
        )

        return
      }

      ctx.gateway
        .rpc<SessionSteerResponse>('session.steer', { session_id: ctx.sid, text: payload })
        .then(
          ctx.guarded<SessionSteerResponse>(r => {
            if (r?.status === 'queued') {
              ctx.transcript.sys(
                `steer queued — arrives after next tool call: "${payload.slice(0, 50)}${payload.length > 50 ? '…' : ''}"`
              )
            } else {
              ctx.transcript.sys('steer rejected')
            }
          })
        )
        .catch(ctx.guardedErr)
    }
  },

  {
    help: '撤销上一轮对话',
    name: 'undo',
    run: (_arg, ctx) => {
      if (!ctx.sid) {
        return ctx.transcript.sys('nothing to undo')
      }

      ctx.gateway.rpc<SessionUndoResponse>('session.undo', { session_id: ctx.sid }).then(
        ctx.guarded<SessionUndoResponse>(r => {
          if ((r.removed ?? 0) > 0) {
            ctx.transcript.setHistoryItems((prev: Msg[]) => ctx.transcript.trimLastExchange(prev))
            ctx.transcript.sys(`undid ${r.removed} messages`)
          } else {
            ctx.transcript.sys('nothing to undo')
          }
        })
      )
    }
  },

  {
    help: '重试上一条用户消息',
    name: 'retry',
    run: (_arg, ctx) => {
      const last = ctx.local.getLastUserMsg()

      if (!last) {
        return ctx.transcript.sys('nothing to retry')
      }

      if (!ctx.sid) {
        return ctx.transcript.send(last)
      }

      ctx.gateway.rpc<SessionUndoResponse>('session.undo', { session_id: ctx.sid }).then(
        ctx.guarded<SessionUndoResponse>(r => {
          if ((r.removed ?? 0) <= 0) {
            return ctx.transcript.sys('nothing to retry')
          }

          ctx.transcript.setHistoryItems((prev: Msg[]) => ctx.transcript.trimLastExchange(prev))
          ctx.transcript.send(last)
        })
      )
    }
  }
]
