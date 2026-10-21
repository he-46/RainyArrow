"""Fetch only official Windows x64 templates from Godot's ranged ZIP archive.

Uses Python's standard library; verifies ZIP CRCs before writing each template.
Run with Python 3. Output stays in the ignored portable Godot tool directory.
"""
import io
import pathlib
import urllib.request
import zipfile

VERSION = "4.7.2"
URL = (
    "https://downloads.godotengine.org/?version="
    + VERSION
    + "&flavor=stable&slug=export_templates.tpz&platform=templates"
)
DESTINATION = (
    pathlib.Path(__file__).resolve().parents[1]
    / ".tools/godot/editor_data/export_templates"
    / (VERSION + ".stable")
)


class RemoteZip(io.RawIOBase):
    def __init__(self):
        super().__init__()
        with urllib.request.urlopen(
            urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0"}, method="HEAD"), timeout=60
        ) as response:
            self.url = response.url
            self.length = int(response.headers["Content-Length"])
        self.position = 0

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=io.SEEK_SET):
        if whence == io.SEEK_CUR:
            offset += self.position
        elif whence == io.SEEK_END:
            offset += self.length
        if offset < 0:
            raise ValueError("Negative seek")
        self.position = offset
        return offset

    def read(self, count=-1):
        end = self.length if count < 0 else min(self.length, self.position + count)
        if end <= self.position:
            return b""
        request = urllib.request.Request(
            self.url, headers={"Range": f"bytes={self.position}-{end - 1}", "User-Agent": "Mozilla/5.0"}
        )
        with urllib.request.urlopen(request, timeout=120) as response:
            expected = f"bytes {self.position}-{end - 1}/{self.length}"
            if response.status != 206 or response.headers.get("Content-Range") != expected:
                raise RuntimeError("Server did not honor range; refusing full download")
            data = response.read(end - self.position + 1)
        if len(data) != end - self.position:
            raise RuntimeError("Incomplete range download")
        self.position = end
        return data


def main():
    DESTINATION.mkdir(parents=True, exist_ok=True)
    with RemoteZip() as remote, zipfile.ZipFile(remote) as archive:
        names = {pathlib.PurePosixPath(name).name: name for name in archive.namelist()}
        for name in ("windows_release_x86_64.exe", "windows_debug_x86_64.exe", "version.txt"):
            if name not in names:
                raise RuntimeError(f"Missing official template: {name}")
            print(f"Downloading {name}", flush=True)
            data = archive.read(names[name])  # ZipFile verifies CRC on full read.
            if name == "version.txt" and data.decode().strip() != VERSION + ".stable":
                raise RuntimeError("Template version mismatch")
            target = DESTINATION / name
            temporary = target.with_suffix(target.suffix + ".tmp")
            temporary.write_bytes(data)
            temporary.replace(target)
            print(f"Verified {name}: {len(data)} bytes", flush=True)


if __name__ == "__main__":
    main()
