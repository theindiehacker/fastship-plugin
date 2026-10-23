---
name: issue
description: ビジネス職・PM・デザイナーなど非エンジニアが、エンジニアに依頼したい機能要望や改善要望を GitHub Issues に起票するのを支援する。やりたいことの背景 (困りごと・要望) と参考資料を対話的にヒアリングし、claude:analysis を付けて起票し、課題分析を始める。別々に役に立つ目的が複数あれば、分けて起票する。claude.ai からも使える。使い方: /dev:issue [owner/repo] {タスクページのURLや作成したい内容のプロンプト}
argument-hint: "[owner/repo] {URL や作成したい内容}"
model: sonnet
---

# 📝 起票

要件や仕様をヒアリングし、エンジニアが作業を開始できるように Issue を作成してください。起票時に `claude:analysis` を付けると、③ 課題分析が始まります。

## 1. ヒアリング
背景 と 参考資料 をヒアリングしてください。

やりたいことに、別々に役に立つ目的 (片方だけ作っても使える) が 2 つ以上あれば、目的ごとに Issue を分けて起票することを提案し、ユーザーに確認してください。1 つの Issue が大きいと、課題分析・承認・最後のレビューで読む量が増えるためです。

 - 例: 「会員登録したい」と「請求書を PDF で出したい」は分けます。「登録・ログイン・ログアウト」のように、揃って初めて使えるものは分けません。
 - 迷ったら分けずに 1 つにしてください。③ 課題分析が、大きければ分けます。

## 2. 起票先を決める
1. ユーザーがリポジトリ (`owner/repo` や URL) を指定していれば、それを使ってください。
2. 指定が無ければ、使えるリポジトリから選んでください。1 つならそれを使い、複数あれば内容に合うものを推奨してユーザーに聞いてください。
   - Claude Code: 作業中のリポジトリ
   - claude.ai: GitHub コネクタで見えるリポジトリ
3. 起票先に `claude:analysis` ラベルがあるか確認してください (`gh api "repos/<owner>/<repo>/labels/claude:analysis"`)。無ければ `/dev:setup` が済んでいないので、そう伝えて止めてください。

## 3. 本文を書く
Issue ごとに、SKILL.md と同じフォルダの `backlog.md` に沿って書いてください。③ 課題分析がこの欄に追記するため、起票先リポジトリのテンプレートではなく、常にこれを使います。

 - 先頭の YAML frontmatter (`---` で囲んだ部分) は本文に含めないでください。
 - 起票時に書くのは 背景 と 参考資料 です。課題 / 解決策 / 要件 は ③ 課題分析が書くので、空のまま残してください。
 - 分けて起票するときは、1 つずつ起票し、2 つ目からは 参考資料 に、先に起票した Issue の番号を書いてください。

## 4. 起票する
起票先・タイトル・本文を見せ、ユーザーの確認を取ってから起票してください。`claude:analysis` は起票と同時に付けます。

 - GitHub の MCP ツール (claude.ai の GitHub コネクタなど) があれば、それを使ってください。
 - 無ければ `gh api` (REST) を使ってください。`gh issue create` は GraphQL を使うため、claude.ai/code では 403 になります。

```bash
jq -n --arg title "<タイトル>" --rawfile body /tmp/issue_body.md \
    '{title:$title, body:$body, labels:["claude:analysis"]}' \
  | gh api --method POST "repos/<owner>/<repo>/issues" --input - --jq '.html_url, .labels[].name'
```

 - どちらも無ければ本文を渡し、GitHub の UI で起票して `claude:analysis` を付けるよう案内してください。

起票したら Issue の URL を伝えてください。`claude:analysis` が付いていなければ (push 権限が無いと黙って外れます)、手動で付けるよう伝えてください。
