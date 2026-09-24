# © Happy AI · 教程截图公共小工具（云端一次性虚拟机上跑，不碰任何真实账号/key）
# 约定：
#   - 到位的截图存成  <data-shot 名>.png
#   - 没到位（按钮没找到/页面不对）也会存一张当时画面，文件名 <data-shot 名>__未到位.png，方便人工看图判断
#   - 每张图的结果写进 _status-<job>.json
import json
import os
import re
import time

# 截图里出现的一律是占位，不许出现真实 key / 邮箱
FAKE_NAME = "示例中转"
FAKE_KEY = "sk-你的key"
FAKE_URL = "https://你的中转地址.com"

OUT = os.environ.get("SHOTS_DIR", "shots")
os.makedirs(OUT, exist_ok=True)
_STATUS = {}


def status(shot, state, note=""):
    _STATUS[shot] = {"state": state, "note": note, "time": time.strftime("%H:%M:%S")}
    print(f"[{state}] {shot} {note}", flush=True)


def dump_status(job):
    with open(os.path.join(OUT, f"_status-{job}.json"), "w", encoding="utf-8") as f:
        json.dump(_STATUS, f, ensure_ascii=False, indent=2)


def save(page, shot, ok=True, full_page=False, note=""):
    name = shot if ok else f"{shot}__未到位"
    path = os.path.join(OUT, name + ".png")
    try:
        page.screenshot(path=path, full_page=full_page)
        status(shot, "ok" if ok else "partial", note)
    except Exception as e:  # 截图本身失败也不许中断后面的
        status(shot, "fail", f"screenshot error: {e!r}"[:300])
    return path


def rx(*words):
    return re.compile("|".join(re.escape(w) for w in words), re.I)


def try_click(page, words, timeout=4000, roles=("button", "tab", "link", "menuitem", "option")):
    """按「可见文字/无障碍名」依次找，找到第一个就点。返回是否点到。"""
    pat = rx(*words)
    for role in roles:
        try:
            loc = page.get_by_role(role, name=pat).first
            loc.wait_for(state="visible", timeout=timeout)
            loc.click(timeout=timeout)
            return True
        except Exception:
            pass
    for w in words:
        for loc in (page.get_by_title(w).first, page.get_by_text(w, exact=True).first, page.get_by_text(w).first):
            try:
                loc.wait_for(state="visible", timeout=timeout)
                loc.click(timeout=timeout)
                return True
            except Exception:
                pass
    return False


def try_fill(page, labels, value, timeout=3000):
    """按 label / placeholder 找输入框填占位值。返回是否填上。"""
    for w in labels:
        for loc in (page.get_by_label(w).first, page.get_by_placeholder(w).first):
            try:
                loc.wait_for(state="visible", timeout=timeout)
                loc.fill(value, timeout=timeout)
                return True
            except Exception:
                pass
    return False


def wait_http(url, seconds=60):
    import urllib.request
    end = time.time() + seconds
    while time.time() < end:
        try:
            urllib.request.urlopen(url, timeout=3).read()
            return True
        except Exception:
            time.sleep(2)
    return False
