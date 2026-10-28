from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints


class AnalysisRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    latitude: float = Field(ge=-90, le=90, allow_inf_nan=False)
    longitude: float = Field(ge=-180, le=180, allow_inf_nan=False)
    question: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1000)] = (
        "Explica los datos de esta zona y sus limitaciones."
    )


class AnalysisReport(BaseModel):
    summary: str = Field(min_length=1, max_length=3000)
    observations: list[str] = Field(min_length=1, max_length=8)
    limitations: list[str] = Field(min_length=1, max_length=8)
    suggested_next_steps: list[str] = Field(min_length=1, max_length=8)


class AnalysisResponse(BaseModel):
    provider: Literal["gemini"] = "gemini"
    model: str
    latitude: float
    longitude: float
    data_source: str
    is_simulated: bool
    notice: str
    analysis: AnalysisReport
