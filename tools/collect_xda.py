#!/usr/bin/env python3
"""Import, fetch, and search source-attributed XDA research."""

from __future__ import annotations

import argparse
import hashlib
from io import BytesIO
import json
from pathlib import Path
import re
import sqlite3
import sys
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen

from lxml import html as lxml_html
from pypdf import PdfReader


ROOT = Path(__file__).resolve().parents[1]
ARCHIVE_URL = "https://raw.githubusercontent.com/mKonic/redmagic-wiki/master/data/rm11pro-unlock.jsonl"
THREADS = {
    "4780930": "https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/",
    "4787673": "https://xdaforums.com/t/redmagic-11-pro-10-pro-astra-bootloader-unlock-root-guide-fastboot-o-fastbootd-o-gsi-o.4787673/",
}
USER_AGENT = "RedMagicLinuxResearch/1.0 (sequential public-forum archive; contact project owner)"
MAX_IMPORT_BYTES = 100 * 1024 * 1024
CHALLENGE_MARKERS = (
    "just a moment...", "checking your browser", "verify you are human",
    "cloudflare ray id", "attention required! | cloudflare",
    "captcha verification",
)


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def digest(data: bytes | str) -> str:
    if isinstance(data, str):
        data = data.encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def clean_text(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def page_number_for_thread(url: str, thread_id: str) -> int | None:
    parsed = urlparse(url)
    if parsed.hostname not in {"xdaforums.com", "www.xdaforums.com"}:
        return None
    thread = re.search(r"/t/[^/]+\.(\d+)(?:/|$)", parsed.path)
    if not thread or thread.group(1) != str(thread_id):
        return None
    page = re.search(r"/page-(\d+)(?:/|$)", parsed.path)
    return int(page.group(1)) if page else 1


def page_url_matches(url: str, thread_id: str, page_num: int) -> bool:
    return page_number_for_thread(url, thread_id) == page_num


def parse_xda_page(source: str, thread_id: str, page_url: str) -> dict:
    document = lxml_html.fromstring(source)
    articles = document.xpath("//article[contains(concat(' ', normalize-space(@class), ' '), ' js-post ')]")
    posts = []
    for article in articles:
        raw_id = article.get("id", "")
        match = re.search(r"(?:js-post-|post-)?(\d{5,})", raw_id)
        post_id = match.group(1) if match else re.sub(r"^post-", "", article.get("data-content", ""))
        if not post_id:
            continue
        body_nodes = article.xpath(".//*[contains(concat(' ', normalize-space(@class), ' '), ' bbWrapper ')]")
        body = body_nodes[0] if body_nodes else article
        quotes = [clean_text(node.text_content()) for node in body.xpath(".//blockquote")]
        author_text = clean_text(" ".join(body.xpath(".//text()[not(ancestor::blockquote)]")))
        author_nodes = article.xpath(".//*[contains(concat(' ', normalize-space(@class), ' '), ' username ')]")
        author = clean_text(author_nodes[0].text_content()) if author_nodes else article.get("data-author", "")
        attribution = article.xpath(".//*[contains(concat(' ', normalize-space(@class), ' '), ' message-attribution ')]")
        attr = attribution[0] if attribution else article
        posted_times = attr.xpath(".//time[@datetime]/@datetime")
        posted = posted_times[0] if posted_times else None
        edit_nodes = article.xpath(".//*[contains(concat(' ', normalize-space(@class), ' '), ' message-lastEdit ')]")
        edited = None
        if edit_nodes:
            edit_times = edit_nodes[0].xpath(".//time[@datetime]/@datetime")
            edited = edit_times[0] if edit_times else edit_nodes[0].get("title") or clean_text(edit_nodes[0].text_content())
        links = []
        for link in body.xpath(".//a[@href]"):
            href = urljoin(page_url, link.get("href"))
            if href not in {entry["url"] for entry in links}:
                links.append({"url": href, "text": clean_text(link.text_content())})
        permalink_hrefs = attr.xpath(f".//a[contains(@href, '/post-{post_id}')]/@href")
        if not permalink_hrefs:
            permalink_hrefs = article.xpath(f".//a[contains(@href, '/post-{post_id}')]/@href")
        permalink = urljoin(page_url, permalink_hrefs[0]) if permalink_hrefs else f"https://xdaforums.com/t/{thread_id}/post-{post_id}"
        raw_html = lxml_html.tostring(article, encoding="unicode", method="html")
        content = raw_html.encode("utf-8")
        posts.append({
            "thread_id": thread_id, "post_id": post_id, "author": author,
            "posted_at": posted, "edited_at": edited, "permalink": permalink,
            "author_text": author_text, "quoted_text": "\n\n".join(q for q in quotes if q),
            "links": links, "source_html": raw_html, "source_markdown": None,
            "source_hash": digest(content), "retrieved_at": now(),
        })
    title_nodes = document.xpath("//*[contains(concat(' ', normalize-space(@class), ' '), ' p-title-value ')]")
    page_links = []
    page_navs = document.xpath("//*[contains(concat(' ', normalize-space(@class), ' '), ' pageNavWrapper ')]")
    for nav in page_navs:
        for href in nav.xpath(".//a[@href]/@href"):
            absolute = urljoin(page_url, href)
            match = re.search(r"/page-(\d+)(?:/|$|[?#])", urlparse(absolute).path)
            if match and page_number_for_thread(absolute, thread_id) is not None:
                page_links.append(int(match.group(1)))
    title = clean_text(title_nodes[0].text_content()) if title_nodes else clean_text(document.xpath("string(//title)"))
    visible_text = clean_text(" ".join(document.xpath("//body//text()[not(ancestor::script or ancestor::style or ancestor::noscript)]"))).lower()
    login_form = bool(document.xpath("//input[translate(@type,'PASSWORD','password')='password']"))
    challenged = not posts and (any(marker in f"{title} {visible_text}".lower() for marker in CHALLENGE_MARKERS)
                                or login_form or "log in" in title.lower() or "login" in title.lower())
    return {"posts": posts, "title": title, "max_page": max(page_links, default=1), "challenged": challenged}


def split_markdown_quotes(markdown: str) -> tuple[str, str]:
    author, quoted = [], []
    for line in markdown.splitlines():
        if re.match(r"^\s*>\s?", line):
            quoted.append(re.sub(r"^\s*> ?", "", line))
        else:
            author.append(line)
    author_text = re.sub(r"\n(?:[ \t]*\n){2,}", "\n\n", "\n".join(author)).strip()
    return author_text, "\n".join(quoted).strip()


def markdown_links(value: str) -> list[dict[str, str]]:
    found = []
    for match in re.finditer(r"\[([^\]]+)\]\((https?://[^)]+)\)|(https?://\S+)", value):
        label = match.group(1) or match.group(3)
        url = match.group(2) or match.group(3)
        if not any(item["url"] == url for item in found):
            found.append({"url": url.rstrip(".,"), "text": label})
    return found


def db_connect(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys = ON")
    db.execute("PRAGMA journal_mode = WAL")
    db.executescript("""
        CREATE TABLE IF NOT EXISTS threads(
            thread_id TEXT PRIMARY KEY, requested_url TEXT NOT NULL, title TEXT,
            first_seen TEXT NOT NULL, last_seen TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS posts(
            thread_id TEXT NOT NULL, post_id TEXT NOT NULL, author TEXT, posted_at TEXT,
            edited_at TEXT, permalink TEXT, author_text TEXT NOT NULL, quoted_text TEXT NOT NULL,
            links_json TEXT NOT NULL, source_html TEXT, source_markdown TEXT,
            source_hash TEXT NOT NULL, snapshot_hash TEXT NOT NULL, current_source TEXT NOT NULL DEFAULT '',
            first_seen TEXT NOT NULL, last_seen TEXT NOT NULL,
            PRIMARY KEY(thread_id, post_id), FOREIGN KEY(thread_id) REFERENCES threads(thread_id)
        );
        CREATE TABLE IF NOT EXISTS revisions(
            revision_id INTEGER PRIMARY KEY, thread_id TEXT NOT NULL, post_id TEXT NOT NULL,
            author TEXT, posted_at TEXT, edited_at TEXT, permalink TEXT,
            author_text TEXT NOT NULL, quoted_text TEXT NOT NULL, links_json TEXT NOT NULL,
            source_html TEXT, source_markdown TEXT, source_hash TEXT NOT NULL,
            snapshot_hash TEXT NOT NULL, retrieved_at TEXT NOT NULL, source_label TEXT NOT NULL,
            UNIQUE(thread_id, post_id, snapshot_hash), FOREIGN KEY(thread_id, post_id)
                REFERENCES posts(thread_id, post_id)
        );
        CREATE TABLE IF NOT EXISTS pages(
            page_id INTEGER PRIMARY KEY, thread_id TEXT NOT NULL, page_num INTEGER NOT NULL,
            requested_url TEXT NOT NULL, final_url TEXT NOT NULL, http_status INTEGER,
            status TEXT NOT NULL, challenged INTEGER NOT NULL DEFAULT 0,
            content_hash TEXT, cache_path TEXT, post_count INTEGER NOT NULL DEFAULT 0,
            discovered_max_page INTEGER NOT NULL DEFAULT 1, retrieved_at TEXT NOT NULL,
            error TEXT
        );
        CREATE INDEX IF NOT EXISTS pages_lookup ON pages(thread_id, page_num, page_id);
        CREATE TABLE IF NOT EXISTS documents(
            document_hash TEXT PRIMARY KEY, source TEXT NOT NULL, kind TEXT NOT NULL,
            imported_at TEXT NOT NULL, last_seen TEXT NOT NULL, extracted_text TEXT NOT NULL,
            extraction_status TEXT NOT NULL, size_bytes INTEGER NOT NULL, cache_path TEXT
        );
    """)
    post_columns = {row["name"] for row in db.execute("PRAGMA table_info(posts)")}
    if "current_source" not in post_columns:
        db.execute("ALTER TABLE posts ADD COLUMN current_source TEXT NOT NULL DEFAULT ''")
    document_columns = {row["name"] for row in db.execute("PRAGMA table_info(documents)")}
    if "cache_path" not in document_columns:
        db.execute("ALTER TABLE documents ADD COLUMN cache_path TEXT")
    return db


def ensure_thread(db: sqlite3.Connection, thread_id: str, url: str, title: str | None = None):
    stamp = now()
    db.execute("""INSERT INTO threads(thread_id,requested_url,title,first_seen,last_seen)
                  VALUES(?,?,?,?,?) ON CONFLICT(thread_id) DO UPDATE SET
                  requested_url=excluded.requested_url,title=COALESCE(excluded.title,threads.title),last_seen=excluded.last_seen""",
               (thread_id, url, title, stamp, stamp))


def record_post(db: sqlite3.Connection, post: dict, source_label: str):
    thread_id, post_id = str(post["thread_id"]), str(post["post_id"])
    if not thread_id.isdecimal() or not post_id.isdecimal():
        raise ValueError("post and thread IDs must be numeric")
    ensure_thread(db, thread_id, post.get("thread_url") or THREADS.get(thread_id) or post.get("permalink", "https://xdaforums.com/"))
    links_json = json.dumps(post.get("links", []), ensure_ascii=False, sort_keys=True)
    source_hash = post.get("source_hash") or digest(post.get("source_markdown") or post.get("source_html") or post.get("author_text", ""))
    semantic_content = {
        "author": post.get("author") or "", "posted_at": post.get("posted_at") or "",
        "edited_at": post.get("edited_at") or "", "permalink": post.get("permalink") or "",
        "author_text": post.get("author_text", ""), "quoted_text": post.get("quoted_text", ""),
        "links": sorted(post.get("links", []), key=lambda item: (item.get("url", ""), item.get("text", ""))),
    }
    snapshot = digest(json.dumps(semantic_content, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    stamp = post.get("retrieved_at") or now()
    values = (post.get("author"), post.get("posted_at"), post.get("edited_at"), post.get("permalink"),
              post.get("author_text", ""), post.get("quoted_text", ""), links_json,
              post.get("source_html"), post.get("source_markdown"), source_hash, snapshot)
    existing = db.execute("SELECT current_source FROM posts WHERE thread_id=? AND post_id=?", (thread_id, post_id)).fetchone()
    if existing:
        if source_label.startswith("XDA HTML ") or not existing["current_source"].startswith("XDA HTML "):
            db.execute("""UPDATE posts SET author=?,posted_at=?,edited_at=?,permalink=?,author_text=?,quoted_text=?,
                         links_json=?,source_html=?,source_markdown=?,source_hash=?,snapshot_hash=?,current_source=?,last_seen=?
                         WHERE thread_id=? AND post_id=?""", (*values, source_label, stamp, thread_id, post_id))
        else:
            db.execute("UPDATE posts SET last_seen=? WHERE thread_id=? AND post_id=?", (stamp, thread_id, post_id))
    else:
        db.execute("""INSERT INTO posts(thread_id,post_id,author,posted_at,edited_at,permalink,author_text,
                     quoted_text,links_json,source_html,source_markdown,source_hash,snapshot_hash,current_source,first_seen,last_seen)
                     VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                   (thread_id, post_id, *values, source_label, stamp, stamp))
    db.execute("""INSERT OR IGNORE INTO revisions(thread_id,post_id,author,posted_at,edited_at,permalink,
                 author_text,quoted_text,links_json,source_html,source_markdown,source_hash,snapshot_hash,
                 retrieved_at,source_label) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
               (thread_id, post_id, *values[:10], snapshot, stamp, source_label))


def add_page(db: sqlite3.Connection, *, thread_id: str, page_num: int, requested_url: str,
             final_url: str, http_status: int | None, status: str, challenged: bool = False,
             content_hash: str | None = None, cache_path: str | None = None,
             post_count: int = 0, discovered_max_page: int = 1, error: str | None = None):
    ensure_thread(db, thread_id, THREADS.get(thread_id, requested_url))
    db.execute("""INSERT INTO pages(thread_id,page_num,requested_url,final_url,http_status,status,challenged,
                 content_hash,cache_path,post_count,discovered_max_page,retrieved_at,error)
                 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)""",
               (thread_id, page_num, requested_url, final_url, http_status, status, int(challenged),
                content_hash, cache_path, post_count, discovered_max_page, now(), error))


def page_complete(db: sqlite3.Connection, thread_id: str, page_num: int) -> bool:
    row = db.execute("SELECT status,post_count,final_url FROM pages WHERE thread_id=? AND page_num=? ORDER BY page_id DESC LIMIT 1", (thread_id, page_num)).fetchone()
    return bool(row and page_result_complete(thread_id, page_num, row["status"], row["post_count"], row["final_url"]))


def page_result_complete(thread_id: str, page_num: int, status: str, post_count: int, final_url: str) -> bool:
    return status in {"ok", "redirected"} and post_count > 0 and page_url_matches(final_url, thread_id, page_num)


def should_fetch_page(db: sqlite3.Connection, thread_id: str, page_num: int, refresh: bool = False) -> bool:
    return refresh or page_num in {1, 93} or not page_complete(db, thread_id, page_num)


def page_targets(start_page: int, last_page: int, selected: list[int] | None = None) -> set[int]:
    targets = {1}
    if last_page >= 93:
        targets.add(93)
    if selected:
        targets.update(selected)
    elif start_page <= last_page:
        targets.update(range(start_page, last_page + 1))
    return targets


def import_jsonl(db: sqlite3.Connection, source: str, data: bytes, thread_id: str):
    ensure_thread(db, thread_id, THREADS.get(thread_id, f"https://xdaforums.com/t/{thread_id}/"))
    imported = 0
    for line_number, raw_line in enumerate(data.decode("utf-8-sig").splitlines(), 1):
        if not raw_line.strip():
            continue
        try:
            item = json.loads(raw_line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"invalid JSON on line {line_number}: {exc}") from exc
        raw_id = str(item.get("id") or item.get("post_id") or "")
        post_id = re.sub(r"^post-", "", raw_id)
        markdown = str(item.get("body_md") or item.get("markdown") or item.get("body") or "")
        if not post_id or not markdown:
            continue
        author_text, quoted_text = split_markdown_quotes(markdown)
        permalink = item.get("permalink") or f"https://xdaforums.com/t/{thread_id}/post-{post_id}"
        permalink = urljoin("https://xdaforums.com", permalink)
        parsed_permalink = urlparse(permalink)
        if parsed_permalink.scheme != "https" or parsed_permalink.hostname not in {"xdaforums.com", "www.xdaforums.com"}:
            raise ValueError(f"invalid XDA permalink on line {line_number}")
        post = {
            "thread_id": str(item.get("thread_id") or thread_id), "post_id": post_id,
            "author": item.get("author"), "posted_at": item.get("datetime") or item.get("posted_at"),
            "edited_at": item.get("edited_at") or item.get("edit_datetime"), "permalink": permalink,
            "author_text": author_text, "quoted_text": quoted_text,
            "links": markdown_links(markdown), "source_html": None, "source_markdown": markdown,
            "source_hash": digest(markdown), "retrieved_at": now(),
        }
        record_post(db, post, source)
        imported += 1
    db.commit()
    return imported


def extract_document_text(kind: str, data: bytes) -> tuple[str, str]:
    if kind == "html":
        document = lxml_html.fromstring(data.decode("utf-8", errors="replace"))
        return clean_text(" ".join(document.xpath("//body//text()[not(ancestor::script or ancestor::style or ancestor::noscript)]"))), "text extracted with lxml"
    try:
        reader = PdfReader(BytesIO(data), strict=False)
        return "\n\n".join(page.extract_text() or "" for page in reader.pages), f"text extracted with pypdf from {len(reader.pages)} pages"
    except Exception as exc:
        return "", f"PDF text extraction failed: {exc}"


def import_document(db: sqlite3.Connection, source: str, data: bytes, kind: str, cache: Path):
    if len(data) > MAX_IMPORT_BYTES:
        raise ValueError(f"document exceeds {MAX_IMPORT_BYTES // (1024 * 1024)} MiB limit")
    checksum = digest(data)
    directory = cache / "documents"
    directory.mkdir(parents=True, exist_ok=True)
    cached = directory / f"{checksum}.{kind}"
    if not cached.exists():
        temporary = cached.with_suffix(cached.suffix + ".tmp")
        temporary.write_bytes(data)
        temporary.replace(cached)
    text, extraction_status = extract_document_text(kind, data)
    db.execute("""INSERT INTO documents(document_hash,source,kind,imported_at,last_seen,extracted_text,
                 extraction_status,size_bytes,cache_path) VALUES(?,?,?,?,?,?,?,?,?)
                 ON CONFLICT(document_hash) DO UPDATE SET source=excluded.source,last_seen=excluded.last_seen,
                 extracted_text=excluded.extracted_text,extraction_status=excluded.extraction_status,cache_path=excluded.cache_path""",
               (checksum, source, kind, now(), now(), text, extraction_status, len(data), str(cached)))
    db.commit()
    return checksum, extraction_status


def download_source(source: str) -> bytes:
    if source == "default":
        source = ARCHIVE_URL
    parsed = urlparse(source)
    if parsed.scheme in {"http", "https"}:
        if parsed.scheme != "https" or parsed.hostname not in {"raw.githubusercontent.com", "github.com"}:
            raise ValueError("remote imports are limited to HTTPS GitHub archive files")
        request = Request(source, headers={"User-Agent": USER_AGENT})
        with urlopen(request, timeout=30) as response:
            data = response.read(MAX_IMPORT_BYTES + 1)
    else:
        path = Path(source).expanduser().resolve()
        if not path.is_file():
            raise ValueError(f"not a file: {path}")
        if path.stat().st_size > MAX_IMPORT_BYTES:
            raise ValueError("import exceeds 100 MiB limit")
        data = path.read_bytes()
        source = str(path)
    if len(data) > MAX_IMPORT_BYTES:
        raise ValueError("import exceeds 100 MiB limit")
    return data


def command_import(args, db):
    source = args.source or "default"
    data = download_source(source)
    lower = (source if source != "default" else ARCHIVE_URL).lower()
    path = Path(source).expanduser() if not urlparse(source).scheme else None
    if lower.endswith(".jsonl") or (not path and "rm11pro-unlock" in lower):
        count = import_jsonl(db, source if source != "default" else ARCHIVE_URL, data, args.thread)
        print(f"Imported {count} source posts from {source if source != 'default' else ARCHIVE_URL}")
    elif path and path.suffix.lower() in {".html", ".htm", ".pdf"}:
        kind = "pdf" if path.suffix.lower() == ".pdf" else "html"
        checksum, status = import_document(db, str(path.resolve()), data, kind, args.cache)
        print(f"Imported {kind.upper()} document sha256:{checksum}; {status}")
    else:
        raise ValueError("import supports JSONL archives or local .html/.htm/.pdf evidence")


def cache_page(cache: Path, thread_id: str, page_num: int, source: bytes, checksum: str) -> Path:
    directory = cache / f"thread-{thread_id}"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"page-{page_num:04d}-{checksum}.html"
    if not path.exists():
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_bytes(source)
        temporary.replace(path)
    return path


def requested_page_url(base: str, page_num: int) -> str:
    base = base.rstrip("/") + "/"
    return base if page_num == 1 else urljoin(base, f"page-{page_num}")


def retry_after_seconds(headers: dict) -> float | None:
    value = headers.get("retry-after")
    if not value:
        return None
    try:
        return max(0.0, float(value))
    except ValueError:
        try:
            return max(0.0, (parsedate_to_datetime(value) - datetime.now(timezone.utc)).total_seconds())
        except (TypeError, ValueError):
            return None


async def fetch_one(page, db, cache: Path, thread_id: str, page_num: int, url: str, delay: float):
    import asyncio
    from playwright.async_api import TimeoutError as PlaywrightTimeoutError

    await asyncio.sleep(delay)
    for attempt in range(4):
        try:
            response = await page.goto(url, wait_until="domcontentloaded", timeout=45000)
            status = response.status if response else None
            headers = response.headers if response else {}
            try:
                await page.wait_for_selector("article.js-post", state="attached", timeout=15000)
            except PlaywrightTimeoutError:
                pass
            final_url = page.url
            source = (await page.content()).encode("utf-8")
            checksum = digest(source)
            parsed = parse_xda_page(source.decode("utf-8", errors="replace"), thread_id, final_url)
            if status in {429, 503}:
                wait = retry_after_seconds(headers) or min(30 * (2 ** attempt), 300)
                add_page(db, thread_id=thread_id, page_num=page_num, requested_url=url, final_url=final_url,
                         http_status=status, status="rate_limited", content_hash=checksum,
                         cache_path=str(cache_page(cache, thread_id, page_num, source, checksum)),
                         discovered_max_page=parsed["max_page"], error=f"Retry-After: {wait:g}s")
                db.commit()
                if attempt == 3:
                    return None
                print(f"Server returned {status}; waiting {wait:g}s as directed before retry.", flush=True)
                await asyncio.sleep(wait)
                continue
            if parsed["challenged"]:
                cached = cache_page(cache, thread_id, page_num, source, checksum)
                add_page(db, thread_id=thread_id, page_num=page_num, requested_url=url, final_url=final_url,
                         http_status=status, status="challenge", challenged=True, content_hash=checksum,
                         cache_path=str(cached), discovered_max_page=parsed["max_page"],
                         error="Challenge/login page retained; not treated as an empty thread")
                db.commit()
                print(f"Stopped at thread {thread_id} page {page_num}: challenge/login page retained.", flush=True)
                return None
            cached = cache_page(cache, thread_id, page_num, source, checksum)
            final_page = page_number_for_thread(final_url, thread_id)
            if final_page != page_num:
                add_page(db, thread_id=thread_id, page_num=page_num, requested_url=url, final_url=final_url,
                         http_status=status, status="redirect_mismatch", content_hash=checksum,
                         cache_path=str(cached), discovered_max_page=1,
                         error=f"Requested page {page_num}; final URL resolves to page {final_page} of this thread")
                db.commit()
                print(f"Stopped at thread {thread_id} page {page_num}: redirect resolved to page {final_page}.", flush=True)
                return None
            status_label = "redirected" if final_url.rstrip("/") != url.rstrip("/") else (
                "http_error" if status is not None and status >= 400 and not parsed["posts"]
                else ("ok" if parsed["posts"] else "empty"))
            add_page(db, thread_id=thread_id, page_num=page_num, requested_url=url, final_url=final_url,
                     http_status=status, status=status_label, content_hash=checksum,
                     cache_path=str(cached), post_count=len(parsed["posts"]), discovered_max_page=parsed["max_page"])
            ensure_thread(db, thread_id, THREADS.get(thread_id, url), parsed["title"] or None)
            for post in parsed["posts"]:
                post["thread_url"] = url
                record_post(db, post, f"XDA HTML {final_url}")
            db.commit()
            print(f"Fetched thread {thread_id} page {page_num}: {len(parsed['posts'])} posts ({status_label}).", flush=True)
            if not page_complete(db, thread_id, page_num):
                return None
            return parsed["max_page"]
        except KeyboardInterrupt:
            raise
        except Exception as exc:
            add_page(db, thread_id=thread_id, page_num=page_num, requested_url=url, final_url=page.url,
                     http_status=None, status="network_error", error=str(exc)[:500])
            db.commit()
            print(f"Fetch failed for {url}: {exc}", file=sys.stderr)
            return None
    return None


async def fetch_threads(args, db):
    try:
        from playwright.async_api import async_playwright
    except ImportError as exc:
        raise RuntimeError("Playwright is required for fetch; install tools/requirements.txt") from exc
    thread_urls = {}
    explicit_threads = [str(thread_id) for thread_id in args.thread or []]
    supplied_url_id = None
    if args.url:
        parsed_url = urlparse(args.url)
        if (parsed_url.scheme != "https" or parsed_url.hostname not in {"xdaforums.com", "www.xdaforums.com"}
                or not parsed_url.path.startswith("/t/") or parsed_url.username or parsed_url.password
                or parsed_url.port not in {None, 443} or parsed_url.query or parsed_url.fragment):
            raise ValueError("--url must be an HTTPS XDA thread URL")
        if re.search(r"/page-\d+(?:/|$)", parsed_url.path):
            raise ValueError("--url must identify the thread root, not a page URL")
        match = re.search(r"\.(\d+)(?:/|$)", parsed_url.path)
        supplied_url_id = match.group(1) if match else None
        if not supplied_url_id or supplied_url_id not in explicit_threads:
            raise ValueError("additional --url requires its numeric ID in --thread")
    for thread_id in explicit_threads or THREADS.keys():
        thread_id = str(thread_id)
        if args.url and supplied_url_id == thread_id:
            thread_urls[thread_id] = args.url
        elif thread_id in THREADS:
            thread_urls[thread_id] = THREADS[thread_id]
        else:
            raise ValueError(f"unknown thread {thread_id}; additional threads require explicit --thread ID --url URL")
    args.profile.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as playwright:
        context = await playwright.chromium.launch_persistent_context(
            user_data_dir=str(args.profile), channel="msedge", headless=False,
            viewport={"width": 1280, "height": 900},
        )
        page = context.pages[0] if context.pages else await context.new_page()
        complete = True
        try:
            for thread_id, base in thread_urls.items():
                ensure_thread(db, thread_id, base)
                db.commit()
                known_max = 1
                targets = page_targets(args.start_page, known_max, args.pages)
                processed = set()
                while targets - processed:
                    page_num = min(targets - processed)
                    processed.add(page_num)
                    if should_fetch_page(db, thread_id, page_num, args.refresh):
                        url = requested_page_url(base, page_num)
                        discovered = await fetch_one(page, db, args.cache, thread_id, page_num, url, args.delay)
                        if discovered is None:
                            latest = db.execute("SELECT status FROM pages WHERE thread_id=? AND page_num=? ORDER BY page_id DESC LIMIT 1", (thread_id, page_num)).fetchone()
                            reason = latest["status"] if latest else "network error"
                            print(f"Thread {thread_id} stopped at page {page_num} ({reason}); rerun fetch to resume.", flush=True)
                            complete = False
                            break
                        known_max = max(known_max, discovered)
                    if not args.pages:
                        targets.update(page_targets(args.start_page, known_max))
                print(f"Thread {thread_id}: discovered through page {known_max}.", flush=True)
        finally:
            await context.close()
    return complete


def command_fetch(args, db):
    import asyncio
    return 0 if asyncio.run(fetch_threads(args, db)) else 1


def report(db: sqlite3.Connection, query: str | None, limit: int):
    threads = db.execute("""SELECT t.thread_id,t.title,
                           (SELECT count(*) FROM posts po WHERE po.thread_id=t.thread_id) posts,
                           (SELECT count(*) FROM revisions r WHERE r.thread_id=t.thread_id) revisions
                           FROM threads t ORDER BY t.thread_id""").fetchall()
    latest_pages = db.execute("""SELECT p.* FROM pages p WHERE p.page_id=(
                                SELECT max(last.page_id) FROM pages last
                                WHERE last.thread_id=p.thread_id AND last.page_num=p.page_num)
                                ORDER BY p.page_id""").fetchall()
    pages_by_thread: dict[str, list[sqlite3.Row]] = {}
    for page in latest_pages:
        pages_by_thread.setdefault(page["thread_id"], []).append(page)
    documents = db.execute("SELECT count(*) n FROM documents").fetchone()["n"]
    challenges = db.execute("SELECT count(*) n FROM pages WHERE challenged=1").fetchone()["n"]
    print("# XDA research coverage\n")
    print("| Thread | Title | Verified pages | Stored post IDs | Revisions |")
    print("|---|---|---:|---:|---:|")
    for row in threads:
        verified_pages = sum(page_result_complete(row["thread_id"], page["page_num"], page["status"], page["post_count"], page["final_url"])
                             for page in pages_by_thread.get(row["thread_id"], []))
        print(f"| {row['thread_id']} | {row['title'] or ''} | {verified_pages} | {row['posts']} | {row['revisions']} |")
    print(f"\nImported documents: {documents}. Challenge/login pages: {challenges}.")
    gaps = [page for page in latest_pages if not page_result_complete(
        page["thread_id"], page["page_num"], page["status"], page["post_count"], page["final_url"])]
    if gaps:
        print("\n## Coverage gaps and redirects\n")
        for row in reversed(gaps[-limit:]):
            final_page = page_number_for_thread(row["final_url"], row["thread_id"])
            reason = row["error"] or (
                f"redirect resolved to page {final_page}; not counted as coverage"
                if row["status"] == "redirected" and final_page != row["page_num"]
                else "see cached page")
            print(f"- Thread {row['thread_id']} page {row['page_num']}: **{row['status']}** → {row['final_url']} ({reason})")
    redirects = db.execute("SELECT thread_id,page_num,requested_url,final_url,retrieved_at FROM pages WHERE final_url<>requested_url ORDER BY page_id DESC").fetchall()
    if redirects:
        print("\n## Redirect history\n")
        for row in redirects[:limit]:
            print(f"- {row['retrieved_at']}: [{row['requested_url']}]({row['requested_url']}) → [{row['final_url']}]({row['final_url']})")
    if not query:
        print("\nUse `report --query WORDS` to find source-attributed posts and imported document excerpts.")
        return
    term = f"%{query}%"
    matches = db.execute("""SELECT thread_id,post_id,author,posted_at,permalink,author_text,quoted_text,source_label
                             FROM revisions WHERE author_text LIKE ? OR quoted_text LIKE ?
                             ORDER BY COALESCE(posted_at,'') DESC LIMIT ?""", (term, term, limit)).fetchall()
    print(f"\n## Matches for {query!r}\n")
    for row in matches:
        excerpt = clean_text(row["author_text"])
        if query.lower() not in excerpt.lower():
            excerpt = "Quoted: " + clean_text(row["quoted_text"])
        pos = excerpt.lower().find(query.lower())
        excerpt = excerpt[max(0, pos - 100):pos + 260] if pos >= 0 else excerpt[:260]
        print(f"- [{row['thread_id']} post {row['post_id']}]({row['permalink']}) — {row['author'] or 'unknown'}, {row['posted_at'] or 'date unknown'}; {row['source_label']}. {excerpt}")
    docs = db.execute("SELECT source,kind,extracted_text,extraction_status FROM documents WHERE extracted_text LIKE ? LIMIT ?", (term, limit)).fetchall()
    for row in docs:
        text = clean_text(row["extracted_text"])
        pos = text.lower().find(query.lower())
        excerpt = text[max(0, pos - 100):pos + 260]
        print(f"- Document [{row['source']}] — {row['kind']}; {row['extraction_status']}. {excerpt}")
    if not matches and not docs:
        print("No matching source text found.")


def add_common_args(parser):
    parser.add_argument("--db", type=Path, default=ROOT / "research" / "xda.sqlite3", help="SQLite database path")
    parser.add_argument("--cache", type=Path, default=ROOT / "research" / "cache", help="immutable fetched-page and document cache")
    parser.add_argument("--profile", type=Path, default=ROOT / "research" / "browser-profile", help="persistent visible Edge profile")


def main(argv=None) -> int:
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure:
            reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    imp = sub.add_parser("import", help="import the public JSONL archive or a local HTML/PDF evidence file")
    add_common_args(imp)
    imp.add_argument("source", nargs="?", help="archive URL/path or local .html/.pdf; omit for the RM11 archive")
    imp.add_argument("--thread", type=int, default=4780930, help="thread ID for JSONL posts (default: 4780930)")
    fetch = sub.add_parser("fetch", help="sequentially fetch allowlisted XDA threads through visible Edge")
    add_common_args(fetch)
    fetch.add_argument("--thread", action="append", help="thread ID; defaults to the two supplied RedMagic threads")
    fetch.add_argument("--url", help="HTTPS URL for an additional thread")
    fetch.add_argument("--delay", type=float, default=2.0, help="seconds between sequential pages (default: 2)")
    fetch.add_argument("--start-page", type=int, default=1, help="fetch sequentially from this page through the discovered last page")
    fetch.add_argument("--page", dest="pages", action="append", type=int, help="fetch a specific page plus pages 1 and 93; repeatable")
    fetch.add_argument("--refresh", action="store_true", help="refetch all pages; page 1 and 93 refresh by default")
    rep = sub.add_parser("report", help="show coverage and source-attributed search results")
    add_common_args(rep)
    rep.add_argument("--query", help="case-insensitive text search across post revisions and documents")
    rep.add_argument("--limit", type=int, default=30)
    args = parser.parse_args(argv)
    try:
        db = db_connect(args.db)
        try:
            if args.command == "import":
                command_import(args, db)
            elif args.command == "fetch":
                if args.delay < 0 or args.delay > 3600:
                    raise ValueError("--delay must be between 0 and 3600 seconds")
                if args.start_page < 1 or any(page < 1 for page in args.pages or []):
                    raise ValueError("page numbers must be positive")
                return command_fetch(args, db)
            else:
                if args.limit < 1:
                    raise ValueError("--limit must be positive")
                report(db, args.query, args.limit)
        finally:
            db.close()
    except (OSError, ValueError, RuntimeError, sqlite3.Error) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
