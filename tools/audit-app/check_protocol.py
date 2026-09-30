#!/usr/bin/env python3
"""check_protocol.py - fails when the probe protocol constants in the guest header (guest/audit_protocol.h) and in the
app (Sources/Engine/GuestLink.swift) disagree. They are written twice on purpose (C for the guest, Swift for the
host), so this is what keeps them one protocol.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def norm(s):
    return s.replace("_", "").lower()


def num(s):
    return int(s.replace("_", "").rstrip("uU"), 0)


def main():
    header = open(os.path.join(HERE, "guest", "audit_protocol.h"), encoding="utf-8").read()
    swift = open(os.path.join(HERE, "Sources", "Engine", "GuestLink.swift"), encoding="utf-8").read()

    # C: #define AUDIT_MB_GUEST_STATE 0x008u  /  AUDIT_STATE_IDLE 1u  /  AUDIT_MAILBOX_MAGIC 0x4D415544u
    c = {}
    for name, val in re.findall(r"#define\s+(AUDIT_[A-Z0-9_]+)\s+(0x[0-9A-Fa-f]+u?|\d+u?)\b", header):
        c[name] = num(val)
    # Swift: static let offGuestState: UInt32 = 0x008 / stateIdle: UInt32 = 1 / magic: UInt32 = 0x4D41_5544
    sw = {}
    for name, val in re.findall(r"static let ([A-Za-z0-9]+):\s*(?:UInt32|Int)\s*=\s*(0x[0-9A-Fa-f_]+|\d+)", swift):
        sw[name] = num(val)

    pairs = []
    for name, val in c.items():
        if name.startswith("AUDIT_MB_"):
            pairs.append((name, val, "off" + name[len("AUDIT_MB_"):]))
        elif name.startswith(("AUDIT_STATE_", "AUDIT_CMD_", "AUDIT_RESULT_")):
            pairs.append((name, val, name[len("AUDIT_"):]))
    pairs += [("AUDIT_MAILBOX_MAGIC", c["AUDIT_MAILBOX_MAGIC"], "magic"), ("AUDIT_MAILBOX_SIZE", c["AUDIT_MAILBOX_SIZE"], "size"),
              ("AUDIT_PROTOCOL_VERSION", c["AUDIT_PROTOCOL_VERSION"], "protocolVersion"),
              ("AUDIT_NAME_LEN", c["AUDIT_NAME_LEN"], "nameLen"), ("AUDIT_MESSAGE_LEN", c["AUDIT_MESSAGE_LEN"], "messageLen"),
              ("AUDIT_PARAMS_LEN", c["AUDIT_PARAMS_LEN"], "paramsLen")]

    by_norm = {norm(k): (k, v) for k, v in sw.items()}
    errors, matched = [], 0
    for cname, cval, swname in pairs:
        hit = by_norm.get(norm(swname))
        if not hit:
            errors.append(f"{cname} = {cval:#x} has no Swift constant (looked for {swname})")
        elif hit[1] != cval:
            errors.append(f"{cname} = {cval:#x} but Swift {hit[0]} = {hit[1]:#x}")
        else:
            matched += 1
    # And the other way: every Swift offset must be in the header.
    c_norm = {norm(n[len("AUDIT_MB_"):]) for n in c if n.startswith("AUDIT_MB_")}
    for name in sw:
        if name.startswith("off") and norm(name[3:]) not in c_norm:
            errors.append(f"Swift {name} is not in audit_protocol.h")
    # The mailbox must fit its declared size.
    top = max(v for k, v in c.items() if k.startswith("AUDIT_MB_")) + c["AUDIT_PARAMS_LEN"]
    if top > c["AUDIT_MAILBOX_SIZE"]:
        errors.append(f"the highest field ends at {top:#x}, past the mailbox size {c['AUDIT_MAILBOX_SIZE']:#x}")

    if errors:
        print("check_protocol: the guest header and GuestLink.swift disagree")
        for e in errors:
            print(" -", e)
        return 1
    print(f"check_protocol: {matched} constants agree between audit_protocol.h and GuestLink.swift")
    return 0


if __name__ == "__main__":
    sys.exit(main())
