from datetime import date
from typing import Literal
from pydantic import BaseModel, Field, ConfigDict, model_validator
import math

class MetricsRequest(BaseModel):
    model_config=ConfigDict(extra="forbid")
    module: Literal["bosques","hundimiento","glaciares"]
    polygon: list[tuple[float,float]]=Field(min_length=3,max_length=50)
    date_a: date|None=None
    date_b: date|None=None
    min_coherence: float=Field(default=0.3,ge=0,le=1,allow_inf_nan=False)
    assume_vertical: bool=False
    incidence_deg: float|None=Field(default=None,gt=0,lt=80,allow_inf_nan=False)
    @model_validator(mode="after")
    def validate_selection(self):
        if (self.date_a is None) != (self.date_b is None):
            raise ValueError("Indica ambas fechas o ninguna.")
        if self.date_a is not None and not date(2012,9,12)<=self.date_a<self.date_b<=date.today():
            raise ValueError("Elige dos fechas ordenadas, desde 2012-09-12 y no futuras.")
        if len(set(self.polygon))<3:
            raise ValueError("Se necesitan tres vértices distintos.")
        for lat,lon in self.polygon:
            if not (math.isfinite(lat) and math.isfinite(lon) and -85<=lat<=85 and -180<=lon<=180):
                raise ValueError("Coordenadas fuera de los límites admitidos.")
        return self

class InterpretRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    result_id: str
    question: str = Field(default="Explica estas métricas y sus limitaciones.", min_length=1, max_length=1000)
    user_context: str | None = Field(default=None, max_length=1000) # 👈 NUEVO CAMPO