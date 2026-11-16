# 读写 OpenReview 和 Google Doc 的做法

## OpenReview

- 审稿意见要登录才能看全：在已登录的浏览器标签页里用 JS 工具 `fetch('https://api2.openreview.net/notes?forum=<forum_id>', {credentials: 'include'})`，把结果存进 `window` 变量，再分段取字段。
- 浏览器 JS 工具的返回会在约 1000 字符处截断，所以按字段、按 900 字符左右分段输出。返回值里带 URL 或查询串时可能被拦成 `[BLOCKED: Cookie/query string data]`，只输出需要的字段。
- 评论框的字数上限用 `https://api2.openreview.net/invitations?replyForum=<forum_id>` 查：`Official_Comment` 下 `comment` 的 `maxLength`。能否上传 revision PDF 看是否有 `Rebuttal_Revision` 之类的 invitation。每位 reviewer 能发几条评论、评论对谁可见，看场地说明或发评论的表单，拿不准就问用户。

## Google Doc

先读 `anthropic-skills:google-workspace` skill；下面是做 rebuttal 时额外要注意的地方。

- **红字只在 Docs API 的 JSON 里看得到**：用 `read_doc` 读，逐个 textRun 看 `textStyle.foregroundColor`。Drive 的 `read_file_content` 输出 Markdown，看不到颜色。
- **批注要用 Drive 读**：`read_file_content` 加 `includeComments: true`，批注锚定的文字夹在 `<comment_start id=…>` 和 `<comment_end id=…>` 之间。
- **`read_doc` 的结果常超过上限**，会被存成文件；用 Python 解析，按段落文字前缀定位，不要靠记住的 index。
- **删掉一条批注锚定的全部文字，会把整串批注一起删掉。** 要保留合作者的批注，就保留锚定文字里的几个词，只改其余部分；要删的话，写入前告诉用户哪些批注会消失。
- **每次写入都带 `writeControl.requiredRevisionId`**，取自写入前最近一次读。合作者回复批注也会改 revision，被拒时重新读、重新算位置，再写。
- **保留样式**：只替换标签后面的正文，保留标题、加粗或斜体标签、列表和代码字体。插入的文字会继承前一个字符的样式（例如加粗标签），插入后对新文字重置 `bold,italic,foregroundColor,weightedFontFamily`，再按原样补上加粗、斜体、代码字体。列表项就地替换文字，不删段落，列表才不会断。
- **合作者写在文档里的内容分三种，处理方式不同**：
  - 修改意见（红字备注、批注）：按意见改完后，问用户是否删掉备注。
  - 合作者自己写的整段回复：保留不动，在我们那版上就地改，除非用户另有安排。
  - 合作者说要亲自重写的我们的段落：原文保留，新版写在后面，用醒目的标签分开（例如 【旧版】 / 【新版】），标法先问用户。
- **每次写完读回**：核对文字、标签样式、列表、表格位置、下一节标题紧接在后；需要时用 Drive 读确认批注还在。
