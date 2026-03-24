use std::path::Path;
use std::sync::{Arc, Mutex};

use axum::extract::{Path as AxPath, Query, State};
use axum::http::StatusCode;
use axum::routing::get;
use axum::{Json, Router};
use rusqlite::{params, Connection, OpenFlags, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::json;
use tower_http::trace::TraceLayer;

#[derive(Clone)]
struct AppState {
    db: Arc<Mutex<Connection>>,
}

#[derive(Debug, Deserialize)]
struct ListQuery {
    limit: Option<i64>,
    offset: Option<i64>,
}

#[derive(Debug, Serialize)]
struct Item {
    id: i64,
    name: String,
    description: String,
    quantity: i32,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Deserialize)]
struct ItemBody {
    name: Option<String>,
    #[serde(default)]
    description: String,
    #[serde(default)]
    quantity: i32,
}

fn require_name(body: &ItemBody) -> Result<String, (StatusCode, Json<serde_json::Value>)> {
    match &body.name {
        Some(s) => Ok(s.clone()),
        None => Err((
            StatusCode::BAD_REQUEST,
            Json(err_json(
                "field 'name' (string) is required",
                "validation",
            )),
        )),
    }
}

fn migrate(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        r"
        PRAGMA foreign_keys = ON;
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          description TEXT NOT NULL DEFAULT '',
          quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_items_name ON items(name);
    ",
    )?;
    Ok(())
}

fn open_db(path: &str) -> rusqlite::Result<Connection> {
    if let Some(parent) = Path::new(path).parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent).map_err(|e| {
                rusqlite::Error::SqliteFailure(
                    rusqlite::ffi::Error::new(rusqlite::ffi::SQLITE_CANTOPEN),
                    Some(e.to_string()),
                )
            })?;
        }
    }
    let flags = OpenFlags::SQLITE_OPEN_READ_WRITE
        | OpenFlags::SQLITE_OPEN_CREATE
        | OpenFlags::SQLITE_OPEN_FULL_MUTEX;
    let conn = Connection::open_with_flags(path, flags)?;
    conn.busy_timeout(std::time::Duration::from_millis(5000))?;
    migrate(&conn)?;
    Ok(conn)
}

fn err_json(message: &str, code: &str) -> serde_json::Value {
    json!({ "error": message, "code": code })
}

async fn health() -> Json<serde_json::Value> {
    Json(json!({ "status": "ok" }))
}

fn clamp_limit(limit: i64) -> i64 {
    if limit < 1 {
        50
    } else if limit > 500 {
        500
    } else {
        limit
    }
}

async fn list_items(
    State(state): State<AppState>,
    Query(q): Query<ListQuery>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let limit = clamp_limit(q.limit.unwrap_or(50));
    let offset = q.offset.unwrap_or(0).max(0);

    let db = state.db.clone();
    tokio::task::spawn_blocking(move || {
        let conn = db.lock().map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(err_json("db lock poisoned", "internal")),
            )
        })?;

        let mut stmt = conn
            .prepare(
                "SELECT id, name, description, quantity, created_at, updated_at \
                 FROM items ORDER BY id DESC LIMIT ?1 OFFSET ?2",
            )
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(err_json(&e.to_string(), "internal")),
                )
            })?;

        let rows = stmt
            .query_map(params![limit, offset], |r| {
                Ok(Item {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    description: r.get(2)?,
                    quantity: r.get(3)?,
                    created_at: r.get(4)?,
                    updated_at: r.get(5)?,
                })
            })
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(err_json(&e.to_string(), "internal")),
                )
            })?;

        let mut items = Vec::new();
        for row in rows {
            items.push(row.map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(err_json(&e.to_string(), "internal")),
                )
            })?);
        }

        let total: i64 = conn
            .query_row("SELECT COUNT(*) FROM items", [], |r| r.get(0))
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(err_json(&e.to_string(), "internal")),
                )
            })?;

        Ok(Json(json!({ "items": items, "total": total })))
    })
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(err_json(&e.to_string(), "internal")),
        )
    })?
}

async fn get_item(
    State(state): State<AppState>,
    AxPath(id): AxPath<i64>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let db = state.db.clone();
    tokio::task::spawn_blocking(move || {
        let conn = db.lock().map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(err_json("db lock poisoned", "internal")),
            )
        })?;

        let item = conn
            .query_row(
                "SELECT id, name, description, quantity, created_at, updated_at FROM items WHERE id = ?1",
                params![id],
                |r| {
                    Ok(Item {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        description: r.get(2)?,
                        quantity: r.get(3)?,
                        created_at: r.get(4)?,
                        updated_at: r.get(5)?,
                    })
                },
            )
            .optional()
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(err_json(&e.to_string(), "internal")),
                )
            })?;

        match item {
            Some(it) => Ok(Json(serde_json::to_value(it).unwrap())),
            None => Err((
                StatusCode::NOT_FOUND,
                Json(err_json("not found", "not_found")),
            )),
        }
    })
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(err_json(&e.to_string(), "internal")),
        )
    })?
}

