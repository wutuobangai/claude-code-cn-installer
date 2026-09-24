# © Happy AI · 教程截图（Windows 云端）：CC Switch / Cherry Studio 真软件界面
# 用法：python desktop_shots.py ccswitch 9222 | cherry 9223
# 原理：两个软件的界面都是网页内核（CC Switch=WebView2，Cherry Studio=Electron），
#       启动时打开调试端口，用 playwright 连上去点按钮、填占位值、截软件窗口里的画面。
#       连不上就退回整屏截图（<名>__fullscreen.png），不会卡住。
import sys

from common import FAKE_KEY, FAKE_NAME, FAKE_URL, OUT, dump_status, save, status, try_click, try_fill, wait_http


def fullscreen(name):
    try:
        from PIL import ImageGrab
        ImageGrab.grab().save(f"{OUT}/{name}__fullscreen.png")
        print("fullscreen saved", name, flush=True)
    except Exception as e:
        print("fullscreen failed", e, flush=True)


def connect(p, port, wait=90):
    if not wait_http(f"http://127.0.0.1:{port}/json/version", wait):
        return None, None
    b = p.chromium.connect_over_cdp(f"http://127.0.0.1:{port}", timeout=30000)
    pages = [pg for c in b.contexts for pg in c.pages if not pg.url.startswith("devtools://")]
    if not pages:
        return b, None
    page = pages[0]
    page.set_default_timeout(8000)
    page.wait_for_timeout(3000)
    return b, page


def ccswitch(port):
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b, page = connect(p, port)
        if not page:
            status("cc-switch-2-add", "fail", "调试端口没起来，只有整屏图")
            fullscreen("cc-switch")
            dump_status("ccswitch")
            return
        try:
            page.keyboard.press("Escape")  # 首次启动可能有欢迎/导入弹窗
            page.wait_for_timeout(800)
            save(page, "extra-cc-switch-main", True)
            add = try_click(page, ["添加供应商", "Add Provider", "Add provider", "新增供应商"])
            if not add:
                for sel in ('button[title*="添加"]', 'button[aria-label*="添加"]', 'button[title*="Add"]', 'button[aria-label*="Add"]'):
                    try:
                        page.locator(sel).first.click(timeout=3000)
                        add = True
                        break
                    except Exception:
                        pass
            page.wait_for_timeout(1500)
            try_click(page, ["自定义", "Custom"], timeout=2500)
            page.wait_for_timeout(1000)
            f1 = try_fill(page, ["供应商名称", "名称", "Name", "Provider Name"], FAKE_NAME)
            f2 = try_fill(page, ["API Key", "API 密钥", "API密钥"], FAKE_KEY)
            f3 = try_fill(page, ["请求地址", "API 请求地址", "Base URL", "API 地址", "Endpoint"], FAKE_URL)
            save(page, "cc-switch-2-add", add and (f1 or f2 or f3), note=f"add={add} fill={f1},{f2},{f3}")
            fullscreen("cc-switch-2-add")

            # 保存（只存在这台一次性虚拟机里）→ 回到列表：给第 3 步做替代图（托盘菜单截不到时用）
            sv = try_click(page, ["保存", "添加", "Save", "Add"], timeout=2500)
            page.wait_for_timeout(1500)
            page.keyboard.press("Escape")
            page.wait_for_timeout(800)
            save(page, "cc-switch-3-tray__替代-主界面列表", True, note=f"saved={sv}；Windows 托盘菜单在网页层截不到，这是列表里「启用」按钮的替代图")
        except Exception as e:
            status("cc-switch-2-add", "fail", repr(e)[:300])
            fullscreen("cc-switch")
        dump_status("ccswitch")


def cherry(port):
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b, page = connect(p, port, wait=180)  # 免安装版首次要先解压，慢
        if not page:
            status("cherry-2-key", "fail", "调试端口没起来，只有整屏图")
            fullscreen("cherry")
            dump_status("cherry")
            return
        try:
            page.keyboard.press("Escape")
            page.wait_for_timeout(800)
            save(page, "extra-cherry-main", True)

            # 设置 → 模型服务 → OpenAI
            st = try_click(page, ["设置", "Settings"])
            if not st:
                try:
                    page.locator('[href*="settings"]').first.click(timeout=3000)
                    st = True
                except Exception:
                    page.evaluate("() => { location.hash = '#/settings/provider' }")
            page.wait_for_timeout(1500)
            ms = try_click(page, ["模型服务", "Model Provider", "Model Service"])
            page.wait_for_timeout(1200)
            op = try_click(page, ["OpenAI"], roles=("button", "listitem", "option", "link"))
            page.wait_for_timeout(1200)
            fk = try_fill(page, ["API 密钥", "API Key", "API 密钥 "], FAKE_KEY)
            save(page, "cherry-2-key", ms and op and fk, note=f"settings={st} provider_page={ms} openai={op} key={fk}；没点获取模型列表（假 key）")

            # 回聊天页，点顶部模型名打开下拉
            home = try_click(page, ["助手", "Assistants", "聊天", "Chat"])
            if not home:
                page.evaluate("() => { location.hash = '#/' }")
            page.wait_for_timeout(1500)
            opened = False
            for sel in ('[class*="SelectModel"]', '[class*="model-select"]', '[class*="ModelSelect"]', 'header [class*="model"]', '.ant-select-selector'):
                try:
                    page.locator(sel).first.click(timeout=2500)
                    opened = True
                    break
                except Exception:
                    pass
            page.wait_for_timeout(1500)
            save(page, "cherry-3-model", opened, note=f"home={home} dropdown={opened}")
        except Exception as e:
            status("cherry-2-key", "fail", repr(e)[:300])
            fullscreen("cherry")
        dump_status("cherry")


if __name__ == "__main__":
    {"ccswitch": ccswitch, "cherry": cherry}[sys.argv[1]](int(sys.argv[2]))
