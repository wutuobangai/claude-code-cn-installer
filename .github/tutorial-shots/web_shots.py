# © Happy AI · 教程截图（Linux 云端）：公开网页 / 浏览器扩展 / ccr ui
# 用法：python web_shots.py pages|ext|ccr
# 只截公开页面和我们在一次性虚拟机上自己装的东西；不登录任何账号，填的都是占位值。
import json
import os
import sys

from playwright.sync_api import sync_playwright

from common import FAKE_KEY, FAKE_NAME, FAKE_URL, OUT, dump_status, save, status, try_click, try_fill

VIEW = {"width": 1280, "height": 860}
CTX = dict(locale="zh-CN", viewport=VIEW, device_scale_factor=1, color_scheme="light")
ARGS = ["--lang=zh-CN"]


def goto(page, url, wait="networkidle", timeout=45000):
    try:
        page.goto(url, wait_until=wait, timeout=timeout)
    except Exception:
        page.goto(url, wait_until="domcontentloaded", timeout=timeout)
    page.wait_for_timeout(2500)


def center(page, selector):
    try:
        loc = page.locator(selector).first
        loc.wait_for(state="attached", timeout=15000)
        loc.evaluate("e => e.scrollIntoView({block: 'center'})")
        page.wait_for_timeout(800)
        return True
    except Exception:
        return False


# ---------------------------------------------------------------- 公开网页
def pages():
    with sync_playwright() as p:
        b = p.chromium.launch(args=ARGS)
        ctx = b.new_context(**CTX)
        page = ctx.new_page()

        # 1) CC Switch 官方下载页：把 .msi / .dmg 那几行放到画面中间
        for shot, url, sel in [
            ("cc-switch-1-releases", "https://github.com/farion1231/cc-switch/releases/latest", 'a[href$=".msi"]'),
            ("cherry-1-download__github", "https://github.com/CherryHQ/cherry-studio/releases/latest", 'a[href$="-win-x64-setup.exe"]'),
        ]:
            try:
                goto(page, url)
                ok = center(page, sel)
                save(page, shot, ok, note=url)
            except Exception as e:
                status(shot, "fail", repr(e)[:300])

        # 2) Cherry Studio 官网下载页（教程里的按钮就是指这里）
        try:
            goto(page, "https://www.cherry-ai.com/download")
            save(page, "cherry-1-download", True, note=page.url)
        except Exception as e:
            status("cherry-1-download", "fail", repr(e)[:300])

        # 3) Chrome 应用商店公开页（没登录也能看；「添加至 Chrome」按钮在首屏）
        for shot, url in [
            ("gpt-export-1-store", "https://chromewebstore.google.com/detail/tampermonkey/dhdgffkkebhmkfjojejmpbldmpobfkfo?hl=zh-CN"),
            ("all-api-hub-1-store", "https://chromewebstore.google.com/detail/lapnciffpekdengooeolaienkeoilfeo?hl=zh-CN"),
        ]:
            try:
                goto(page, url)
                txt = page.content()
                ok = ("添加至 Chrome" in txt) or ("Add to Chrome" in txt)
                save(page, shot, ok, note=url)
            except Exception as e:
                status(shot, "fail", repr(e)[:300])

        # 4) 附赠：GreasyFork 脚本页（教程第 2 步没有截图位，截了备用）
        try:
            goto(page, "https://greasyfork.org/zh-CN/scripts/456055-chatgpt-exporter")
            save(page, "extra-gpt-export-greasyfork", True)
        except Exception as e:
            status("extra-gpt-export-greasyfork", "fail", repr(e)[:300])
        b.close()
    dump_status("pages")


# ---------------------------------------------------------------- 浏览器扩展（解包加载，官方包）
def _ext_id(ctx, want_dir):
    """从已加载扩展的 service worker / 后台页地址里拿到扩展 ID。"""
    import time
    manifest = json.load(open(os.path.join(want_dir, "manifest.json"), encoding="utf-8-sig"))
    end = time.time() + 20
    while time.time() < end:
        # 每个浏览器实例只加载了一个扩展，所以第一个扩展地址就是它
        for w in list(ctx.service_workers) + list(ctx.background_pages):
            u = w.url
            if u.startswith("chrome-extension://"):
                return u.split("/")[2], manifest
        time.sleep(1)
    return None, manifest


