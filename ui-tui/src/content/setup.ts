import type { PanelSection } from '../types.js'

export const SETUP_REQUIRED_TITLE = '需要设置'

export const buildSetupRequiredSections = (): PanelSection[] => [
  {
    text: 'TUI 开始会话前，需要先为 Hermes 配置模型服务商。'
  },
  {
    rows: [
      ['/model', '在当前界面配置 provider 和 model'],
      ['/setup', '在当前界面运行首次设置向导'],
      ['Ctrl+C', '退出后手动运行 `hermes setup`']
    ],
    title: '操作'
  }
]
