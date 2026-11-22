#!/usr/bin/env python3
"""Check that the built homepage's local stylesheets exist under its base path."""
import argparse
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


class Stylesheets(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urls = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "link" and "stylesheet" in values.get("rel", "").lower().split():
            self.urls.append(values.get("href", ""))


def check_stylesheets(public, base_url):
    public = Path(public).resolve()
    base = urlsplit(base_url)
    prefix = "/" + base.path.strip("/") + "/" if base.path.strip("/") else "/"
    parser = Stylesheets()
    parser.feed((public / "index.html").read_text(encoding="utf-8"))
    if not parser.urls:
        raise ValueError("the built homepage has no stylesheet")
    checked = 0
    for url in parser.urls:
        parsed = urlsplit(url)
        if parsed.netloc and parsed.netloc != base.netloc:
            continue
        path = unquote(parsed.path)
        if not path.startswith(prefix):
            raise ValueError(f"stylesheet {url!r} does not use base path {prefix!r}")
        target = (public / path[len(prefix):]).resolve()
        if not target.is_relative_to(public) or not target.is_file():
            raise ValueError(f"stylesheet {url!r} is absent from the built site")
        checked += 1
    if not checked:
        raise ValueError("the built homepage has no local stylesheet")
    return checked


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("public")
    parser.add_argument("base_url")
    args = parser.parse_args()
    print(f"site: checked {check_stylesheets(args.public, args.base_url)} local stylesheets")
