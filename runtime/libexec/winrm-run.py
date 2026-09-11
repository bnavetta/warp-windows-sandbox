#!/usr/bin/env python3

import argparse
import os
import sys

import winrm


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a script through a Windows Remote Management endpoint."
    )
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--shell", choices=("pwsh", "cmd"), required=True)
    return parser.parse_args()


def write_output(stream: object, data: bytes) -> None:
    if data:
        stream.buffer.write(data)
        stream.buffer.flush()


def main() -> int:
    args = parse_args()
    password = os.environ.get("VM_WINRM_PASSWORD")
    if not password:
        password_file = os.environ.get("VM_WINRM_PASSWORD_FILE")
        if not password_file:
            print("[windows-vm] error: WinRM password is not configured", file=sys.stderr)
            return 1
        try:
            with open(password_file, encoding="utf-8") as file:
                password = file.read().rstrip("\r\n")
        except OSError as error:
            print(
                f"[windows-vm] error: cannot read WinRM password: {error}",
                file=sys.stderr,
            )
            return 1
        if not password:
            print("[windows-vm] error: WinRM password is empty", file=sys.stderr)
            return 1

    script = sys.stdin.read()
    try:
        session = winrm.Session(
            args.endpoint,
            auth=(args.user, password),
            transport="basic",
            operation_timeout_sec=int(
                os.environ.get("VM_WINRM_OPERATION_TIMEOUT", "20")
            ),
            read_timeout_sec=int(os.environ.get("VM_WINRM_READ_TIMEOUT", "30")),
        )
        if args.shell == "cmd":
            response = session.run_cmd("cmd.exe", ["/Q", "/D", "/C", script])
        else:
            response = session.run_ps(script)
    except Exception as error:
        print(f"[windows-vm] error: WinRM command failed: {error}", file=sys.stderr)
        return 1

    write_output(sys.stdout, response.std_out)
    write_output(sys.stderr, response.std_err)
    return int(response.status_code)


if __name__ == "__main__":
    sys.exit(main())
