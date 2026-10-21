---
name: retrospective
description: FastShip の ♻️ 振り返り。前回の振り返りから今までにマージした PR・クローズした Issue・claude:blocked の件数・成功指標 (⑫) の報告と確認待ちを集めて振り返り (確認待ちの親 Issue の claude:shipped を合わせ直す)、結果を振り返り Issue (claude:retrospective) に残して閉じる。改善点は重複を除いて最大 3 件起票し、claude:analysis を付けて課題分析を始める。振り返りルーティンから週 1 回使う。使い方: /dev:retrospective
---

# ♻️ 振り返り

前回の振り返りから今までの開発を振り返り、結果を振り返り Issue に残してください。改善点は Issue に起票し、課題分析を始めます。開発者は振り返り Issue を読み、改善 Issue を ④ で承認するかを決めます。

GitHub は `gh api` (REST) で操作します。claude.ai/code では `search/issues` が 403 になるため、`repos/{owner}/{repo}/...` だけを使います。コマンドの `<since>` / `<until>` は 1 で出た時刻に、`123` は振り返り Issue の番号に置き換えてください。

## 1. 始める
次を実行してください。振り返り Issue を先に起票し、期間を決めます。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/retrospective.sh" start
```

 - `STOP` と出たら、何もせずに終えてください。別のセッションが振り返っているか、前回から 6 日経っていないなどです。理由は同じ行に出ます。
 - `CONTINUE` と出たら続けてください。振り返り Issue の番号と期間 (`since` 以上 `until` 未満) が出ます。続けて出る前回までの振り返りから、前回の数字・確認待ち・起票した改善 Issue を控えてください。
 - `(再開)` と付いていたら、前のセッションが途中で止まっています。途中の本文の ♻️ 改善 Issue にある Issue は起票済みなので、起票し直さないでください。

## 2. 集める
期間に閉じた Issue / PR と、`claude:blocked` の質問を読んでください。

```bash
gh api --paginate "repos/{owner}/{repo}/issues?state=closed&since=<since>&per_page=100" --jq '.[]
  | select(.closed_at >= "<since>" and .closed_at < "<until>" and ([.labels[].name] | index("claude:retrospective") | not))
  | if .pull_request then "PR #\(.number) merged=\(.pull_request.merged_at // "-") created=\(.created_at) \(.title)"
    else "Issue #\(.number) \(.state_reason) subs=\(.sub_issues_summary.total // 0) \(.title)" end'
gh api --paginate "repos/{owner}/{repo}/issues/comments?since=<since>&per_page=100" --jq '.[]
  | select(.created_at >= "<since>" and .created_at < "<until>" and (.body | startswith("<!-- fastship:blocked -->")))
  | "### \(.html_url) (\(.created_at))\n\(.body)\n"'
```

 - **マージした PR**: `merged=` が日時の PR です。`merged=-` は閉じただけなので数えません。
 - **クローズした Issue**: `completed` の Issue です。`not_planned` は数えません。
 - **`claude:blocked`**: 2 つ目の出力です。件数と、何を判断できずに止めたかを読んでください。
 - 理由を確かめたいときは、PR / Issue の本文やコメントも読んでください。推測で書かないためです。

### 成功指標 (⑫)
親 Issue は自動では閉じないため、Sub Issue がすべて閉じた親 Issue を、成功指標を確かめる対象にします。

 - open の親 Issue で、Sub Issue がすべて閉じたもの・`claude:shipped` が付いたもの (下の 1 つ目のコマンド)。それぞれ 2 つ目のコマンドで `claude:shipped` を合わせ、`SHIPPED` と出たものだけを対象にしてください。リファインメントが起動しなかったとき (`claude:implement` の無い Sub Issue を手で閉じた、Sub Issue を開き直したなど) の付け漏れ・外し漏れも、ここで直ります
 - 1 つ目の出力で `completed` かつ `subs=` が 1 以上の Issue (期間に閉じた親 Issue)

```bash
gh api --paginate "repos/{owner}/{repo}/issues?state=open&per_page=100" --jq '.[]
  | select((.pull_request | not) and (([.labels[].name] | index("claude:shipped")) or (.sub_issues_summary.total > 0 and .sub_issues_summary.completed == .sub_issues_summary.total)))
  | "#\(.number) \(.title)"'
