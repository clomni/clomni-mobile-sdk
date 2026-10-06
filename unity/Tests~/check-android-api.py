#!/usr/bin/env python3
"""Checks every JVM call in Runtime/Android/ClomniAndroid.cs against android/messenger/api/messenger.api.

    python3 unity/Tests~/check-android-api.py        (from the repository root, or anywhere)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
API = (ROOT / "android/messenger/api/messenger.api").read_text()
CS = (ROOT / "unity/Runtime/Android/ClomniAndroid.cs").read_text()
TYPES = (ROOT / "unity/Runtime/ClomniTypes.cs").read_text()

# class (short name) -> {"funs": {(name, signature)}, "fields": {name}}
api = {}
for block in re.finditer(r"class ai/clomni/messenger/(\w+)[^{]*\{(.*?)\n\}", API, re.S):
    body = block.group(2)
    api[block.group(1)] = {
        "funs": set(re.findall(r"fun (\S+) (\S+)", body)),
        "fields": set(re.findall(r"field (\w+) ", body)),
    }

errors = []
checked = 0


def expect(cls, name, signature):
    global checked
    checked += 1
    if (name, signature) not in api.get(cls, {}).get("funs", set()):
        errors.append(f"{cls}.{name}{signature} is not in messenger.api")


calls = re.findall(r'Static\((clomni|push), "(\w+)",\s*"([^"]+)"', CS)
if len(calls) != len(re.findall(r"Static\((clomni|push), (?!setter,)", CS)):
    errors.append("a Static(...) call is not written as Static(owner, \"name\", \"signature\", ...)")
for owner, name, signature in calls:
    expect("Clomni" if owner == "clomni" else "ClomniPush", name, signature)

for name, interface in re.findall(r'Listen\("(\w+)", "(\w+)"', CS):
    expect("Clomni", name, f"(Lai/clomni/messenger/{interface};)V")

for cls, signature in re.findall(r'New\(Package \+ "(\w+)",\s*"([^"]+)"', CS):
    expect(cls, "<init>", signature)

for java_enum in re.findall(r'Enum\("(\w+)"', CS):
    members = re.search(r"enum " + java_enum + r"\s*\{([^}]*)\}", TYPES).group(1)
    for member in re.findall(r"\w+", members):
        checked += 1
        if member.upper() not in api.get(java_enum, {}).get("fields", set()):
            errors.append(f"{java_enum}.{member.upper()} is not in messenger.api")

# Listener interfaces: every abstract method has a C# proxy method of the same name and types.
JAVA_TO_CS = {"I": "int", "Z": "bool", "V": "void", "Ljava/lang/String;": "string"}
for cls, members in api.items():
    if not cls.endswith("Listener"):
        continue
    for name, signature in members["funs"]:
        args, ret = re.match(r"\((.*)\)(.+)", signature).groups()
        params = [JAVA_TO_CS[a] for a in re.findall(r"L[^;]+;|[IZ]", args)]
        pattern = (rf"public {JAVA_TO_CS[ret]} {name}\(" + ", ".join(rf"{p} \w+" for p in params) + r"\)")
        checked += 1
        if not re.search(pattern, CS):
            errors.append(f"no proxy method for {cls}.{name}{signature}")

for error in errors:
    print("FAIL", error)
print(f"{checked} checks, {len(errors)} failed")
sys.exit(1 if errors or checked == 0 else 0)
