from typing import Annotated

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    model_validator,
)


class AnalysisRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    latitude: float | None = Field(default=None, ge=-90, le=90, allow_inf_nan=False)
    longitude: float | None = Field(
        default=None, ge=-180, le=180, allow_inf_nan=False
    )
    polygon: list[tuple[float, float]] | None = Field(
        default=None, min_length=3, max_length=50
    )
    question: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1000)
    ] = "Explica los datos de esta zona y sus limitaciones."

    @model_validator(mode="after")
    def _check_location(self):
        has_point = self.latitude is not None and self.longitude is not None
        has_polygon = self.polygon is not None
        if has_point == has_polygon:
            raise ValueError(
                "Envía latitude/longitude o polygon, no ambos ni ninguno."
            )
        if has_polygon:
            for lat, lng in self.polygon:
                if not (-90 <= lat <= 90 and -180 <= lng <= 180):
                    raise ValueError("Coordenada del polígono fuera de rango.")
        return self


class AnalysisReport(BaseModel):
    summary: str = Field(min_length=1, max_length=3000)
    observations: list[str] = Field(min_length=1, max_length=8)
    limitations: list[str] = Field(min_length=1, max_length=8)
    suggested_next_steps: list[str] = Field(min_length=1, max_length=8)


class AnalysisResponse(BaseModel):
    provider: str = "gemini"
    model: str
    latitude: float
    longitude: float
    data_source: str
    is_simulated: bool
    notice: str
    analysis: AnalysisReport