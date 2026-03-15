"""
Baker App — EC2 Backend (Flask)
Runs on EC2 instances behind the ALB.
Handles: image upload to S3, result retrieval, health check, DB history
"""

from flask import Flask, jsonify, request
import boto3
import json
import os
import base64
import uuid
import pymysql

app = Flask(__name__)

# ── Config from environment (set by deploy.sh via User Data) ─────────────
REGION      = os.environ.get('AWS_REGION', 'us-east-1')
BUCKET_NAME = os.environ.get('BUCKET_NAME', '')
DB_HOST     = os.environ.get('DB_HOST', '')
DB_NAME     = os.environ.get('DB_NAME', 'bakerapp')
DB_USER     = os.environ.get('DB_USER', 'bakerapp')
DB_PASS     = os.environ.get('DB_PASS', '')

# ── AWS clients ────────────────────────────────────────────────────────────
s3  = boto3.client('s3', region_name=REGION)
rds = None  # lazy connect


def get_db():
    """Get RDS MySQL connection."""
    if not DB_HOST or DB_HOST == 'pending':
        return None
    try:
        conn = pymysql.connect(
            host=DB_HOST, user=DB_USER, password=DB_PASS,
            database=DB_NAME, connect_timeout=5, cursorclass=pymysql.cursors.DictCursor
        )
        return conn
    except Exception as e:
        print(f"DB connect failed: {e}")
        return None


def ensure_table():
    """Create detections table if it doesn't exist."""
    conn = get_db()
    if not conn:
        return
    try:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS detections (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    image_key VARCHAR(500),
                    detected_as VARCHAR(100),
                    confidence FLOAT,
                    is_burnt BOOLEAN DEFAULT FALSE,
                    recipe_name VARCHAR(200),
                    all_labels TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
        conn.commit()
    except Exception as e:
        print(f"Table creation failed: {e}")
    finally:
        conn.close()


# Create table on startup
ensure_table()


# ── Routes ──────────────────────────────────────────────────────────────────

@app.route('/health')
def health():
    """ALB health check endpoint."""
    db_ok = get_db() is not None
    return jsonify({
        "status": "healthy",
        "service": "Baker App",
        "bucket": BUCKET_NAME,
        "rds_connected": db_ok,
        "region": REGION
    })


@app.route('/analyze', methods=['POST'])
def analyze():
    """
    Receive image from frontend, upload to S3.
    Lambda auto-triggers on S3 upload and handles Rekognition.
    This endpoint waits for the result JSON to appear in S3.
    """
    import time

    data = request.get_json()
    if not data or 'image_base64' not in data:
        return jsonify({"error": "No image provided"}), 400

    filename = data.get('filename', f'photo_{uuid.uuid4().hex[:8]}.jpg')
    image_bytes = base64.b64decode(data['image_base64'])

    # Upload to S3 uploads/ folder — this triggers Lambda automatically
    s3_key = f"uploads/{uuid.uuid4().hex[:8]}_{filename}"
    try:
        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=s3_key,
            Body=image_bytes,
            ContentType='image/jpeg'
        )
    except Exception as e:
        return jsonify({"error": f"S3 upload failed: {str(e)}"}), 500

    # Poll S3 for the result JSON (Lambda writes it after Rekognition)
    result_key = s3_key.replace('uploads/', 'results/').rsplit('.', 1)[0] + '_result.json'
    max_wait = 15  # seconds
    interval = 1

    for _ in range(max_wait):
        time.sleep(interval)
        try:
            obj = s3.get_object(Bucket=BUCKET_NAME, Key=result_key)
            result = json.loads(obj['Body'].read())
            return jsonify(result)
        except s3.exceptions.NoSuchKey:
            continue
        except Exception as e:
            continue

    return jsonify({"error": "Analysis timed out — Lambda may still be processing"}), 504


@app.route('/history')
def history():
    """Return detection history from RDS."""
    conn = get_db()
    if not conn:
        return jsonify({"error": "Database not available", "rows": []})

    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT id, image_key, detected_as, confidence,
                       is_burnt, recipe_name, created_at
                FROM detections
                ORDER BY created_at DESC
                LIMIT 20
            """)
            rows = cur.fetchall()
            # Convert datetime to string
            for row in rows:
                if row.get('created_at'):
                    row['created_at'] = str(row['created_at'])
                row['is_burnt'] = bool(row['is_burnt'])
        return jsonify({"rows": rows})
    except Exception as e:
        return jsonify({"error": str(e), "rows": []})
    finally:
        conn.close()


@app.route('/results/<path:filename>')
def get_result(filename):
    """Fetch a specific result JSON from S3."""
    try:
        result_key = f"results/{filename}_result.json"
        obj = s3.get_object(Bucket=BUCKET_NAME, Key=result_key)
        return jsonify(json.loads(obj['Body'].read()))
    except Exception as e:
        return jsonify({"error": str(e)}), 404


@app.route('/')
def index():
    return jsonify({
        "app": "Baker App Backend",
        "status": "running",
        "endpoints": ["/health", "/analyze", "/history", "/results/<filename>"]
    })


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80, debug=False)
