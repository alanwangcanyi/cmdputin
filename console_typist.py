#!/usr/bin/env python3
"""Send a single command as keyboard input to a selected macOS window."""

import subprocess
import tkinter as tk
from tkinter import messagebox, ttk


def applescript_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def run_applescript(script: str) -> str:
    result = subprocess.run(
        ["/usr/bin/osascript", "-e", script], check=True, capture_output=True, text=True
    )
    return result.stdout.strip()


class CMDPutin:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.windows: list[tuple[str, str]] = []
        self.root.title("CMDPutin")
        self.root.geometry("580x300")
        self.root.minsize(500, 280)
        self.root.configure(bg="#ffffff", padx=22, pady=18)
        self.root.attributes("-topmost", False)

        header = tk.Frame(root, bg="#ffffff")
        header.pack(fill="x")
        self.draw_icon(header, "logo", 34).pack(side="left", padx=(0, 10))
        tk.Label(header, text="CMDPutin", font=("Helvetica", 16, "bold"), bg="#ffffff", fg="#111111").pack(side="left")
        self.pin_var = tk.BooleanVar(value=False)
        pin = tk.Frame(header, bg="#ffffff", cursor="hand2")
        pin.pack(side="right")
        self.draw_icon(pin, "pin").pack(side="left")
        self.pin_label = tk.Label(pin, text="置顶", font=("Helvetica", 10), bg="#ffffff", fg="#111111")
        self.pin_label.pack(side="left", padx=(5, 0))
        for widget in (pin, *pin.winfo_children()):
            widget.bind("<Button-1>", lambda _event: self.toggle_topmost())

        tk.Label(root, text="命令", font=("Helvetica", 11, "bold"), bg="#ffffff", fg="#222222").pack(anchor="w", pady=(24, 6))
        self.command = tk.Entry(root, font=("Menlo", 13), relief="solid", bd=1, highlightthickness=0)
        self.command.pack(fill="x", ipady=9)
        self.command.bind("<Return>", lambda _event: "break")

        window_row = tk.Frame(root, bg="#ffffff")
        window_row.pack(fill="x", pady=(18, 0))
        tk.Label(window_row, text="目标窗口", font=("Helvetica", 11, "bold"), bg="#ffffff", fg="#222222").pack(side="left")
        self.window_menu = ttk.Combobox(window_row, state="readonly")
        self.window_menu.pack(side="left", fill="x", expand=True, padx=(12, 8), ipady=4)
        refresh = self.draw_icon(window_row, "refresh")
        refresh.configure(cursor="hand2")
        refresh.pack(side="right", padx=8, pady=5)
        refresh.bind("<Button-1>", lambda _event: self.refresh_windows())

        footer = tk.Frame(root, bg="#ffffff")
        footer.pack(fill="x", side="bottom", pady=(18, 0))
        self.status = tk.StringVar(value="选择窗口后输入；不会自动按回车。")
        tk.Label(footer, textvariable=self.status, font=("Helvetica", 10), bg="#ffffff", fg="#666666", anchor="w").pack(side="left", fill="x", expand=True)
        send = tk.Frame(footer, bg="#ffffff", cursor="hand2", padx=12, pady=7, highlightthickness=1, highlightbackground="#111111")
        send.pack(side="right")
        self.draw_icon(send, "send").pack(side="left")
        tk.Label(send, text="输入", font=("Helvetica", 10, "bold"), bg="#ffffff", fg="#111111").pack(side="left", padx=(7, 0))
        for widget in (send, *send.winfo_children()):
            widget.bind("<Button-1>", lambda _event: self.send_command())

        self.refresh_windows()

    def draw_icon(self, parent: tk.Widget, name: str, size: int = 18, bg: str = "#ffffff", color: str = "#111111") -> tk.Canvas:
        canvas = tk.Canvas(parent, width=size, height=size, bg=bg, highlightthickness=0, bd=0)
        s = size / 18
        line = dict(fill=color, width=max(1, 1.7 * s), capstyle=tk.ROUND, joinstyle=tk.ROUND)
        if name == "logo":
            canvas.create_arc(2*s, 2*s, 16*s, 16*s, start=45, extent=270, style=tk.ARC, outline=color, width=2.3*s)
        elif name == "pin":
            canvas.create_line(6*s, 3*s, 12*s, 3*s, **line)
            canvas.create_line(7*s, 3*s, 7*s, 8*s, **line)
            canvas.create_line(11*s, 3*s, 11*s, 8*s, **line)
            canvas.create_line(5*s, 8*s, 13*s, 8*s, **line)
            canvas.create_line(9*s, 8*s, 9*s, 15*s, **line)
        elif name == "refresh":
            canvas.create_arc(3*s, 3*s, 15*s, 15*s, start=35, extent=285, style=tk.ARC, outline=color, width=1.7*s)
            canvas.create_line(12*s, 3*s, 15*s, 4*s, **line)
            canvas.create_line(15*s, 4*s, 14*s, 7*s, **line)
        elif name == "send":
            canvas.create_line(2*s, 9*s, 15*s, 9*s, **line)
            canvas.create_line(10*s, 4*s, 15*s, 9*s, **line)
            canvas.create_line(15*s, 9*s, 10*s, 14*s, **line)
        return canvas

    def toggle_topmost(self) -> None:
        enabled = not self.pin_var.get()
        self.pin_var.set(enabled)
        self.root.attributes("-topmost", enabled)
        self.pin_label.configure(text="已置顶" if enabled else "置顶")

    def refresh_windows(self) -> None:
        script = '''tell application "System Events"
set windowRecords to {}
repeat with p in (every application process whose background only is false)
  set appName to name of p
  repeat with w in (every window of p)
    try
      set windowName to name of w
      if windowName is "" then set windowName to "(无标题)"
      set end of windowRecords to appName & tab & windowName
    end try
  end repeat
end repeat
set AppleScript's text item delimiters to linefeed
return windowRecords as text
end tell'''
        try:
            output = run_applescript(script)
            self.windows = []
            for row in output.splitlines():
                parts = row.split("\t", 1)
                if len(parts) == 2:
                    self.windows.append((parts[0], parts[1]))
            self.window_menu["values"] = [f"{app} — {title}" for app, title in self.windows]
            if self.windows:
                self.window_menu.current(0)
                self.status.set(f"找到 {len(self.windows)} 个窗口。")
            else:
                self.status.set("未找到可访问窗口；请检查辅助功能权限。")
        except (OSError, subprocess.CalledProcessError) as exc:
            self.status.set("读取窗口失败；请授权辅助功能权限后刷新。")
            if isinstance(exc, subprocess.CalledProcessError) and exc.stderr:
                messagebox.showerror("无法读取窗口", exc.stderr.strip(), parent=self.root)

    def send_command(self) -> None:
        value = self.command.get()
        selected = self.window_menu.current()
        if not value:
            messagebox.showinfo("没有命令", "请先输入一条命令。", parent=self.root)
            return
        if any(char in value for char in "\r\n\t"):
            messagebox.showerror("不支持的字符", "只支持单行命令，不能包含换行或制表符。", parent=self.root)
            return
        if selected < 0 or selected >= len(self.windows):
            messagebox.showinfo("选择窗口", "请先选择一个目标窗口。", parent=self.root)
            return
        app_name, window_name = self.windows[selected]
        self.root.withdraw()
        self.root.after(350, lambda: self.type_into_window(value, app_name, window_name))

    def type_into_window(self, value: str, app_name: str, window_name: str) -> None:
        app = applescript_string(app_name)
        window = applescript_string(window_name)
        text = applescript_string(value)
        script = f'''tell application "System Events"
set targetProcess to first application process whose name is {app}
set frontmost of targetProcess to true
repeat with targetWindow in (every window of targetProcess)
  if name of targetWindow is {window} then
    perform action "AXRaise" of targetWindow
    exit repeat
  end if
end repeat
delay 0.25
keystroke {text}
end tell'''
        try:
            run_applescript(script)
            self.status.set(f"已输入到：{app_name} — {window_name}。请检查后手动执行。")
        except (OSError, subprocess.CalledProcessError) as exc:
            detail = exc.stderr.strip() if isinstance(exc, subprocess.CalledProcessError) and exc.stderr else str(exc)
            self.status.set("输入失败；请检查辅助功能权限和目标窗口状态。")
            messagebox.showerror("输入失败", detail or "macOS 未能激活所选窗口。")
        finally:
            self.root.deiconify()
            self.root.lift()
            self.root.attributes("-topmost", self.pin_var.get())


if __name__ == "__main__":
    app = tk.Tk()
    CMDPutin(app)
    app.mainloop()
