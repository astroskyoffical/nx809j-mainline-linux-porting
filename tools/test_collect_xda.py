import json
from io import BytesIO
from contextlib import redirect_stdout
from pathlib import Path
import sqlite3
import tempfile
import unittest
from io import StringIO
from unittest.mock import patch

from tools import collect_xda as collector
from pypdf import PdfWriter
from pypdf.generic import DecodedStreamObject, DictionaryObject, NameObject
from playwright.async_api import TimeoutError as PlaywrightTimeoutError


class CollectorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.db = collector.db_connect(Path(self.temp.name) / "research.sqlite3")

    def tearDown(self):
        self.db.close()
        self.temp.cleanup()

    def test_import_is_idempotent_and_keeps_edit_revisions_and_quotes(self):
        first = {
            "id": "post-123456", "author": "A", "datetime": "2026-08-01T10:00:00Z",
            "permalink": "/t/example.4780930/post-123456",
            "body_md": "Current answer\n\n> quoted advice\n> more quote\n\nhttps://example.com/guide",
        }
        source = (json.dumps(first) + "\n").encode()
        self.assertEqual(collector.import_jsonl(self.db, "fixture.jsonl", source, "4780930"), 1)
        self.assertEqual(collector.import_jsonl(self.db, "fixture.jsonl", source, "4780930"), 1)
        row = self.db.execute("SELECT * FROM posts").fetchone()
        self.assertEqual(row["author_text"], "Current answer\n\nhttps://example.com/guide")
        self.assertEqual(row["quoted_text"], "quoted advice\nmore quote")
        self.assertEqual(self.db.execute("SELECT count(*) FROM revisions").fetchone()[0], 1)
        edited = dict(first, body_md="Updated answer", edited_at="2026-08-02T11:00:00Z")
        collector.import_jsonl(self.db, "fixture.jsonl", (json.dumps(edited) + "\n").encode(), "4780930")
        self.assertEqual(self.db.execute("SELECT count(*) FROM posts").fetchone()[0], 1)
        self.assertEqual(self.db.execute("SELECT count(*) FROM revisions").fetchone()[0], 2)
        self.assertEqual(self.db.execute("SELECT author_text FROM posts").fetchone()[0], "Updated answer")

    def test_volatile_html_changes_do_not_create_revisions_but_body_edits_do(self):
        base = {"thread_id": "4780930", "post_id": "654321", "author": "A",
                "posted_at": "2026-08-01T00:00:00Z", "permalink": "https://xdaforums.com/t/x.4780930/post-654321",
                "author_text": "Same body", "quoted_text": "", "links": [],
                "source_html": '<article data-reaction-count="0">Same body</article>'}
        base["source_hash"] = collector.digest(base["source_html"])
        collector.record_post(self.db, base, "XDA HTML first")
        volatile = dict(base, source_html='<article data-reaction-count="9">Same body</article>')
        volatile["source_hash"] = collector.digest(volatile["source_html"])
        collector.record_post(self.db, volatile, "XDA HTML refresh")
        self.assertEqual(self.db.execute("SELECT count(*) FROM revisions WHERE post_id='654321'").fetchone()[0], 1)
        edited = dict(volatile, author_text="Actually edited body")
        edited["source_hash"] = collector.digest(edited["source_html"] + edited["author_text"])
        collector.record_post(self.db, edited, "XDA HTML edit")
        self.assertEqual(self.db.execute("SELECT count(*) FROM revisions WHERE post_id='654321'").fetchone()[0], 2)

    def test_html_keeps_original_fragment_and_separates_quote_and_links(self):
        page = '''<html><h1 class="p-title-value">Example thread</h1>
        <article class="message js-post" id="js-post-987654" data-author="Ada">
          <div class="message-attribution"><a href="/t/example.4780930/post-987654"><time datetime="2026-08-03T12:00:00Z"></time></a></div>
          <a class="username">Ada</a>
          <div class="bbWrapper">Author text <blockquote><a href="https://source.test/x">Quoted source</a>
          <a href="/t/example.4780930/page-999">quoted page</a></blockquote>
          <a href="https://example.test/next">Next</a></div>
          <div class="message-lastEdit"><time datetime="2026-08-04T12:00:00Z"></time></div>
        </article><nav class="pageNavWrapper"><a href="/t/example.4780930/page-12">12</a>
          <a href="/t/other-thread.4787673/page-168">168</a></nav></html>'''
        parsed = collector.parse_xda_page(page, "4780930", "https://xdaforums.com/t/example.4780930/")
        self.assertEqual(parsed["title"], "Example thread")
        self.assertEqual(parsed["max_page"], 12)
        self.assertEqual(len(parsed["posts"]), 1)
        post = parsed["posts"][0]
        self.assertEqual(post["post_id"], "987654")
        self.assertEqual(post["author"], "Ada")
        self.assertEqual(post["posted_at"], "2026-08-03T12:00:00Z")
        self.assertEqual(post["edited_at"], "2026-08-04T12:00:00Z")
        self.assertEqual(post["author_text"], "Author text Next")
        self.assertEqual(post["quoted_text"], "Quoted source quoted page")
        self.assertEqual(post["permalink"], "https://xdaforums.com/t/example.4780930/post-987654")
        self.assertIn("<article", post["source_html"])
        self.assertTrue(post["source_html"].endswith("</article>"))
        self.assertTrue(any(link["url"] == "https://example.test/next" for link in post["links"]))

    def test_redirect_and_withdrawn_thread_are_history_not_post_deletions(self):
        url = collector.THREADS["4787673"]
        collector.record_post(self.db, {
            "thread_id": "4787673", "post_id": "777777", "author_text": "Older cited instructions",
            "source_markdown": "Older cited instructions", "source_hash": collector.digest("Older cited instructions"),
            "retrieved_at": "2026-08-01T00:00:00Z",
        }, "fixture")
        collector.add_page(self.db, thread_id="4787673", page_num=1, requested_url=url,
                            final_url="https://xdaforums.com/t/delete.4787673/", http_status=200,
                            status="redirected", post_count=0)
        row = self.db.execute("SELECT requested_url,final_url,status FROM pages").fetchone()
        self.assertEqual(row["status"], "redirected")
        self.assertNotEqual(row["requested_url"], row["final_url"])
        self.assertEqual(self.db.execute("SELECT count(*) FROM posts").fetchone()[0], 1)

    def test_challenge_page_with_status_200_is_detected(self):
        result = collector.parse_xda_page("<title>Just a moment...</title><div>Checking your browser</div>", "4780930", "https://xdaforums.com/")
        self.assertTrue(result["challenged"])
        self.assertEqual(result["posts"], [])
        script_only = collector.parse_xda_page("<title>Thread</title><script>captcha verification</script><p>Thread unavailable</p>", "4780930", "https://xdaforums.com/")
        self.assertFalse(script_only["challenged"])

    def test_documents_are_not_fabricated_as_posts_and_resume_rules_refresh_key_pages(self):
        path = Path(self.temp.name) / "page.html"
        data = b"<html><body>saved page about charging</body></html>"
        path.write_bytes(data)
        cache = Path(self.temp.name) / "cache"
        checksum, status = collector.import_document(self.db, str(path), data, "html", cache)
        self.assertEqual(len(checksum), 64)
        self.assertIn("lxml", status)
        self.assertEqual(self.db.execute("SELECT count(*) FROM documents").fetchone()[0], 1)
        self.assertEqual(self.db.execute("SELECT count(*) FROM posts").fetchone()[0], 0)
        self.assertTrue((cache / "documents" / f"{checksum}.html").is_file())
        url = collector.THREADS["4780930"]
        page2 = collector.requested_page_url(url, 2)
        collector.add_page(self.db, thread_id="4780930", page_num=2, requested_url=page2,
                            final_url=page2, http_status=200, status="ok", post_count=1)
        page3 = collector.requested_page_url(url, 3)
        collector.add_page(self.db, thread_id="4780930", page_num=3, requested_url=page3,
                            final_url=page3, http_status=200, status="challenge", challenged=True)
        self.assertTrue(collector.page_complete(self.db, "4780930", 2))
        self.assertFalse(collector.page_complete(self.db, "4780930", 3))
        self.assertFalse(collector.page_complete(self.db, "4780930", 93))
        self.assertFalse(collector.should_fetch_page(self.db, "4780930", 2))
        self.assertTrue(collector.should_fetch_page(self.db, "4780930", 1))
        self.assertTrue(collector.should_fetch_page(self.db, "4780930", 93))
        self.assertTrue(collector.should_fetch_page(self.db, "4780930", 2, refresh=True))
        self.assertEqual(collector.requested_page_url(url, 1), url)
        self.assertTrue(collector.requested_page_url(url, 93).endswith("/page-93"))

    def test_archive_reimport_preserves_newer_live_post_as_current(self):
        live = {
            "thread_id": "4780930", "post_id": "123456", "author": "Ada",
            "author_text": "Current live edit", "source_html": "<article>Current live edit</article>",
            "source_hash": collector.digest("<article>Current live edit</article>"),
            "permalink": "https://xdaforums.com/t/example.4780930/post-123456",
        }
        collector.record_post(self.db, live, "XDA HTML https://xdaforums.com/t/example.4780930/")
        archive = {"id": "post-123456", "author": "Ada", "body_md": "Older August archive text"}
        collector.import_jsonl(self.db, "archive.jsonl", (json.dumps(archive) + "\n").encode(), "4780930")
        self.assertEqual(self.db.execute("SELECT author_text FROM posts WHERE post_id='123456'").fetchone()[0], "Current live edit")
        self.assertEqual(self.db.execute("SELECT count(*) FROM revisions WHERE post_id='123456'").fetchone()[0], 2)

    def test_pdf_text_is_extracted_with_pypdf(self):
        writer = PdfWriter()
        page = writer.add_blank_page(width=300, height=300)
        font = writer._add_object(DictionaryObject({
            NameObject("/Type"): NameObject("/Font"),
            NameObject("/Subtype"): NameObject("/Type1"),
            NameObject("/BaseFont"): NameObject("/Helvetica"),
        }))
        page[NameObject("/Resources")] = DictionaryObject({
            NameObject("/Font"): DictionaryObject({NameObject("/F1"): font})
        })
        content = DecodedStreamObject()
        content.set_data(b"BT /F1 18 Tf 20 100 Td (Linux evidence) Tj ET")
        page[NameObject("/Contents")] = writer._add_object(content)
        pdf = BytesIO()
        writer.write(pdf)
        extracted, status = collector.extract_document_text("pdf", pdf.getvalue())
        self.assertIn("Linux evidence", extracted)
        self.assertIn("pypdf", status)

    def test_empty_and_failed_pages_do_not_count_as_resume_success(self):
        url = collector.THREADS["4780930"]
        for number, status in ((7, "empty"), (8, "http_error"), (9, "challenge")):
            page_url = collector.requested_page_url(url, number)
            collector.add_page(self.db, thread_id="4780930", page_num=number, requested_url=page_url,
                                final_url=page_url, http_status=200, status=status,
                                challenged=status == "challenge")
            self.assertFalse(collector.page_complete(self.db, "4780930", number))
        page10 = collector.requested_page_url(url, 10)
        collector.add_page(self.db, thread_id="4780930", page_num=10, requested_url=page10,
                            final_url="https://xdaforums.com/t/renamed.4780930/", http_status=200,
                            status="redirected", post_count=0)
        self.assertFalse(collector.page_complete(self.db, "4780930", 10))
        page11 = collector.requested_page_url(url, 11)
        collector.add_page(self.db, thread_id="4780930", page_num=11, requested_url=page11,
                            final_url="https://xdaforums.com/t/renamed.4780930/page-11", http_status=200,
                            status="redirected", post_count=1)
        self.assertTrue(collector.page_complete(self.db, "4780930", 11))
        page12 = collector.requested_page_url(url, 12)
        collector.add_page(self.db, thread_id="4780930", page_num=12, requested_url=page12,
                            final_url=collector.requested_page_url(url, 10), http_status=200,
                            status="redirected", post_count=19)
        self.assertFalse(collector.page_complete(self.db, "4780930", 12))

    def test_page_selection_supports_full_incremental_and_referenced_page_runs(self):
        self.assertEqual(collector.page_targets(1, 168), set(range(1, 169)) | {93})
        self.assertEqual(collector.page_targets(160, 168), {1, 93, 160, 161, 162, 163, 164, 165, 166, 167, 168})
        self.assertEqual(collector.page_targets(160, 10), {1})
        self.assertEqual(collector.page_targets(1, 10), set(range(1, 11)))
        self.assertEqual(collector.page_targets(1, 10, [7, 42]), {1, 7, 42})
        self.assertEqual(collector.page_targets(1, 168, [7, 42]), {1, 7, 42, 93})

    def test_report_counts_do_not_multiply_pages_posts_and_revisions(self):
        url = collector.THREADS["4780930"]
        for number in (1, 2):
            page_url = collector.requested_page_url(url, number)
            collector.add_page(self.db, thread_id="4780930", page_num=number, requested_url=page_url,
                                final_url=page_url, http_status=200, status="ok", post_count=2)
        page12, page10 = collector.requested_page_url(url, 12), collector.requested_page_url(url, 10)
        collector.add_page(self.db, thread_id="4780930", page_num=12, requested_url=page12,
                            final_url=page10, http_status=200, status="redirected", post_count=19)
        for post_id in ("111111", "222222"):
            post = {"thread_id": "4780930", "post_id": post_id, "author_text": "initial",
                    "source_markdown": "initial", "source_hash": collector.digest("initial")}
            collector.record_post(self.db, post, "fixture")
        edited = {"thread_id": "4780930", "post_id": "111111", "author_text": "edited",
                  "source_markdown": "edited", "source_hash": collector.digest("edited")}
        collector.record_post(self.db, edited, "fixture")
        output = StringIO()
        with redirect_stdout(output):
            collector.report(self.db, None, 30)
        self.assertIn("| 4780930 |  | 2 | 2 | 3 |", output.getvalue())
        self.assertIn("Stored post IDs", output.getvalue())
        self.assertIn("redirect resolved to page 10; not counted as coverage", output.getvalue())

    def test_fetch_waits_for_posts_before_classifying_a_transient_challenge(self):
        import asyncio

        normal = '''<h1 class="p-title-value">Thread</h1><article class="js-post" id="js-post-345678">
          <div class="message-attribution"><time datetime="2026-08-01T00:00:00Z"></time></div>
          <a class="username">User</a><div class="bbWrapper">Post loaded after browser verification</div>
        </article>'''

        class Response:
            status, headers = 200, {}

        class Page:
            url = collector.requested_page_url(collector.THREADS["4780930"], 161)

            async def goto(self, *_args, **_kwargs):
                return Response()

            async def wait_for_selector(self, selector, state, timeout):
                self.selector, self.state, self.timeout = selector, state, timeout

            async def content(self):
                return normal

        page = Page()
        result = asyncio.run(collector.fetch_one(
            page, self.db, Path(self.temp.name) / "cache", "4780930", 161, page.url, 0,
        ))
        self.assertEqual(result, 1)
        self.assertEqual((page.selector, page.state, page.timeout), ("article.js-post", "attached", 15000))
        self.assertEqual(tuple(self.db.execute("SELECT status,post_count FROM pages").fetchone()), ("ok", 1))

    def test_unresolved_challenge_is_a_gap_and_fetch_exits_nonzero_without_prompting(self):
        import asyncio

        challenge = "<title>Establishing a secure connection</title><body><p>We are checking your browser</p></body>"

        class Response:
            status, headers = 403, {}

        class Page:
            url = collector.requested_page_url(collector.THREADS["4780930"], 161)

            async def goto(self, *_args, **_kwargs):
                return Response()

            async def wait_for_selector(self, *_args, **_kwargs):
                raise PlaywrightTimeoutError("article did not appear")

            async def content(self):
                return challenge

        page = Page()
        result = asyncio.run(collector.fetch_one(
            page, self.db, Path(self.temp.name) / "cache", "4780930", 161, page.url, 0,
        ))
        row = self.db.execute("SELECT status,http_status,challenged FROM pages").fetchone()
        self.assertIsNone(result)
        self.assertEqual(tuple(row), ("challenge", 403, 1))
        self.assertFalse(collector.page_complete(self.db, "4780930", 161))
        def stop_without_running(coroutine):
            coroutine.close()
            return False

        with patch("asyncio.run", side_effect=stop_without_running):
            self.assertEqual(collector.main(["fetch", "--db", str(Path(self.temp.name) / "fetch.sqlite3")]), 1)

    def test_out_of_range_redirect_is_cached_but_never_recorded_as_the_requested_page(self):
        import asyncio

        base = collector.THREADS["4787673"]
        requested = collector.requested_page_url(base, 11)
        content = '''<article class="js-post" id="js-post-456789"><div class="message-attribution">
          <time datetime="2026-08-01T00:00:00Z"></time></div><a class="username">User</a>
          <div class="bbWrapper">This is page ten content.</div></article>'''

        class Response:
            status, headers = 200, {}

        class Page:
            url = collector.requested_page_url(base, 10)

            async def goto(self, *_args, **_kwargs):
                return Response()

            async def wait_for_selector(self, *_args, **_kwargs):
                return None

            async def content(self):
                return content

        result = asyncio.run(collector.fetch_one(
            Page(), self.db, Path(self.temp.name) / "cache", "4787673", 11, requested, 0,
        ))
        row = self.db.execute("SELECT status,post_count,final_url FROM pages").fetchone()
        self.assertIsNone(result)
        self.assertEqual(row["status"], "redirect_mismatch")
        self.assertEqual(row["post_count"], 0)
        self.assertEqual(row["final_url"], collector.requested_page_url(base, 10))
        self.assertEqual(self.db.execute("SELECT count(*) FROM posts").fetchone()[0], 0)
        self.assertFalse(collector.page_complete(self.db, "4787673", 11))


if __name__ == "__main__":
    unittest.main()
