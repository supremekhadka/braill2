from pydantic_settings import BaseSettings, SettingsConfigDict

class InferenceConfig:
    ALLOWED_LANGS = {"en", "np"}

    NEPALI_LABEL_MAP = "configs/nepali_braille.yaml"

    BASE_CONFIG = {
        "model": "runs/train/weights/best.pt",
        "slice_size": 640,
        "overlap": 0.1,
        "confidence": 0.4,
        "nms_iou": 0.1,
        "label_map": "configs/braille.yaml",
    }

    @staticmethod
    def resolve_cfg(lang: str) -> dict:
        cfg = dict(InferenceConfig.BASE_CONFIG)

        if lang == "np":
            cfg["label_map"] = InferenceConfig.NEPALI_LABEL_MAP

        return cfg


class Settings(BaseSettings):
    postgres_user: str
    postgres_password: str
    postgres_db: str
    postgres_port: int
    postgres_host: str

    @property
    def database_url(self):
        return (
            f"postgresql+psycopg2://"
            f"{self.postgres_user}:{self.postgres_password}"
            f"@{self.postgres_host}:{self.postgres_port}"
            f"/{self.postgres_db}"
        )  

    JWT_SECRET_KEY: str
    ACCESS_TOKEN_EXPIRE: int = 60 * 24 * 7 # 7 days
    JWT_ALGORITHM: str

    UPLOAD_DIR: str

    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore"
    )

settings = Settings()