# Tailscale Desktop for Omarchy

[English](README.md)

[Omarchy](https://omarchy.org/) のバーに置く Tailscale ウィジェットです。Windows 版・Mac 版の Tailscale のメニューでできることを、同じ並びで使えます。

> Omarchy 標準の `omarchy.tailscale` ウィジェットを元にした、コミュニティ製のプラグインです。Tailscale・Omarchy とは関係ありません。

## パネルの中身

1. **接続** — オン/オフのスイッチ（バーのアイコンを右クリックしても同じ）
2. **アカウント** — アカウントの切り替え、追加、ログアウト（2回押し）、管理コンソール
3. **このデバイス** — 名前、Tailscale の IP、MagicDNS 名、キーの有効期限。どれもコピーできます
4. **ネットワーク上のデバイス** — 自分のデバイス／タグ付きデバイス／他のユーザーに分けて表示。オフラインの端末も最後に見えた時刻つきで薄く出します。名前・DNS 名・IPv4・IPv6 のコピーと、Taildrop でのファイル送信ができます
5. **出口ノード** — なし、おすすめ（`auto:any`。Tailscale の提案先を表示）、tailnet の出口ノード、使えるときは Mullvad の地域。さらに「ローカルネットワークへのアクセスを許可」「出口ノードとして動作」
6. **設定** — Tailscale の DNS 設定を使う、Tailscale のサブネットを使う、着信接続を許可
7. **情報** — Tailscale のバージョン（アップデートがあれば表示）と、`tailscale bugreport` の ID をコピーする「バグレポート」

Windows 版だけの項目（Run unattended、Launch at startup）は入れていません。Linux では `tailscaled` が systemd のサービスとして動くためです。

## インストール

```bash
omarchy plugin add https://github.com/MoomA-0750/omarchy-tailscale-desktop.git --enable
omarchy plugin disable omarchy.tailscale   # 標準のウィジェットを隠す（tailscaled は止まりません）
```

### パネルから設定を変えられるようにする

オン/オフや設定の変更には、自分のユーザーが Tailscale の「オペレーター」になっている必要があります。パネルの **Authorize Tailscale operator** を1回押してください（`pkexec tailscale set --operator=$USER` が走ります）。ターミナルからなら次のとおりです。

```bash
sudo tailscale set --operator=$USER
```

## キー操作

| キー | 動作 |
| --- | --- |
| `j` / `k`、矢印 | カーソルを動かす |
| `Enter` / `Space` | その行を実行 |
| `t` | Tailscale のオン/オフ |
| `c` / `n` / `d` | 選んだ端末の IP / 名前 / DNS 名をコピー |
| `s` | 選んだ端末にファイルを送る |
| `/` | 端末を検索（台数が多いとき） |
| `Esc` | 閉じる |

## 必要なもの

- Quickshell ベースの `omarchy-shell` が入った Omarchy
- `PATH` 上の `tailscale`、コピー用の `wl-copy`

## 言語

Setup > Language で選んだ言語に従います。このプラグインで足した文言は英語と日本語を同梱しています（`i18n/`）。それ以外は Omarchy 本体の翻訳を使います。

## ライセンス

MIT。[LICENSE](LICENSE) を参照してください。
