import type { Register } from 'claude-code'

// Redraws each block of Claude's replies in the terminal with colour cues for skimming. Plain lines (paragraphs,
// headings, list items) are drawn here; tables, code fences, quotes and rules go to the engine's own Markdown, as
// does anything this mod can't parse. Only the drawing changes: the stored reply, and ctrl+o, stay as written.

const LABEL = 'claude'          // headings, and a bold lead-in like "**Moved to Done:**"
const CODE = 'permission'       // `inline code`: paths, commands, flags
const IDENT = 'suggestion'      // KEV-1344, TEA-355, PR #106
const LINK = 'suggestion'
const WARN = 'warning'          // "not committed", "can't", "failed"...
const GOOD = 'success'          // "passed", "verified"...

type Style = { color?: string; bold?: boolean; italic?: boolean; underline?: boolean }
type Span = { text: string; style?: Style; href?: string }
type Segment = { kind: 'markdown'; text: string } | { kind: 'line'; text: string } | { kind: 'blank' }

const MARKDOWN_TOKEN =
  /(`[^`\n]+`)|(\*\*[^*\n]+\*\*)|(\[[^\]\n]+\]\(<?[^)\s>]+>?\))|(\*[^*\s][^*\n]*\*)|(https?:\/\/[^\s)>\]]+)/g
const HIGHLIGHT = new RegExp(
  [
    String.raw`(\b[A-Z][A-Z0-9]{1,6}-\d+\b|(?<![\w#&])#\d+\b)`,
    String.raw`(\b\d+(?:[.,]\d+)?(?:\s?[×x]\s?\d+(?:[.,]\d+)?)*\s?(?:mm|cm³|cm|kg|g|%|°C?|ms|s|min|h|KB|MB|GB|px|layers|days?|hours?|minutes?|seconds?|tests?|files?|lines?|stories|issues)(?![\w]))`,
    String.raw`(\b(?:not committed|uncommitted|not (?:yet|verified|tested|run|merged|loaded|built)|haven't|hasn't|failed|fails|failing|can't|cannot|couldn't|won't|wasn't|unverified|blocked|broken|refused|denied|careful|caution)\b)`,
    String.raw`(\b(?:passes|passed|verified|confirmed)\b)`,
  ].join('|'),
  'gi',
)

function highlight(text: string, base: Style = {}): Span[] {
  const spans: Span[] = []
  let at = 0
  for (const m of text.matchAll(HIGHLIGHT)) {
    const i = m.index ?? 0
    if (i > at) spans.push({ text: text.slice(at, i), style: base })
    const [, ident, figure, warn] = m
    // identifiers are case-sensitive; the flag is for the word lists
    const isIdent = ident !== undefined && /^[A-Z#]/.test(ident) && !/^[A-Z][a-z]/.test(ident)
    const style: Style = isIdent ? { ...base, color: IDENT }
      : figure !== undefined ? { ...base, bold: true }
      : warn !== undefined ? { ...base, color: WARN }
      : ident !== undefined ? base
      : { ...base, color: GOOD }
    spans.push({ text: m[0], style })
    at = i + m[0].length
  }
  if (at < text.length) spans.push({ text: text.slice(at), style: base })
  return spans
}

function inline(text: string): Span[] {
  const spans: Span[] = []
  let at = 0
  for (const m of text.matchAll(MARKDOWN_TOKEN)) {
    const i = m.index ?? 0
    if (i > at) spans.push(...highlight(text.slice(at, i)))
    const [token, code, bold, link, italic, url] = m
    if (code) spans.push({ text: code.slice(1, -1), style: { color: CODE } })
    else if (bold) {
      const inner = bold.slice(2, -2)
      const isLabel = text.slice(0, i).trim() === '' || /:\s*$/.test(inner)
      spans.push(...highlight(inner, isLabel ? { bold: true, color: LABEL } : { bold: true }))
    } else if (link) {
      const [, label, href] = /^\[([^\]]+)\]\(<?([^)\s>]+)>?\)$/.exec(link) ?? []
      spans.push(label && href ? { text: label, href, style: { color: LINK, underline: true } } : { text: token })
    } else if (italic) spans.push(...highlight(italic.slice(1, -1), { italic: true }))
    else if (url) spans.push({ text: url, href: url, style: { color: LINK, underline: true } })
    at = i + token.length
  }
  if (at < text.length) spans.push(...highlight(text.slice(at)))
  return spans
}