async fn create_item(
    State(state): State<AppState>,
    body: String,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let parsed: ItemBody = match serde_json::from_str(if body.is_empty() { "{}" } else { &body }) {
        Ok(b) => b,
        Err(_) => {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(err_json("invalid JSON body", "validation")),
            ));
        }
    };

    let name = require_name(&parsed)?;
    if parsed.quantity < 0 {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(err_json("quantity must be >= 0", "validation")),
        ));
    }

    let db = state.db.clone();
    tokio::task::spawn_blocking(move || {
        let conn = db.lock().map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(err_json("db lock poisoned", "internal")),
            )
        })?;

        conn.execute(
            "INSERT INTO items (name, description, quantity) VALUES (?1, ?2, ?3)",
            params![name, parsed.description, parsed.quantity],
        )
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(err_json(&e.to_string(), "internal")),
            )
        })?;

        let new_id = conn.last_insert_rowid();
        let item = conn
            .query_row(
                "SELECT id, name, description, quantity, created_at, updated_at FROM items WHERE id = ?1",
                params![new_id],
                |r| {
                    Ok(Item {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        description: r.get(2)?,
                        quantity: r.get(3)?,
                        created_at: r.get(4)?,
                        updated_at: r.get(5)?,
                    })
                },
            )
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(err_json(&e.to_string(), "internal")),
                )
            })?;

        Ok((StatusCode::CREATED, Json(serde_json::to_value(item).unwrap())))
    })
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(err_json(&e.to_string(), "internal")),
        )
    })?
}

async fn update_item(
    State(state): State<AppState>,
    AxPath(id): AxPath<i64>,
    body: String,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let parsed: ItemBody = match serde_json::from_str(if body.is_empty() { "{}" } else { &body }) {
        Ok(b) => b,
        Err(_) => {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(err_json("invalid JSON body", "validation")),
            ));
        }
    };

    let name = require_name(&parsed)?;
    if parsed.quantity < 0 {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(err_json("quantity must be >= 0", "validation")),
        ));
    }

    let db = state.db.clone();
    tokio::task::spawn_blocking(move || {
        let conn = db.lock().map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(err_json("db lock poisoned", "internal")),
            )
        })?;

        let n = conn
            .execute(
                "UPDATE items SET name = ?1, description = ?2, quantity = ?3, \
                 updated_at = datetime('now') WHERE id = ?4",
                params![name, parsed.description, parsed.quantity, id],
            )
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(err_json(&e.to_string(), "internal")),
                )
            })?;

        if n == 0 {
            return Err((
                StatusCode::NOT_FOUND,
                Json(err_json("not found", "not_found")),
            ));
        }

        let item = conn
            .query_row(
                "SELECT id, name, description, quantity, created_at, updated_at FROM items WHERE id = ?1",
                params![id],
                |r| {
                    Ok(Item {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        description: r.get(2)?,
                        quantity: r.get(3)?,
                        created_at: r.get(4)?,
                        updated_at: r.get(5)?,
                    })
                },
            )
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(err_json(&e.to_string(), "internal")),
                )
            })?;

        Ok(Json(serde_json::to_value(item).unwrap()))
    })
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(err_json(&e.to_string(), "internal")),
        )
    })?
}

async fn delete_item(
    State(state): State<AppState>,
    AxPath(id): AxPath<i64>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let db = state.db.clone();
    tokio::task::spawn_blocking(move || {
        let conn = db.lock().map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(err_json("db lock poisoned", "internal")),
            )
        })?;

        let n = conn
            .execute("DELETE FROM items WHERE id = ?1", params![id])
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(err_json(&e.to_string(), "internal")),
                )
            })?;

        if n == 0 {
            return Err((
                StatusCode::NOT_FOUND,
                Json(err_json("not found", "not_found")),
            ));
        }

        Ok(Json(json!({ "deleted": true, "id": id })))
    })
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(err_json(&e.to_string(), "internal")),
        )
    })?
}

fn config_port() -> u16 {
    std::env::var("PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .filter(|&p| p > 0)
        .unwrap_or(18080)
}

fn config_bind() -> String {
    std::env::var("BIND_ADDRESS").unwrap_or_else(|_| "0.0.0.0".to_string())
}

fn config_db_path() -> String {
    std::env::var("DB_PATH").unwrap_or_else(|_| "data/app.db".to_string())
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("warn")),
        )
        .init();

    let db_path = config_db_path();
    let conn = open_db(&db_path).map_err(|e| anyhow::anyhow!("sqlite: {e}"))?;
    let state = AppState {
        db: Arc::new(Mutex::new(conn)),
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/api/items", get(list_items).post(create_item))
        .route(
            "/api/items/:id",
            get(get_item).put(update_item).delete(delete_item),
        )
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let addr = format!("{}:{}", config_bind(), config_port());
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    eprintln!("Listening on http://{addr}");
    eprintln!("Database: {db_path}");
    axum::serve(listener, app).await?;
    Ok(())
}
