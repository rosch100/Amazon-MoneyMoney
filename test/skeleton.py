#!/usr/bin/env python3
"""Print an indented skeleton (tags + class + short text) of HTML, skipping
script/style noise. Used to reverse-engineer Amazon's new order layout.

Usage:
  skeleton.py FILE [--class SUBSTR] [--nth N] [--max-depth D] [--max-text N]
If --class is given, only print subtrees rooted at the Nth element whose class
contains SUBSTR (0-based; default all matches).
"""
import sys
from html.parser import HTMLParser

VOID = {"area","base","br","col","embed","hr","img","input","link","meta",
        "param","source","track","wbr"}
SKIP = {"script","style","noscript","svg"}

class Node:
    def __init__(self, tag, attrs):
        self.tag = tag
        self.attrs = dict(attrs)
        self.children = []
        self.text = ""

class Builder(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#root", [])
        self.stack = [self.root]
        self.skip_depth = 0
    def handle_starttag(self, tag, attrs):
        if self.skip_depth:
            if tag in SKIP: self.skip_depth += 1
            return
        if tag in SKIP:
            self.skip_depth = 1
            return
        n = Node(tag, attrs)
        self.stack[-1].children.append(n)
        if tag not in VOID:
            self.stack.append(n)
    def handle_endtag(self, tag):
        if self.skip_depth:
            if tag in SKIP: self.skip_depth -= 1
            return
        if tag in VOID: return
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                break
    def handle_data(self, data):
        if self.skip_depth: return
        t = data.strip()
        if t:
            self.stack[-1].text += (" " if self.stack[-1].text else "") + t

def find(node, substr, out):
    cls = node.attrs.get("class", "")
    if substr in cls:
        out.append(node)
        return  # don't descend into matches-of-matches
    for c in node.children:
        find(c, substr, out)

def pp(node, depth, max_depth, max_text):
    if depth > max_depth: return
    ind = "  " * depth
    bits = [node.tag]
    cls = node.attrs.get("class")
    if cls: bits.append("." + ".".join(cls.split()))
    nid = node.attrs.get("id")
    if nid: bits.append("#" + nid)
    for k in ("href", "data-csa-c-slot-id", "name", "value", "aria-label"):
        if k in node.attrs:
            v = node.attrs[k]
            if len(v) > 80: v = v[:80] + "…"
            bits.append(f'{k}="{v}"')
    line = ind + " ".join(bits)
    own = node.text
    if own:
        if len(own) > max_text: own = own[:max_text] + "…"
        line += f"   ⟨{own}⟩"
    print(line)
    for c in node.children:
        pp(c, depth + 1, max_depth, max_text)

def main():
    args = sys.argv[1:]
    path = args[0]
    substr = None; nth = None; max_depth = 40; max_text = 60
    i = 1
    while i < len(args):
        if args[i] == "--class": substr = args[i+1]; i += 2
        elif args[i] == "--nth": nth = int(args[i+1]); i += 2
        elif args[i] == "--max-depth": max_depth = int(args[i+1]); i += 2
        elif args[i] == "--max-text": max_text = int(args[i+1]); i += 2
        else: i += 1
    b = Builder()
    with open(path, encoding="utf-8", errors="replace") as f:
        b.feed(f.read())
    if substr is None:
        pp(b.root, 0, max_depth, max_text)
        return
    matches = []
    find(b.root, substr, matches)
    print(f"# {len(matches)} match(es) for class~='{substr}'", file=sys.stderr)
    targets = matches if nth is None else [matches[nth]]
    for t in targets:
        pp(t, 0, max_depth, max_text)
        print("-" * 60)

if __name__ == "__main__":
    main()
