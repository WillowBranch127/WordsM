#!/usr/bin/env python3

import os
import sys

# 不希望读取的二进制/无关文件
IGNORE_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico",
    ".mp3", ".wav", ".mp4", ".mov", ".avi",
    ".zip", ".tar", ".gz", ".7z", ".rar",
    ".pdf", ".dmg", ".app", ".xcarchive",
    ".o", ".a", ".dylib",
}

# 不希望进入的目录
IGNORE_DIRS = {
    ".git",
    ".build",
    "DerivedData",
    "node_modules",
    "__pycache__",
}


def is_text_file(path):
    """简单判断一个文件是不是文本文件"""
    ext = os.path.splitext(path)[1].lower()

    if ext in IGNORE_EXTENSIONS:
        return False

    try:
        with open(path, "rb") as f:
            data = f.read(8192)

        # 包含 NUL 通常意味着二进制文件
        if b"\x00" in data:
            return False

        return True
    except Exception:
        return False


def collect_files(root):
    result = []

    for current_dir, dirs, files in os.walk(root):
        # 原地修改，阻止 os.walk 进入这些目录
        dirs[:] = [
            d for d in dirs
            if d not in IGNORE_DIRS
        ]

        for filename in sorted(files):
            path = os.path.join(current_dir, filename)

            if is_text_file(path):
                result.append(path)

    return sorted(result)


def main():
    if len(sys.argv) < 2:
        print("用法:")
        print(f"  python3 {sys.argv[0]} <目录>")
        return

    root = os.path.abspath(sys.argv[1])

    if not os.path.isdir(root):
        print(f"错误：不是目录：{root}")
        return

    output = os.path.join(root, "all_files_content.txt")

    files = collect_files(root)

    with open(output, "w", encoding="utf-8") as out:
        for path in files:
            relative_path = os.path.relpath(path, root)

            out.write("\n")
            out.write("=" * 80 + "\n")
            out.write(f"FILE: {relative_path}\n")
            out.write("=" * 80 + "\n\n")

            try:
                with open(path, "r", encoding="utf-8") as f:
                    out.write(f.read())
            except UnicodeDecodeError:
                # UTF-8 失败就尝试忽略非法字符
                with open(path, "r", encoding="utf-8", errors="replace") as f:
                    out.write(f.read())
            except Exception as e:
                out.write(f"[无法读取文件: {e}]\n")

            out.write("\n")

    print(f"完成！")
    print(f"共找到 {len(files)} 个文本文件")
    print(f"输出文件：{output}")


if __name__ == "__main__":
    main()
