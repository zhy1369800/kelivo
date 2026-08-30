/// 语音通话专用文本净化器：去除思考标签、Markdown 语法标记与 Emoji，确保 TTS 朗读与字幕自然流畅
class VoiceTextSanitizer {
  // 只匹配有完整闭合标签的 <think>...</think> 块
  static final RegExp _thinkTagClosedRegex = RegExp(
    r'<think>[\s\S]*?</think>',
    caseSensitive: false,
  );

  // 兜底：匹配以 <think> 开头但无闭合标签（被截断的响应），保护后续正文不被误删
  static final RegExp _thinkTagUnclosedRegex = RegExp(
    r'<think>[^<]*$',
    caseSensitive: false,
  );

  static final RegExp _codeBlockRegex = RegExp(
    r'```[\s\S]*?```',
  );

  static final RegExp _inlineCodeRegex = RegExp(
    r'`([^`]+)`',
  );

  static final RegExp _markdownLinkRegex = RegExp(
    r'\[([^\]]+)\]\([^)]+\)',
  );

  static final RegExp _markdownHeaderRegex = RegExp(
    r'^\s*#{1,6}\s+',
    multiLine: true,
  );

  static final RegExp _markdownListPrefixRegex = RegExp(
    r'^\s*[-+]\s+',
    multiLine: true,
  );

  static final RegExp _markdownOrderedListPrefixRegex = RegExp(
    r'^\s*\d+\.\s+',
    multiLine: true,
  );

  static final RegExp _markdownQuotePrefixRegex = RegExp(
    r'^\s*>\s+',
    multiLine: true,
  );

  // 只匹配成对的 Markdown 格式标记（粗体/斜体/删除线），避免误删正文中合法的单个符号
  static final RegExp _boldRegex = RegExp(r'\*\*([^*]+)\*\*');
  static final RegExp _italicStarRegex = RegExp(r'\*([^*\n]+)\*');
  static final RegExp _boldUnderscoreRegex = RegExp(r'__([^_]+)__');
  static final RegExp _italicUnderscoreRegex = RegExp(r'_([^_\n]+)_');
  static final RegExp _strikethroughRegex = RegExp(r'~~([^~]+)~~');

  // 匹配常见 Emoji 与图形符号
  static final RegExp _emojiRegex = RegExp(
    r'[\u{1F300}-\u{1F9FF}\u{1FA00}-\u{1FAFF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{FE00}-\u{FE0F}\u{1F1E6}-\u{1F1FF}]',
    unicode: true,
  );

  static final RegExp _multipleNewlinesRegex = RegExp(r'\n{2,}');
  static final RegExp _multipleSpacesRegex = RegExp(r'[ \t]{2,}');

  /// 清洗输入文本，输出适合语音合成（TTS）与灵动岛字幕的纯净口语文本
  static String clean(String raw) {
    if (raw.trim().isEmpty) return '';

    var text = raw;

    // 1. 去除完整的 <think>...</think> 块
    text = text.replaceAll(_thinkTagClosedRegex, '');

    // 2. 去除截断的未闭合 <think> 块（防止末尾孤立标签干扰）
    text = text.replaceAll(_thinkTagUnclosedRegex, '');

    // 3. 去除多行代码块
    text = text.replaceAll(_codeBlockRegex, '');

    // 4. 将行内代码 `code` 转为 code
    text = text.replaceAllMapped(_inlineCodeRegex, (m) => m.group(1) ?? '');

    // 5. 将 [链接文本](url) 转为 链接文本
    text = text.replaceAllMapped(_markdownLinkRegex, (m) => m.group(1) ?? '');

    // 6. 去除 Markdown 标题符号 (#)
    text = text.replaceAll(_markdownHeaderRegex, '');

    // 7. 去除列表前缀 (- / + / 1.)
    text = text.replaceAll(_markdownListPrefixRegex, '');
    text = text.replaceAll(_markdownOrderedListPrefixRegex, '');

    // 8. 去除引用前缀 (>)
    text = text.replaceAll(_markdownQuotePrefixRegex, '');

    // 9. 精准去除成对格式标记，保留正文内容（不误伤合法的下划线/单个星号）
    text = text.replaceAllMapped(_boldRegex, (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(_boldUnderscoreRegex, (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(_strikethroughRegex, (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(_italicStarRegex, (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(_italicUnderscoreRegex, (m) => m.group(1) ?? '');

    // 10. 去除 Emoji 表情符号
    text = text.replaceAll(_emojiRegex, '');

    // 11. 规范化空格与换行
    text = text.replaceAll(_multipleSpacesRegex, ' ');
    text = text.replaceAll(_multipleNewlinesRegex, '\n');

    return text.trim();
  }
}
