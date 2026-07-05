import os
import json
import shutil
import datetime
import pathlib


SNAPSHOT_DIR_NAME = "_snapshots"
INDEX_FILE_NAME = "index.json"
DESIGN_EXTENSIONS = {".v", ".sv", ".vhd", ".xdc"}


def _get_snapshot_root(workspace_dir: str) -> pathlib.Path:
    return pathlib.Path(workspace_dir) / SNAPSHOT_DIR_NAME


def _load_index(snapshot_root: pathlib.Path) -> list:
    index_file = snapshot_root / INDEX_FILE_NAME
    if not index_file.exists():
        return []
    try:
        with open(index_file, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return []


def _save_index(snapshot_root: pathlib.Path, index: list) -> None:
    snapshot_root.mkdir(parents=True, exist_ok=True)
    index_file = snapshot_root / INDEX_FILE_NAME
    with open(index_file, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=2)


def _collect_design_files(workspace_dir: str) -> list[pathlib.Path]:
    """Collect all design files recursively, skipping _snapshots directory."""
    root = pathlib.Path(workspace_dir)
    result = []
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in DESIGN_EXTENSIONS:
            # Skip files inside _snapshots to avoid nested snapshot pollution
            try:
                path.relative_to(root / SNAPSHOT_DIR_NAME)
                continue  # it's inside _snapshots, skip
            except ValueError:
                pass
            result.append(path)
    return result


def take_snapshot(label: str, workspace_dir: str) -> str:
    """
    workspace_dir altındaki tüm .v, .sv, .vhd, .xdc dosyalarını
    workspace_dir/_snapshots/YYYYMMDD_HHMMSS_{label}/ klasörüne kopyala.
    Snapshot index'ini _snapshots/index.json dosyasına kaydet.
    Başarıda: "Snapshot alındı: 20260511_083609_stabil\n3 dosya kaydedildi." döndür
    Hata durumunda: "Hata: ..." döndür
    """
    try:
        workspace_path = pathlib.Path(workspace_dir)
        if not workspace_path.exists():
            return f"Hata: Workspace dizini bulunamadı: {workspace_dir}"

        now = datetime.datetime.now()
        timestamp_str = now.strftime("%Y%m%d_%H%M%S")
        snapshot_id = f"{timestamp_str}_{label}"
        timestamp_human = now.strftime("%Y-%m-%d %H:%M:%S")

        snapshot_root = _get_snapshot_root(workspace_dir)
        snapshot_dest = snapshot_root / snapshot_id
        snapshot_dest.mkdir(parents=True, exist_ok=True)

        design_files = _collect_design_files(workspace_dir)
        copied_files = []

        for src_path in design_files:
            # Preserve relative path structure within workspace
            rel_path = src_path.relative_to(workspace_path)
            dest_path = snapshot_dest / rel_path
            dest_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_path, dest_path)
            copied_files.append(str(rel_path))

        # Update index
        index = _load_index(snapshot_root)
        entry = {
            "id": snapshot_id,
            "label": label,
            "timestamp": timestamp_human,
            "files": copied_files,
            "file_count": len(copied_files),
        }
        index.append(entry)
        _save_index(snapshot_root, index)

        return f"Snapshot alındı: {snapshot_id}\n{len(copied_files)} dosya kaydedildi."

    except Exception as e:
        return f"Hata: {e}"


def list_snapshots(workspace_dir: str) -> str:
    """
    _snapshots/index.json okuyarak mevcut snapshotları listele.
    Format:
    TASARIM GEÇMİŞİ:
    1. 20260511_083609_stabil  — 3 dosya  (2026-05-11 08:36:09)
    2. 20260511_091234_sim_ok  — 5 dosya  (2026-05-11 09:12:34)
    Boşsa: "Henüz snapshot alınmamış." döndür
    """
    try:
        snapshot_root = _get_snapshot_root(workspace_dir)
        index = _load_index(snapshot_root)

        if not index:
            return "Henüz snapshot alınmamış."

        lines = ["TASARIM GEÇMİŞİ:"]
        for i, entry in enumerate(index, start=1):
            snapshot_id = entry.get("id", "?")
            file_count = entry.get("file_count", 0)
            timestamp = entry.get("timestamp", "?")
            lines.append(f"{i}. {snapshot_id}  — {file_count} dosya  ({timestamp})")

        return "\n".join(lines)

    except Exception as e:
        return f"Hata: {e}"


def restore_snapshot(label_or_index: str, workspace_dir: str) -> str:
    """
    Verilen label veya sıra numarası ile snapshot'ı geri yükle.
    Mevcut dosyaları önce _snapshots/_before_restore/ altına yedekle.
    Snapshot dosyalarını workspace_dir kökünden uygun yollara geri kopyala.
    Başarıda: "Geri yüklendi: {label}\nDosyalar: ..." döndür
    """
    try:
        workspace_path = pathlib.Path(workspace_dir)
        if not workspace_path.exists():
            return f"Hata: Workspace dizini bulunamadı: {workspace_dir}"

        snapshot_root = _get_snapshot_root(workspace_dir)
        index = _load_index(snapshot_root)

        if not index:
            return "Hata: Hiç snapshot bulunamadı."

        # Resolve the target snapshot entry
        target_entry = None

        # Try as 1-based index number first
        stripped = label_or_index.strip()
        if stripped.isdigit():
            idx = int(stripped) - 1
            if 0 <= idx < len(index):
                target_entry = index[idx]
            else:
                return f"Hata: Geçersiz sıra numarası: {label_or_index} (toplam {len(index)} snapshot var)"
        else:
            # Try exact id match, then label match
            for entry in index:
                if entry.get("id") == stripped or entry.get("label") == stripped:
                    target_entry = entry
                    break
            if target_entry is None:
                return f"Hata: Snapshot bulunamadı: {label_or_index}"

        snapshot_id = target_entry["id"]
        snapshot_src = snapshot_root / snapshot_id

        if not snapshot_src.exists():
            return f"Hata: Snapshot dizini bulunamadı: {snapshot_src}"

        # Backup current design files before restoring
        now = datetime.datetime.now()
        backup_name = now.strftime("%Y%m%d_%H%M%S") + "_before_restore"
        backup_dest = snapshot_root / "_before_restore" / backup_name
        backup_dest.mkdir(parents=True, exist_ok=True)

        current_files = _collect_design_files(workspace_dir)
        for src_path in current_files:
            rel_path = src_path.relative_to(workspace_path)
            dest_path = backup_dest / rel_path
            dest_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_path, dest_path)

        # Restore snapshot files to workspace root
        restored_files = []
        for item in snapshot_src.rglob("*"):
            if item.is_file():
                rel_path = item.relative_to(snapshot_src)
                dest_path = workspace_path / rel_path
                dest_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(item, dest_path)
                restored_files.append(str(rel_path))

        files_list = "\n  ".join(restored_files) if restored_files else "(dosya yok)"
        return (
            f"Geri yüklendi: {snapshot_id}\n"
            f"Dosyalar:\n  {files_list}"
        )

    except Exception as e:
        return f"Hata: {e}"
