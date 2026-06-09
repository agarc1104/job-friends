from __future__ import annotations

import os
from dataclasses import dataclass

from dotenv import load_dotenv


load_dotenv()


def _split_csv(raw_value: str | None, default: str = "") -> list[str]:
    source = raw_value if raw_value is not None else default
    return [item.strip() for item in source.split(",") if item.strip()]


@dataclass(frozen=True)
class Settings:
    supabase_url: str
    supabase_key: str
    supabase_service_role_key: str
    deepseek_api_key: str
    deepseek_model: str
    deepseek_base_url: str
    deepseek_fallback_models: list[str]
    cv_metadata_table: str
    monetization_events_table: str
    serpapi_api_key: str
    mobile_api_host: str
    mobile_api_port: str
    admob_android_app_id: str
    admob_ios_app_id: str
    admob_android_banner_id: str
    admob_ios_banner_id: str
    admob_android_interstitial_id: str
    admob_ios_interstitial_id: str


settings = Settings(
    supabase_url=os.getenv("SUPABASE_URL", ""),
    supabase_key=os.getenv("SUPABASE_KEY", ""),
    supabase_service_role_key=os.getenv("SUPABASE_SERVICE_ROLE_KEY", ""),
    deepseek_api_key=os.getenv("DEEPSEEK_API_KEY", ""),
    deepseek_model=os.getenv("DEEPSEEK_MODEL", "deepseek-chat"),
    deepseek_base_url=os.getenv("DEEPSEEK_API_BASE_URL", "https://api.deepseek.com"),
    deepseek_fallback_models=_split_csv(
        os.getenv("DEEPSEEK_FALLBACK_MODELS"),
        "",
    ),
    cv_metadata_table=os.getenv("SUPABASE_CV_TABLE", "ApplicantCVs"),
    monetization_events_table=os.getenv("SUPABASE_MONETIZATION_EVENTS_TABLE", "MonetizationEvents"),
    serpapi_api_key=os.getenv("SERPAPI_API_KEY", ""),
    mobile_api_host=os.getenv("MOBILE_API_HOST", "0.0.0.0"),
    mobile_api_port=os.getenv("MOBILE_API_PORT", "8000"),
    admob_android_app_id=os.getenv("ADMOB_ANDROID_APP_ID", ""),
    admob_ios_app_id=os.getenv("ADMOB_IOS_APP_ID", ""),
    admob_android_banner_id=os.getenv("ADMOB_ANDROID_BANNER_ID", ""),
    admob_ios_banner_id=os.getenv("ADMOB_IOS_BANNER_ID", ""),
    admob_android_interstitial_id=os.getenv("ADMOB_ANDROID_INTERSTITIAL_ID", ""),
    admob_ios_interstitial_id=os.getenv("ADMOB_IOS_INTERSTITIAL_ID", ""),
)