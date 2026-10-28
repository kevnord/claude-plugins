import { expect, test } from 'claude-code/testing'

const reply = (text: string, extra: Record<string, unknown> = {}) => ({
  plugin: 'skim-colors',
  component: 'AssistantMessage',
  requestId: 'msg-1',
  surface: 'terminal',
  props: { text, isFirstOfReply: true, ...extra },
} as const)

const REPLY = [
  '**Moved to Done:**',
  '- **TEA-345** (c4hero): merged in PR #224 on 2026-10-07.',
  '- The logo is 44 × 42 mm and `packing-station.scad` is not committed.',
  '',
  '| a | b |',
  '| - | - |',
  '| 1 | 2 |',
].join('\n')

test('plain lines are coloured and the table goes to Markdown', async ($, on) => {
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })

  const ui = await $.ui.mount(reply(REPLY))
  // the innermost Text with exactly these words carries the run's style
  const styleOf = async (text: string) => {
    const all = await ui.findAll({ type: 'Text', text })
    return all[all.length - 1]?.props
  }

  expect(await ui.find({ type: 'Text', text: 'engine' })).toBe(undefined)
  expect((await styleOf('Moved to Done:'))?.color).toBe('claude')
  expect((await styleOf('TEA-345'))?.color).toBe('suggestion')
  expect((await styleOf('#224'))?.color).toBe('suggestion')
  expect((await styleOf('44 × 42 mm'))?.bold).toBe(true)
  expect((await styleOf('packing-station.scad'))?.color).toBe('permission')
  expect((await styleOf('not committed'))?.color).toBe('warning')
  expect((await ui.find({ type: 'Markdown' }))?.text).toContain('| 1 | 2 |')
  await ui.unmount()
})

test('a summary and a reply that is all table stay the engine\'s', async ($, on) => {
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })

  for (const props of [reply('Some **text**', { isSummary: true }), reply('| a |\n| - |\n| 1 |')]) {
    const ui = await $.ui.mount(props)
    expect(await ui.find({ type: 'Text', text: 'engine' })).not.toBe(undefined)
    await ui.unmount()
  }
})
