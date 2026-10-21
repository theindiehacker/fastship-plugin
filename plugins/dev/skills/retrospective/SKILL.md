---
name: retrospective
description: FastShip の ♻️ 振り返り。前回の振り返りから今までにマージした PR・クローズした Issue・claude:blocked の件数・成功指標のコメント (⑫) を集めて振り返り、結果を振り返り Issue (claude:retrospective) に残して閉じる。改善点は重複を除いて最大 3 件起票し、claude:analysis を付けて課題分析を始める。振り返りルーティンから週 1 回使う。使い方: /dev:retrospective
---

# ♻️ 振り返り

前回の振り返りから今までの開発を振り返り、結果を振り返り Issue に残してください。改善点は Issue に起票し、課題分析を始めます。開発者は振り返り Issue を読み、改善 Issue を ④ で承認するかを決めます。

GitHub は `gh api` (REST) で操作します。claude.ai/code では `search/issues` が 403 になるため、`repos/{owner}/{repo}/...` だけを使います。コマンドの `<開始時刻>` は 1 で決めた時刻 (例: `2026-10-14T00:00:00Z`) に、`123` は振り返り Issue の番号に置き換えてください。

## 1. 期間を決める
過去の振り返り Issue を新しい順に取得してください。

```bash
gh api "repos/{owner}/{repo}/issues?labels=claude:retrospective&state=all&per_page=4" --jq '.[] | "### #\(.number) \(.created_at) \(.title)\n\(.body)\n"'
date -u -d '7 days ago' +%FT%TZ
```

 - 期間は、最新の振り返り Issue の `created_at` から今までです。無ければ直近 7 日です。
 - 最新の振り返り Issue が 24 時間以内なら、何もせずに終えてください。同じ週に 2 回振り返らないためです。
 - 本文から、前回の数字と、起票した改善 Issue を控えてください。

## 2. 集める
期間に閉じた Issue / PR と、期間に書かれたコメントを読んでください。

```bash
gh api --paginate "repos/{owner}/{repo}/issues?state=closed&since=<開始時刻>&per_page=100" --jq '.[]
  | select(.closed_at >= "<開始時刻>" and ([.labels[].name] | index("claude:retrospective") | not))
  | if .pull_request then "PR #\(.number) merged=\(.pull_request.merged_at // "-") created=\(.created_at) \(.title)"
    else "Issue #\(.number) \(.state_reason) 成功指標=\(.body // "" | contains("## 成功指標")) \(.title)" end'
gh api --paginate "repos/{owner}/{repo}/issues/comments?since=<開始時刻>&per_page=100" --jq '.[]
  | select(.created_at >= "<開始時刻>")
  | select((.body | startswith("<!-- fastship:blocked -->"))
      or ((.html_url | contains("/issues/")) and (.body | startswith("<!-- fastship:") | not)))
  | "### \(.html_url) (\(.created_at))\n\(.body)\n"'
```

 - **マージした PR**: `merged=` が日時の PR です。`merged=-` は閉じただけなので数えません。
 - **クローズした Issue**: `completed` の Issue です。`not_planned` は数えません。
 - **`claude:blocked`**: `<!-- fastship:blocked -->` で始まるコメントです。件数と、何を判断できずに止めたかを読んでください。
 - **成功指標 (⑫)**: 残りの Issue のコメントから、成功指標の結果を報告したものを探してください。開発者と Claude が同じアカウントで書くことがあるため、投稿者ではなく内容で見分けます。見つけたら、その Issue の本文の 成功指標 と照らして、目標を満たしたかを確かめてください。
 - **確認待ち**: 閉じた Issue のうち `成功指標=true` (本文に 成功指標 の欄がある) ものは、本文を読み、確認する時期を控えてください。開発者に ⑫ を促すためです。欄が空なら飛ばしてください。
 - 理由を確かめたいときは、PR / Issue の本文やコメントも読んでください。推測で書かないためです。

## 3. 振り返る
開発者が数分で読めるよう、短く書いてください。

 - **数字**: マージした PR・クローズした Issue・`claude:blocked`・PR の作成からマージまでの時間 (中央値) を、前回と比べてください。
 - **Keep**: 続けたいことを 1〜2 行で書いてください。
 - **Problem**: 困ったこと・遅れたことを、根拠の #番号 を付けて 1〜3 行で書いてください。`claude:blocked` の質問は、Issue の書き方やリポジトリのドキュメントで防げたかを見てください。成功指標が未達なら、それも Problem です。
 - **Try**: Problem から、このリポジトリで直せる改善を最大 3 件選び、5.2 で起票します。根拠の無い一般論 (「テストを増やす」など) は選ばないでください。無ければ 0 件で構いません。
 - FastShip プラグイン (スキル・テンプレート) の改善は、このリポジトリに起票できません。Problem に「FastShip プラグイン:」と付けて書くだけにしてください。