def ext():
    tm = os.environ.get("TM_DIR", "ext/tampermonkey")
    ah = os.environ.get("AAH_DIR", "ext/all-api-hub")
    with sync_playwright() as p:
        # 2a) 油猴：只加载油猴，打开 chrome://extensions 详情页找「允许用户脚本」开关
        if os.path.isfile(os.path.join(tm, "manifest.json")):
            try:
                ctx = p.chromium.launch_persistent_context(
                    "/tmp/prof-tm", headless=False, args=ARGS + [f"--disable-extensions-except={tm}", f"--load-extension={tm}"], **CTX)
                page = ctx.new_page()
                eid, _ = _ext_id(ctx, tm)
                goto(page, f"chrome://extensions/?id={eid}" if eid else "chrome://extensions/", wait="load")
                ok = False
                for w in ("允许用户脚本", "Allow User Scripts", "Allow user scripts"):
                    try:
                        loc = page.get_by_text(w).first
                        loc.wait_for(state="visible", timeout=5000)
                        loc.evaluate("e => e.scrollIntoView({block: 'center'})")
                        ok = True
                        break
                    except Exception:
                        pass
                save(page, "gpt-export-2-toggle", ok, note=f"ext id={eid}")
                ctx.close()
            except Exception as e:
                status("gpt-export-2-toggle", "fail", repr(e)[:300])
        else:
            status("gpt-export-2-toggle", "fail", "油猴安装包没下载下来")

        # 2b) All API Hub：打开它的弹出页（当普通标签页开），点「新增账号」、再看「密钥管理」
        if os.path.isfile(os.path.join(ah, "manifest.json")):
            try:
                ctx = p.chromium.launch_persistent_context(
                    "/tmp/prof-aah", headless=False, args=ARGS + [f"--disable-extensions-except={ah}", f"--load-extension={ah}"], **CTX)
                page = ctx.new_page()
                eid, mf = _ext_id(ctx, ah)
                popup = ((mf.get("action") or mf.get("browser_action") or {}).get("default_popup") or "popup.html")
                if eid:
                    page.set_viewport_size({"width": 420, "height": 640})  # 弹出窗大小
                    goto(page, f"chrome-extension://{eid}/{popup}", wait="load")
                    save(page, "extra-all-api-hub-popup", True)
                    clicked = try_click(page, ["新增账号", "添加账号", "Add account", "Add Account"])
                    page.wait_for_timeout(1500)
                    if clicked:
                        try_fill(page, ["站点地址", "网址", "站点 URL", "URL", "https://"], FAKE_URL)
                    save(page, "all-api-hub-2-add", clicked, note="占位网址，未点自动识别（没有真账号）")
                    page.keyboard.press("Escape")
                    page.wait_for_timeout(800)
                    goto(page, f"chrome-extension://{eid}/{popup}", wait="load")
                    k = try_click(page, ["密钥管理", "Key Management", "Keys"])
                    page.wait_for_timeout(1500)
                    # 没有真账号，列表必然是空的 → 永远记成未到位，由人工决定用不用
                    save(page, "all-api-hub-3-keys", False, note=f"点到密钥管理={k}；无真实账号，列表为空")
                else:
                    status("all-api-hub-2-add", "fail", "拿不到扩展 ID")
                ctx.close()
            except Exception as e:
                status("all-api-hub-2-add", "fail", repr(e)[:300])
        else:
            status("all-api-hub-2-add", "fail", "All API Hub 安装包没下载下来")
    dump_status("ext")


# ---------------------------------------------------------------- claude-code-router 管理页
def ccr():
    url = os.environ.get("CCR_URL", "").strip() or "http://127.0.0.1:3458/"
    with sync_playwright() as p:
        b = p.chromium.launch(args=ARGS)
        ctx = b.new_context(**CTX)
        page = ctx.new_page()
        try:
            goto(page, url, wait="load")
            page.evaluate("() => { try { localStorage.setItem('ccr.ui.language', 'zh') } catch (e) {} }")
            page.reload(wait_until="load")
            page.wait_for_timeout(2500)
            save(page, "extra-ccr-home", True)

            # 供应商 → 添加供应商 → 选自定义 → 填三样占位
            nav = try_click(page, ["供应商", "Providers"])
            page.wait_for_timeout(1200)
            add = try_click(page, ["添加供应商", "Add provider", "Add Provider", "添加", "Add"])
            page.wait_for_timeout(1500)
            try_click(page, ["其他", "自定义", "Custom", "Other"], timeout=2500)
            page.wait_for_timeout(1000)
            f1 = try_fill(page, ["名称", "供应商名称", "Name"], FAKE_NAME)
            f2 = try_fill(page, ["API 地址", "API地址", "Base URL", "API URL", "请求地址"], FAKE_URL + "/v1")
            f3 = try_fill(page, ["API 密钥", "API Key", "密钥"], FAKE_KEY)
            ok = nav and add and (f1 or f2 or f3)
            save(page, "ccr-2-provider", ok, note=f"nav={nav} add={add} fill={f1},{f2},{f3}；没点检测连通性（假地址）")

            # 保存供应商（假地址，只存在这台一次性虚拟机里），再去 Agent 配置档案 → 添加配置 → Claude Code
            saved = try_click(page, ["保存", "Save", "创建", "Create", "添加", "Add"], timeout=2500)
            page.wait_for_timeout(1500)
            page.keyboard.press("Escape")
            n2 = try_click(page, ["Agent 配置档案", "Agent 配置", "Agent profiles", "Agent profile", "Profiles"])
            page.wait_for_timeout(1200)
            a2 = try_click(page, ["添加配置", "Add Profile", "Add profile"])
            page.wait_for_timeout(1200)
            try_click(page, ["Claude Code"], timeout=2500)
            try_fill(page, ["配置名称", "名称", "Name"], "claude")
            s2 = try_click(page, ["保存", "Save", "创建", "Create"], timeout=2500)
            page.wait_for_timeout(1500)
            page.keyboard.press("Escape")
            page.wait_for_timeout(800)
            txt = page.content()
            ok3 = n2 and s2 and ("claude" in txt)
            save(page, "ccr-3-agent", ok3, note=f"saved_provider={saved} nav={n2} add={a2} save={s2}")
        except Exception as e:
            status("ccr-2-provider", "fail", repr(e)[:300])
        b.close()
    dump_status("ccr")


if __name__ == "__main__":
    {"pages": pages, "ext": ext, "ccr": ccr}[sys.argv[1]]()
