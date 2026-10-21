---
name: blocked
description: FastShip のルーティン (課題分析・リファインメント・実装・レビュー) の共通ルール。開始時に多重起動を防ぎ、前回の質問と回答を読んで再開する。Claude だけで判断できないときは、Issue / PR に質問をコメントし、claude:blocked を付けて人間に返す。ルーティンの最初と、止めるときに使う。
---

# ❓ 質問・差し戻し (claude:blocked)

ルーティンは「1. 始める」から始めてください。Claude だけで判断できないことがあれば、推測で進めず「2. 止める」で人間に返してください。ルーティンのチャットは誰も見ていないため、質問は必ず Issue / PR にコメントします。

| ルーティン | 進行中ラベル | 対象 | 再開のトリガー |
|:--|:--|:--|:--|
| 課題分析 | `claude:analysis` | Issue | `issues.labeled` |
| リファインメント | `claude:refine` | Issue | `issues.labeled` |
| 実装 | `claude:implement` | Sub Issue (1 PR で済むときは Issue)。PR を作った後は PR | `issues.labeled` / `pull_request.labeled` |
| レビュー | `claude:under-review` | PR | `pull_request.labeled` |

どちらの手順も `${CLAUDE_PLUGIN_ROOT}/scripts/blocked.sh` で行います。GitHub は `gh api` (REST) で操作します。

## 1. 始める
トリガーになった Issue / PR の番号と、ルーティンの進行中ラベルで実行してください。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/blocked.sh" start 123 claude:implement
```

 - `STOP` と出たら、何もせずに終えてください。進行中ラベルが無いか、別のセッションが着手済みです。ルーティンは、進行中ラベルが付いた Issue / PR に別のラベルが付いたときにも起動するためです。
 - `CONTINUE` と出たら続けてください。着手コメントを投稿し、残っていた `claude:blocked` を外しています。
 - 続けて「前回の質問と回答」が出たら再開です。回答と Issue / PR の本文を読み、止めたところから続けてください。回答が足りなければ、もう一度「2. 止める」で聞いてください。

## 2. 止める
1. 作業中の変更があれば、コミットしてブランチに push してください。再開したセッションはそこから続けます。
2. 質問を下の形式でファイルに書いてください。
3. 次を実行してください。質問をコメントし、進行中ラベルを外してから `claude:blocked` を付けます。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/blocked.sh" stop 123 claude:implement /tmp/question.md
```

4. 以降は何もせずに終えてください。`claude:blocked` が付いている間は、PR のイベントで起こされても対応しないでください。

 - 実装で PR を作った後は、PR の番号で実行してください。Sub Issue の `claude:implement` は外しません。リファインメントは、このラベルが付いた Sub Issue が閉じたときに後続に着手するためです。Sub Issue に別のラベルが付いて実装ルーティンが起動しても、着手コメントがあるので「1. 始める」で止まります。
 - ラベルを手で操作するときも、進行中ラベルを先に外してください。付いたまま `claude:blocked` を付けると、ルーティンがもう一度起動します。

```markdown
## ❓ 質問

<何を判断できずに止めたか>

1. <質問>
   - A (推奨): <案と理由>
   - B: <案>

<作業ブランチ / PR があれば書く>

**再開するには**: コメントで回答し、`claude:blocked` を外して `<進行中ラベル>` を付けてください。
```

 - 開発者がコメント 1 つで答えられるように、選択肢と推奨を付けてください。