bash "${CLAUDE_PLUGIN_ROOT}/scripts/shipped.sh" sync <番号>
gh api "repos/{owner}/{repo}/issues/<番号>" --jq .body
gh api --paginate "repos/{owner}/{repo}/issues/<番号>/comments" --jq '.[]
  | select(.body | startswith("<!-- fastship:") | not) | "### \(.created_at)\n\(.body)\n"'
```

対象ごとに、本文の 成功指標 とコメントを読んでください。本文の 成功指標 が空なら飛ばしてください。

 - 期間内のコメントに結果の報告があれば、目標を満たしたかを確かめ、🎯 の結果に書いてください。
 - 報告が無い指標は、確認待ちです。確認する時期が過ぎていれば ⏰ を付けてください。
 - 期間より前に報告済みの指標は、どちらにも書きません。
 - 開発者と Claude が同じアカウントで書くことがあるため、報告かどうかは投稿者ではなく内容で見分けてください。

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
### 5.1 振り返り Issue を書く
下の形式で `/tmp/retro.md` を書き、振り返り Issue の本文を更新してください。先頭のマーカー行は、1 で起票した本文のまま残してください。次回の期間に使います。

```bash
jq -n --rawfile body /tmp/retro.md '{body:$body}' \
  | gh api --method PATCH "repos/{owner}/{repo}/issues/123" --input - > /dev/null
```

```markdown
<!-- fastship:retrospective since=<since> until=<until> -->
## 📊 数字
| 項目 | 今回 | 前回 |
|:--|--:|--:|
| マージした PR | <件数> | <件数> |
| クローズした Issue | <件数> | <件数> |
| `claude:blocked` | <件数> | <件数> |
| PR 作成〜マージ (中央値) | <時間> | <時間> |

## 🎯 成功指標 (⑫)
- #<番号> <指標>: <結果> (<達成 / 未達>)
- 確認待ち: #<番号> <指標> (<確認する時期>)
<結果も確認待ちも無ければ「なし」。確認待ちがあれば「報告したら Issue を閉じてください。確認待ちから外れます」を添える>

## 🔍 気づき
- Keep: <続けたいこと>
- Problem: <困ったこと> (#<番号>)

## ♻️ 改善 Issue
- なし
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
  | gh api --method POST "repos/{owner}/{repo}/issues" --input - --jq '.number, .labels[].name'
```

出力に `claude:analysis` が無ければ、push 権限が無く黙って外れています。下の行の末尾に「`claude:analysis` を手で付けてください」と書いてください。

4 で同じ改善が open だったものは、起票せずに、下の形式で Issue ごとに `/tmp/evidence.md` を書いてコメントしてください。先頭のマーカーは、ほかのスキルが開発者のコメントと見分けるために付けます。

```markdown
<!-- fastship:retrospective -->
♻️ 振り返り #123 でも見つかりました。

- <今週の根拠 (事実と #番号)>
```

```bash
jq -n --rawfile body /tmp/evidence.md '{body:$body}' \
  | gh api --method POST "repos/{owner}/{repo}/issues/<番号>/comments" --input - > /dev/null
```

1 件ごとに、`/tmp/retro.md` の ♻️ 改善 Issue に下の行を足し (`- なし` は消す)、5.1 のコマンドで本文を更新してください。途中で止まっても、再開したセッションが起票済みの Issue を見分けられます。

```markdown
- #<番号> <タイトル> (新規)
- #<番号> <タイトル> (根拠を追記)
```

### 5.3 振り返り Issue を閉じる
閉じておくと、open の Issue の一覧に残らず、次回はこの Issue の `until` から始まります。

```bash
gh api --method PATCH "repos/{owner}/{repo}/issues/123" -f state=closed -f state_reason=completed > /dev/null
```
