"""One change to the stock keyboard: an app's private IME option without "=" has no value, and
the keyboard calls a method on that null value and crashes. getValue() now returns "" for it."""
import re
import sys
from pathlib import Path

p = Path(sys.argv[1]) / "com/android/inputmethod/diopen/C.smali"
s = p.read_text()
m = re.search(r"(\.method public getValue\(\)Ljava/lang/String;\n)(.*?)(\.end method)", s, re.S)
assert m, "getValue not found"
body = m.group(2)
ret = re.search(r"^( *)return-object (v\d+)$", body, re.M)
assert ret and body.count("return-object") == 1, "unexpected getValue"
indent, reg = ret.group(1), ret.group(2)
fix = ("%sif-nez %s, :has_value\n%sconst-string %s, \"\"\n%s:has_value\n%s" %
       (indent, reg, indent, reg, indent, ret.group(0)))
s = s[:m.start(2)] + body.replace(ret.group(0), fix) + s[m.end(2):]
p.write_text(s)
