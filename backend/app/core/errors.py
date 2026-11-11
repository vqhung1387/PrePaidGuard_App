from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy.exc import DBAPIError
from starlette.exceptions import HTTPException


class ErrorDetail(BaseModel):
    code: str
    message: str
    details: dict
    request_id: str


class ErrorResponse(BaseModel):
    error: ErrorDetail


ERROR_RESPONSES = {
    status: {"model": ErrorResponse}
    for status in (400, 401, 403, 404, 409, 422, 429, 500, 503)
}


class ApiError(Exception):
    def __init__(
        self, status: int, code: str, message: str, *, headers: dict | None = None
    ):
        super().__init__(code)
        self.status = status
        self.code = code
        self.message = message
        self.headers = headers


def not_found() -> ApiError:
    return ApiError(
        404, "NOT_FOUND", "Không tìm thấy tài nguyên trong phạm vi được phép."
    )


def config_error() -> ApiError:
    return ApiError(503, "CONFIG_MISMATCH", "Deployment chưa có cấu hình hợp lệ.")


def rpc_error() -> ApiError:
    return ApiError(
        503, "RPC_UNAVAILABLE", "Chưa đọc được blockchain. Vui lòng thử lại."
    )


def database_error() -> ApiError:
    return ApiError(503, "DATABASE_UNAVAILABLE", "Database chưa sẵn sàng.")


def register_errors(app: FastAPI) -> None:
    @app.middleware("http")
    async def request_id(request: Request, call_next):
        request.state.request_id = str(uuid4())
        response = await call_next(request)
        response.headers["X-Request-ID"] = request.state.request_id
        return response

    def respond(request: Request, error: ApiError, details: dict | None = None):
        request_id = getattr(request.state, "request_id", str(uuid4()))
        body = ErrorResponse(
            error=ErrorDetail(
                code=error.code,
                message=error.message,
                details=details or {},
                request_id=request_id,
            )
        )
        return JSONResponse(
            body.model_dump(),
            status_code=error.status,
            headers={"X-Request-ID": request_id, **(error.headers or {})},
        )

    @app.exception_handler(ApiError)
    async def api_error(request: Request, error: ApiError):
        return respond(request, error)

    @app.exception_handler(RequestValidationError)
    async def validation_error(request: Request, error: RequestValidationError):
        details = {
            "issues": [
                {"location": list(issue["loc"]), "type": issue["type"]}
                for issue in error.errors()
                if issue["type"] not in {"extra_forbidden", "invalid_key"}
            ]
        }
        return respond(
            request,
            ApiError(422, "VALIDATION_ERROR", "Dữ liệu không đúng schema."),
            details,
        )

    @app.exception_handler(DBAPIError)
    async def unavailable(request: Request, error: DBAPIError):
        return respond(request, database_error())

    @app.exception_handler(HTTPException)
    async def http_error(request: Request, error: HTTPException):
        return respond(
            request,
            not_found()
            if error.status_code == 404
            else ApiError(
                error.status_code,
                "HTTP_ERROR",
                "Yêu cầu không hợp lệ.",
                headers=error.headers,
            ),
        )

    @app.exception_handler(Exception)
    async def internal_error(request: Request, error: Exception):
        return respond(request, ApiError(500, "INTERNAL_ERROR", "Dịch vụ gặp lỗi."))
