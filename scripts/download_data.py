"""Download the Instacart Market Basket Analysis dataset from Kaggle.

Needs a free Kaggle account: put your API token at ~/.kaggle/kaggle.json
(Kaggle -> Account -> Create New Token), then run:

    python scripts/download_data.py

Downloads ~3.2 GB into data/raw/. The files are git-ignored; the warehouse
is built from them by scripts/build_warehouse.py.
"""
import subprocess
import sys
from pathlib import Path

RAW = Path(__file__).resolve().parent.parent / "data" / "raw"
COMPETITION = "instacart-market-basket-analysis"


def main() -> None:
    RAW.mkdir(parents=True, exist_ok=True)
    try:
        import kaggle  # noqa: F401
    except ImportError:
        sys.exit("pip install kaggle, then place your token at ~/.kaggle/kaggle.json")
    print(f"downloading '{COMPETITION}' -> {RAW} ...")
    subprocess.run(
        ["kaggle", "competitions", "download", "-c", COMPETITION,
         "-p", str(RAW)],
        check=True,
    )
    print("unzipping ...")
    subprocess.run(
        [sys.executable, "-c",
         f"import zipfile, pathlib; "
         f"[zipfile.ZipFile(p).extractall('{RAW}') or p.unlink() "
         f"for p in pathlib.Path('{RAW}').glob('*.zip')]"],
        check=True,
    )
    print("done:", sorted(p.name for p in RAW.glob("*.csv")))


if __name__ == "__main__":
    main()