## 4. 重複を確かめる
open の Issue と、1 で控えた改善 Issue を読み、Try と同じ改善が無いか確かめてください。

```bash
gh api --paginate "repos/{owner}/{repo}/issues?state=open&per_page=100" --jq '.[] | select(.pull_request | not) | "#\(.number) \(.title)"'
gh api "repos/{owner}/{repo}/issues/<改善 Issue の番号>" --jq '"#\(.number) \(.state) \(.state_reason) \(.title)"'
```

 - 同じ改善が open なら、起票せずに、今週の根拠をその Issue にコメントしてください (5.2)。
 - 同じ改善が closed なら、起票しないでください。開発者が見送ったか、もう直しています。また起きていれば、Problem に「#番号 の後も起きている」と書いてください。

## 5. 残す
### 5.1 振り返り Issue を起票する
下の形式で `/tmp/retro.md` を書き、`claude:retrospective` を付けて起票してください。タイトルは `♻️ 振り返り 10/14〜10/20` の形式で、期間の初日〜最終日 (JST) です。

```bash
jq -n --arg title "♻️ 振り返り <期間>" --rawfile body /tmp/retro.md \
    '{title:$title, body:$body, labels:["claude:retrospective"]}' \
  | gh api --method POST "repos/{owner}/{repo}/issues" --input - --jq .number
```

```markdown
<!-- fastship:retrospective -->
## 📊 数字
| 項目 | 今回 | 前回 |
|:--|--:|--:|
| マージした PR | <件数> | <件数> |
| クローズした Issue | <件数> | <件数> |
| `claude:blocked` | <件数> | <件数> |
| PR 作成〜マージ (中央値) | <時間> | <時間> |

## 🎯 成功指標 (⑫)
- #<番号> <指標>: <結果> (<達成 / 未達>)
- 確認待ち: #<番号> (<確認する時期>)
<報告も確認待ちも無ければ「なし」>

## 🔍 気づき
- Keep: <続けたいこと>
- Problem: <困ったこと> (#<番号>)

## ♻️ 改善 Issue
<5.3 で書く>
```

 - 前回が無いときは、前回の列を `-` にしてください。
 - 動きが無い週も、0 件のまま残してください。ルーティンが動いていることを開発者が確かめられます。

### 5.2 改善 Issue を起票する
Try ごとに、`${CLAUDE_PLUGIN_ROOT}/skills/issue/backlog.md` の欄に沿って `/tmp/improve.md` を書き、`claude:analysis` を付けて起票してください。課題分析が始まります。

 - 先頭の YAML frontmatter は含めないでください。HTML コメントは残し、その下に書いてください。
 - 書くのは 背景 と 参考資料 です。課題 / 解決策 / 成功指標 は課題分析が書くので、空のまま残してください。
 - 背景: 振り返りで分かったこと (事実と根拠の #番号) と、どうしたいか
 - 参考資料: `- 振り返り #123` と、根拠の Issue / PR

```bash
jq -n --arg title "<タイトル>" --rawfile body /tmp/improve.md \
    '{title:$title, body:$body, labels:["claude:analysis"]}' \
  | gh api --method POST "repos/{owner}/{repo}/issues" --input - --jq .number
```

4 で同じ改善が open だったものは、起票せずに `♻️ 振り返り #123 でも見つかりました: <根拠>` をコメントしてください。

```bash
jq -n --rawfile body /tmp/evidence.md '{body:$body}' \
  | gh api --method POST "repos/{owner}/{repo}/issues/<番号>/comments" --input - > /dev/null
```

### 5.3 振り返り Issue を閉じる
`/tmp/retro.md` の ♻️ 改善 Issue を下の形式で書き、本文を更新して閉じてください。閉じておくと、open の Issue の一覧に残りません。

```markdown
- #<番号> <タイトル> (新規)
- #<番号> <タイトル> (根拠を追記)
<無ければ「なし」>
```

```bash
jq -n --rawfile body /tmp/retro.md '{body:$body, state:"closed", state_reason:"completed"}' \
  | gh api --method PATCH "repos/{owner}/{repo}/issues/123" --input - > /dev/null
```
