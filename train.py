import argparse
from email import parser
import os
from ultralytics import YOLO

def main():
    parser = argparse.ArgumentParser(description="Train YOLOv8 model on Braille dataset")
    parser.add_argument("--target", type=str, required=True, choices=["cells", "characters"], help="Target dataset to train on: 'cells' or 'characters'")
    parser.add_argument("--model", type=str, default="yolo26n.pt", help="YOLO model variant to use: 'yolo26n.pt'")
    parser.add_argument("--epochs", type=int, default=100, help="Number of epochs")
    parser.add_argument("--batch", type=int, default=8, help="Batch size")
    parser.add_argument("--imgsz", type=int, default=640, help="Image size for training")
    parser.add_argument("--device", type=str, default="0", help="CUDA device (e.g., '0', '0,1', or 'cpu')")
    parser.add_argument("--data_path", type=str, default="data/dataset", help="Path to the dataset directory containing 'cells' and 'characters' subdirectories")

    args = parser.parse_args()

    data_yaml = os.path.join("configs", f"{args.target}.yaml")

    if not os.path.exists(data_yaml):
        raise FileNotFoundError(
            f"Config file {data_yaml} not found! "
            f"Please create configs/{args.target}.yaml defining your dataset."
        )

    print(f"Loading base model: {args.model}...")
    model = YOLO(f"weights/{args.model}")

    print(f"Starting training for '{args.target.upper()}' using {data_yaml}...")
    
    results = model.train(
        data=data_yaml,
        epochs=args.epochs,
        batch=args.batch,
        imgsz=args.imgsz,
        device=args.device,
        name=f"{args.target}_run",  
        exist_ok=True               
    )

    print(f"Training complete! Weights saved to: runs/{args.target}_run/weights/")

if __name__ == "__main__":
    main()