function segments(text: string): Segment[] {
  const lines = text.split('\n')
  const line = (i: number) => lines[i] ?? ''
  const isBlockLine = (s: string) => /^\s*[|>]/.test(s)
  const out: Segment[] = []
  const markdown = (block: string[]) => {
    const last = out[out.length - 1]
    if (last?.kind === 'markdown') last.text += '\n' + block.join('\n')
    else out.push({ kind: 'markdown', text: block.join('\n') })
  }
  for (let i = 0; i < lines.length; i++) {
    const current = line(i)
    if (/^\s*(```|~~~)/.test(current)) {
      const fence = current.trim().slice(0, 3)
      const block = [current]
      while (++i < lines.length) {
        block.push(line(i))
        if (line(i).trim().startsWith(fence)) break
      }
      markdown(block)
    } else if (isBlockLine(current)) {
      const block = [current]
      while (i + 1 < lines.length && isBlockLine(line(i + 1))) block.push(line(++i))
      markdown(block)
    } else if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(current)) {
      markdown([current])
    } else if (current.trim() === '') {
      if (out.length > 0 && out[out.length - 1]?.kind !== 'blank') out.push({ kind: 'blank' })
    } else out.push({ kind: 'line', text: current })
  }
  while (out[out.length - 1]?.kind === 'blank') out.pop()
  return out
}

export const register: Register = on => {
  on('ui.render', { component: 'AssistantMessage' }, ($, e, next) => {
    if (e.surface !== 'terminal' || e.props.isSummary) return next(e)

    const parts = segments(e.props.text)
    if (!parts.some(p => p.kind === 'line')) return next(e)

    const { Box, Text, Link, Markdown } = $.ui.resolve(e)

    const drawSpans = (spans: Span[]) =>
      spans.map(s => {
        const { color, bold, italic, underline } = s.style ?? {}
        const body = s.href ? <Link href={s.href}>{s.text}</Link> : s.text
        return color || bold || italic || underline
          ? <Text color={color} bold={bold} italic={italic} underline={underline}>{body}</Text>
          : body
      })

    const drawLine = (line: string) => {
      const heading = /^#{1,6}\s+(.*)$/.exec(line)
      if (heading) {
        return <Text bold color={LABEL}>{(heading[1] ?? '').replace(/\*\*/g, '')}</Text>
      }
      const item = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/.exec(line)
      if (item) {
        const [, indent = '', marker = '', rest = ''] = item
        const mark = /\d/.test(marker) ? marker + ' ' : '• '
        return (
          <Box flexDirection="row" paddingLeft={Math.floor(indent.length / 2) * 2}>
            <Box flexShrink={0}><Text color={LABEL}>{mark}</Text></Box>
            <Box flexGrow={1} flexShrink={1}><Text>{drawSpans(inline(rest))}</Text></Box>
          </Box>
        )
      }
      return <Text>{drawSpans(inline(line))}</Text>
    }

    return (
      <Box flexDirection="row" marginTop={1}>
        <Box flexShrink={0} width={2}><Text>{e.props.isFirstOfReply ? '●' : ' '}</Text></Box>
        <Box flexDirection="column" flexGrow={1} flexShrink={1}>
          {parts.map(p =>
            p.kind === 'markdown' ? <Markdown text={p.text} />
              : p.kind === 'blank' ? <Box height={1} />
              : drawLine(p.text),
          )}
        </Box>
      </Box>
    )
  })
}
