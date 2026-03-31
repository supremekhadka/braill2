import argparse
import os
from src.data_builder.build import build_dataset
from src.data_builder.split import split_dataset

IGNORE_DIRS = ['.gitignore', 'pics', 'src', 'README.md', 'train.txt', 'val.txt', 'test.txt', 'figures']

def main():
    parser = argparse.ArgumentParser(description="Pipeline to build and split dataset")

    parser.add_argument("--raw_path", type=str, default="data/raw", help="Path to the raw datasets directory")
    parser.add_argument("--target_path", type=str, default="data/dataset", help="Path to the output directory")
    parser.add_argument("--angelina_prefix", type=str, default="ANG", help="Prefix for Angelina dataset")
    parser.add_argument("--dsbi_prefix", type=str, default="DSBI", help="Prefix for DSBI dataset")

    args = parser.parse_args()

    print("Preparing dataset...")
    if not os.path.exists(args.raw_path):
        print(f"Error: Raw path {args.raw_path} does not exist.")
        return

    for item in os.listdir(args.raw_path):
        if item in IGNORE_DIRS:
            continue
        raw_dataset_dir = os.path.join(args.raw_path, item)
        if os.path.isdir(raw_dataset_dir):
            build_dataset(
                raw_dataset_path=raw_dataset_dir, 
                target_dataset_path=args.target_path,
                angelina_prefix=args.angelina_prefix,
                dsbi_prefix=args.dsbi_prefix,
                ignore_dirs=IGNORE_DIRS
            )

    print("Splitting dataset into train/val/test...")
    for sub_dataset in ["cells", "characters"]:
        dataset_dir = os.path.join(args.target_path, sub_dataset)
        if os.path.exists(dataset_dir):
            print(f"Splitting {sub_dataset}...")
            split_dataset(
                dataset_dir=dataset_dir,
                angelina_prefix=args.angelina_prefix,
                dsbi_prefix=args.dsbi_prefix,
                train_ratio=0.6, 
                val_ratio=0.2, 
                test_ratio=0.2
            )
            
    print("Pipeline complete! Dataset is ready at:", args.target_path)

if __name__ == "__main__":
    main()