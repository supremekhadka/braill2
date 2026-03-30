from ultralytics import YOLO

if __name__ == "__main__":
        # Load model
    model = YOLO("weights/yolo26n.pt")

    # Train the model on the dataset specified in the 'data.yaml' file for 100 epochs with an image size of 640x 640 pixels
    results = model.train(data="configs/data.yaml", epochs=100, imgsz=640, batch=8, workers=4, name="yolo26n_braille", augment=True)

    # Run inference with the YOLO26n model on a test image and print the results
    results = model("C:/braill2/data/dataset/images/test/ANG_15e4578a-2295-40ef-969a-a8e8c2c7c740.labeled.jpg")